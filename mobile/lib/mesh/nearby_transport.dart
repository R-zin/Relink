import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';

enum MeshTransportStatus {
  idle,
  requestingPermissions,
  running,
  permissionDenied,
  error,
}

class PeerInfo {
  final String endpointId;
  final String deviceId;
  final DateTime connectedAt;

  PeerInfo({
    required this.endpointId,
    required this.deviceId,
    required this.connectedAt,
  });
}

/// The surface [MeshManager] needs from a mesh transport. Abstracting it lets
/// unit tests drive the flooding engine with an in-memory fake (the real
/// [NearbyTransport] constructs the Nearby Connections plugin, which needs a
/// platform channel that doesn't exist in `flutter test`).
abstract class MeshTransportApi implements Listenable {
  MeshTransportStatus get status;
  int get peerCount;

  /// Reverse-chronological transport event log (used by the debug viewer).
  List<String> get eventLog;

  Future<void> Function(String endpointId, Uint8List bytes)? onPayloadReceived;
  void Function(PeerInfo peer)? onPeerConnected;
  void Function(String endpointId)? onPeerDisconnected;

  Future<bool> start();
  Future<void> stop();
  Future<int> broadcastBytes(Uint8List bytes, {String? exceptEndpointId});
  Future<void> sendToEndpoint(String endpointId, Uint8List bytes);

  /// Debug viewer hook: send a plain UTF-8 text ping to every peer.
  Future<int> sendTestMessage(String message);
}

/// Thin, resilient wrapper around Google Nearby Connections API.
/// Uses Strategy.P2P_CLUSTER with serviceId 'in.relink.mesh'.
class NearbyTransport extends ChangeNotifier implements MeshTransportApi {
  static const String serviceId = 'in.relink.mesh';
  static const Strategy strategy = Strategy.P2P_CLUSTER;

  final String localDeviceId;
  final Nearby _nearby = Nearby();

  MeshTransportStatus _status = MeshTransportStatus.idle;
  @override
  MeshTransportStatus get status => _status;

  final Map<String, PeerInfo> _connectedPeers = {};
  Map<String, PeerInfo> get connectedPeers => Map.unmodifiable(_connectedPeers);
  @override
  int get peerCount => _connectedPeers.length;

  final List<String> _eventLog = [];
  @override
  List<String> get eventLog => List.unmodifiable(_eventLog);

  // Callbacks for higher layer (flooding engine / probe). Returns a Future so
  // callers (and tests) can await full handling of the payload; the BLE path
  // ignores the return value.
  @override
  Future<void> Function(String endpointId, Uint8List bytes)? onPayloadReceived;
  @override
  void Function(PeerInfo peer)? onPeerConnected;
  @override
  void Function(String endpointId)? onPeerDisconnected;

  NearbyTransport({required this.localDeviceId});

  void _log(String msg) {
    final time = DateTime.now().toIso8601String().split('T')[1].split('.')[0];
    final line = '[$time] $msg';
    _eventLog.insert(0, line);
    if (_eventLog.length > 100) _eventLog.removeLast();
    if (kDebugMode) debugPrint('[NearbyTransport] $line');
    notifyListeners();
  }

  /// Request all needed Bluetooth and Location permissions.
  Future<bool> checkAndRequestPermissions() async {
    _status = MeshTransportStatus.requestingPermissions;
    notifyListeners();

    try {
      final permissions = [
        Permission.bluetoothScan,
        Permission.bluetoothAdvertise,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
        Permission.nearbyWifiDevices,
      ];

      final statuses = await permissions.request();
      final locGranted = statuses[Permission.locationWhenInUse]?.isGranted ?? false;

      _log('Permissions: loc=$locGranted, btScan=${statuses[Permission.bluetoothScan]}');

      if (!locGranted) {
        _status = MeshTransportStatus.permissionDenied;
        notifyListeners();
        return false;
      }
      return true;
    } catch (e) {
      _log('Permission request error: $e');
      _status = MeshTransportStatus.error;
      notifyListeners();
      return false;
    }
  }

