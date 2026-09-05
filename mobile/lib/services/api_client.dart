import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/alert.dart';
import '../models/cluster.dart';
import '../models/hazard_stats.dart';
import '../models/missing_person.dart';
import '../models/mesh_message.dart';
import '../models/report.dart';
import '../models/shelter.dart';
import '../models/sos_event.dart';

class ApiException implements Exception {
  final int? statusCode;
  final String message;

  ApiException(this.message, {this.statusCode});

  /// Network-level failure (no route, timeout, DNS) — the caller should treat
  /// this as "offline" and leave the message in the outbox, unlike a 4xx
  /// which means the server actively rejected the payload.
  bool get isNetworkError => statusCode == null;

  @override
  String toString() =>
      'ApiException(${statusCode ?? 'network'}): $message';
}

/// Thin HTTP wrapper over the Phase 1 backend.
///
/// The transport is injectable ([postJson]) so tests can run without a
/// network — see `SyncService`.
class ApiClient {
  ApiClient({http.Client? httpClient, String? baseUrl})
      : _http = httpClient ?? http.Client(),
        baseUrl = baseUrl ?? apiBaseUrl;

  final http.Client _http;
  final String baseUrl;

  static const _timeout = Duration(seconds: 10);

  Future<Map<String, dynamic>> postJson(
      String path, Map<String, dynamic> body) async {
    final http.Response res;
    try {
      res = await _http
          .post(
            Uri.parse('$baseUrl$path'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw ApiException('request timed out');
    } on SocketException catch (e) {
      throw ApiException('no connection: ${e.message}');
    } on http.ClientException catch (e) {
      throw ApiException('connection failed: ${e.message}');
    }
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    throw ApiException(
        'server rejected the request (${res.statusCode}): ${res.body}',
        statusCode: res.statusCode);
  }

  Future<dynamic> _get(String path, [Map<String, String>? query]) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    final http.Response res;
    try {
      res = await _http.get(uri).timeout(_timeout);
    } on TimeoutException {
      throw ApiException('request timed out');
    } on SocketException catch (e) {
      throw ApiException('no connection: ${e.message}');
    } on http.ClientException catch (e) {
      throw ApiException('connection failed: ${e.message}');
    }
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return jsonDecode(res.body);
    }
    throw ApiException('GET $path failed (${res.statusCode})',
        statusCode: res.statusCode);
  }

  // --- typed endpoints (Phase 1 contract) ---

  Future<List<SosEvent>> listSos({String? status, int limit = 100}) async {
    final data = await _get('/sos', {
      if (status != null) 'status': status,
      'limit': '$limit',
    }) as List;
    return data
        .map((e) => SosEvent.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<ClusterResult> reportClusters({String? type}) async {
    final data = await _get('/reports/clusters', {
      if (type != null) 'type': type,
    }) as Map<String, dynamic>;
    return ClusterResult.fromJson(data);
  }

  Future<List<Report>> listReports({
    String? type,
    double? lat,
    double? lng,
    double radiusKm = 25,
  }) async {
    final data = await _get('/reports', {
      if (type != null) 'type': type,
      if (lat != null && lng != null) ...{
        'lat': '$lat',
        'lng': '$lng',
        'radius_km': '$radiusKm',
      },
    }) as List;
    return data
        .map((e) => Report.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<List<Shelter>> listShelters({
    double? lat,
    double? lng,
    double radiusKm = 50,
  }) async {
    final data = await _get('/shelters', {
      if (lat != null && lng != null) ...{
        'lat': '$lat',
        'lng': '$lng',
        'radius_km': '$radiusKm',
      },
    }) as List;
    return data
        .map((e) => Shelter.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<List<MissingPerson>> searchMissingPersons({
    String? name,
    double? lat,
    double? lng,
    double radiusKm = 50,
  }) async {
    final data = await _get('/missing-persons/search', {
      if (name != null && name.isNotEmpty) 'name': name,
      if (lat != null && lng != null) ...{
        'lat': '$lat',
        'lng': '$lng',
        'radius_km': '$radiusKm',
      },
    }) as List;
    return data
        .map((e) => MissingPerson.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<void> confirmReport(String id) => postJson('/reports/$id/confirm', {});

  Future<void> confirmShelter(String id) =>
      postJson('/shelters/$id/confirm', {});

  // --- Phase 4: hazard stats / AI review / official alerts ---

  Future<List<Alert>> listAlerts({String state = 'kerala'}) async {
    final data = await _get('/alerts', {'state': state}) as List;
    return data
        .map((e) => Alert.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<HazardStats> getStats({String? region}) async {
    final data = await _get('/stats', {
      if (region != null) 'region': region,
    }) as Map<String, dynamic>;
    return HazardStats.fromJson(data);
  }

  Future<AiReview> getAiReview({String? region}) async {
    final data = await _get('/stats/ai-review', {
      if (region != null) 'region': region,
    }) as Map<String, dynamic>;
    return AiReview.fromJson(data);
  }
}

/// Maps a mesh envelope to the Phase 1 endpoint + request body for its type.
/// Extracted as a pure function so the mapping is unit-testable without any
/// HTTP layer (Phase 2 §10: golden-map assertions).
({String path, Map<String, dynamic> body}) envelopeRequest(MeshMessage msg) {
  final p = msg.payload;
  switch (msg.type) {
    case MessageType.sos:
      return (
        path: '/sos',
        body: {
          'device_id': msg.originDeviceId,
          'client_msg_id': msg.id, // idempotent multi-relay flush (Phase 3)
          'lat': p['lat'],
          'lng': p['lng'],
          if (p['plaintext_medical'] != null)
            'plaintext_medical': p['plaintext_medical'],
          if (p['sensitive_medical'] != null)
            'sensitive_medical': p['sensitive_medical'],
          if (msg.encryptedPayload != null)
            'encrypted_medical': msg.encryptedPayload,
        },
      );
    case MessageType.report:
      return (
        path: '/reports',
        body: {
          'type': p['type'],
          'lat': p['lat'],
          'lng': p['lng'],
          if (p['description'] != null) 'description': p['description'],
          'device_id': msg.originDeviceId,
          'client_msg_id': msg.id, // idempotent multi-relay flush (Phase 3)
        },
      );
    case MessageType.shelter:
      return (
        path: '/shelters',
        body: {
          'name': p['name'],
          'lat': p['lat'],
          'lng': p['lng'],
          if (p['contact_info'] != null) 'contact_info': p['contact_info'],
          'added_by': msg.originDeviceId,
        },
      );
    case MessageType.missingPerson:
      return (
        path: '/missing-persons',
        body: {
          'name': p['name'],
          if (p['last_seen_lat'] != null) 'last_seen_lat': p['last_seen_lat'],
          if (p['last_seen_lng'] != null) 'last_seen_lng': p['last_seen_lng'],
          if (p['description'] != null) 'description': p['description'],
          'reporter_device_id': msg.originDeviceId,
        },
      );
  }
}