  /// Start concurrent advertising and discovery for P2P cluster.
  @override
  Future<bool> start() async {
    final hasPermissions = await checkAndRequestPermissions();
    if (!hasPermissions) {
      _log('Cannot start mesh: permissions not granted');
      return false;
    }

    try {
      _log('Starting advertising ($localDeviceId)...');
      final advOk = await _nearby.startAdvertising(
        localDeviceId,
        strategy,
        onConnectionInitiated: _handleConnectionInitiated,
        onConnectionResult: _handleConnectionResult,
        onDisconnected: _handleDisconnected,
        serviceId: serviceId,
      );

      _log('Starting discovery...');
      final discOk = await _nearby.startDiscovery(
        localDeviceId,
        strategy,
        onEndpointFound: _handleEndpointFound,
        onEndpointLost: _handleEndpointLost,
        serviceId: serviceId,
      );

      if (advOk && discOk) {
        _status = MeshTransportStatus.running;
        _log('Mesh transport active (P2P_CLUSTER)');
        notifyListeners();
        return true;
      } else {
        _log('Start failed: adv=$advOk, disc=$discOk');
        _status = MeshTransportStatus.error;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _log('Error starting transport: $e');
      _status = MeshTransportStatus.error;
      notifyListeners();
      return false;
    }
  }

  /// Stop mesh radios and disconnect peers.
  @override
  Future<void> stop() async {
    try {
      await _nearby.stopAdvertising();
      await _nearby.stopDiscovery();
      await _nearby.stopAllEndpoints();
      _connectedPeers.clear();
      _status = MeshTransportStatus.idle;
      _log('Mesh transport stopped');
      notifyListeners();
    } catch (e) {
      _log('Error stopping transport: $e');
    }
  }

  void _handleEndpointFound(String endpointId, String endpointName, String sId) {
    _log('Peer found: $endpointName ($endpointId)');

    // Collision tie-breaker:
    // When Phone A and Phone B discover each other at the same time,
    // only the device with lexicographically smaller ID calls requestConnection.
    if (localDeviceId.compareTo(endpointName) < 0) {
      _log('Initiating connection to $endpointName...');
      _nearby.requestConnection(
        localDeviceId,
        endpointId,
        onConnectionInitiated: _handleConnectionInitiated,
        onConnectionResult: _handleConnectionResult,
        onDisconnected: _handleDisconnected,
      ).catchError((err) {
        _log('requestConnection error: $err');
        return false;
      });
    } else {
      _log('Awaiting connection request from $endpointName (tie-breaker)...');
    }
  }

  void _handleEndpointLost(String? endpointId) {
    _log('Peer lost from discovery: $endpointId');
  }

  void _handleConnectionInitiated(String endpointId, ConnectionInfo info) {
    _log('Connection initiated from ${info.endpointName} ($endpointId) — auto-accepting');

    _nearby.acceptConnection(
      endpointId,
      onPayLoadRecieved: (epId, payload) {
        if (payload.type == PayloadType.BYTES && payload.bytes != null) {
          _log('Received bytes (${payload.bytes!.length} B) from $epId');
          onPayloadReceived?.call(epId, payload.bytes!);
        }
      },
      onPayloadTransferUpdate: (epId, update) {
        // Transfer progress updates if needed
      },
    ).catchError((err) {
      _log('acceptConnection error: $err');
      return false;
    });
  }

  void _handleConnectionResult(String endpointId, Status status) {
    _log('Connection result with $endpointId: $status');
    if (status == Status.CONNECTED) {
      final peer = PeerInfo(
        endpointId: endpointId,
        deviceId: endpointId,
        connectedAt: DateTime.now(),
      );
      _connectedPeers[endpointId] = peer;
      onPeerConnected?.call(peer);
      notifyListeners();
    } else {
      _connectedPeers.remove(endpointId);
      notifyListeners();
    }
  }

  void _handleDisconnected(String endpointId) {
    _log('Disconnected from peer: $endpointId');
    _connectedPeers.remove(endpointId);
    onPeerDisconnected?.call(endpointId);
    notifyListeners();
  }

  /// Send bytes to a single connected peer by endpointId (used by the
  /// peer-greeting burst sync).
  @override
  Future<void> sendToEndpoint(String endpointId, Uint8List bytes) async {
    await _nearby.sendBytesPayload(endpointId, bytes);
  }

  /// Broadcast bytes to all connected peers, optionally excluding sender.
  @override
  Future<int> broadcastBytes(Uint8List bytes, {String? exceptEndpointId}) async {
    int sentCount = 0;
    for (final peerId in _connectedPeers.keys) {
      if (exceptEndpointId != null && peerId == exceptEndpointId) continue;
      try {
        await _nearby.sendBytesPayload(peerId, bytes);
        sentCount++;
      } catch (e) {
        _log('Error sending to $peerId: $e');
      }
    }
    return sentCount;
  }

  /// Send a test text string to all peers.
  @override
  Future<int> sendTestMessage(String message) async {
    final bytes = Uint8List.fromList(utf8.encode(message));
    final count = await broadcastBytes(bytes);
    _log('Sent "$message" to $count peers');
    return count;
  }
}
