import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

/// Represents a modeled flood/landslide susceptibility polygon derived from the ML engine.
class RiskPolygon {
  final List<LatLng> points;
  final List<List<LatLng>>? holePointsList;
  final int riskClass;
  final String riskName;
  final double? probMean;
  final double? probMax;
  final double? areaKm2;

  const RiskPolygon({
    required this.points,
    this.holePointsList,
    required this.riskClass,
    required this.riskName,
    this.probMean,
    this.probMax,
    this.areaKm2,
  });

  bool get isVeryHigh => riskClass == 5;

  /// Palette compliant with CLAUDE.md §2 (Alarm red reserved exclusively for SOS).
  /// Class 4 (High): warm amber; Class 5 (Very High): deep plum/purple.
  Color get themeColor =>
      isVeryHigh ? const Color(0xFF7B0177) : const Color(0xFFE8803A);

  String get formattedProbability {
    if (probMean != null) {
      return '${(probMean! * 100).toStringAsFixed(1)}%';
    }
    return 'N/A';
  }

  String get formattedArea {
    if (areaKm2 != null) {
      return '${areaKm2!.toStringAsFixed(2)} km²';
    }
    return 'N/A';
  }

  bool contains(LatLng point) {
    if (!_pointInPolygon(point.longitude, point.latitude, points)) {
      return false;
    }
    if (holePointsList != null) {
      for (final hole in holePointsList!) {
        if (_pointInPolygon(point.longitude, point.latitude, hole)) {
          return false;
        }
      }
    }
    return true;
  }
}

bool _pointInPolygon(double x, double y, List<LatLng> ring) {
  bool inside = false;
  final n = ring.length;
  if (n < 3) return false;
  var p1 = ring[0];
  for (int i = 1; i <= n; i++) {
    final p2 = ring[i % n];
    if (y > (p1.latitude < p2.latitude ? p1.latitude : p2.latitude)) {
      if (y <= (p1.latitude > p2.latitude ? p1.latitude : p2.latitude)) {
        if (x <= (p1.longitude > p2.longitude ? p1.longitude : p2.longitude)) {
          if (p1.latitude != p2.latitude) {
            final xinters = (y - p1.latitude) *
                    (p2.longitude - p1.longitude) /
                    (p2.latitude - p1.latitude) +
                p1.longitude;
            if (p1.longitude == p2.longitude || x <= xinters) {
              inside = !inside;
            }
          }
        }
      }
    }
    p1 = p2;
  }
  return inside;
}

/// Standalone top-level function suitable for execution inside a Flutter background
/// isolate via [compute] so large GeoJSON collections do not jank the main UI thread.
List<RiskPolygon> parseRiskPolygons(String rawJson) {
  final Map<String, dynamic> data = jsonDecode(rawJson) as Map<String, dynamic>;
  final features = data['features'] as List<dynamic>? ?? [];
  final List<RiskPolygon> result = [];

  for (final f in features) {
    if (f is! Map<String, dynamic>) continue;
    final props = f['properties'] as Map<String, dynamic>? ?? {};
    final geom = f['geometry'] as Map<String, dynamic>? ?? {};

    final riskClass = props['risk_class'] as int? ?? 4;
    final riskName = props['risk_name'] as String? ?? (riskClass == 5 ? 'Very High' : 'High');
    final probMean = (props['prob_mean'] as num?)?.toDouble();
    final probMax = (props['prob_max'] as num?)?.toDouble();
    final areaKm2 = (props['area_km2'] as num?)?.toDouble();

    final gtype = geom['type'] as String?;
    final coords = geom['coordinates'] as List<dynamic>? ?? [];

    if (gtype == 'Polygon' && coords.isNotEmpty) {
      final outerList = coords[0] as List<dynamic>;
      final points = _coordsToLatLng(outerList);
      List<List<LatLng>>? holes;
      if (coords.length > 1) {
        holes = [
          for (int i = 1; i < coords.length; i++)
            _coordsToLatLng(coords[i] as List<dynamic>)
        ];
      }
      if (points.isNotEmpty) {
        result.add(RiskPolygon(
          points: points,
          holePointsList: holes,
          riskClass: riskClass,
          riskName: riskName,
          probMean: probMean,
          probMax: probMax,
          areaKm2: areaKm2,
        ));
      }
    } else if (gtype == 'MultiPolygon' && coords.isNotEmpty) {
      for (final poly in coords) {
        if (poly is! List<dynamic> || poly.isEmpty) continue;
        final outerList = poly[0] as List<dynamic>;
        final points = _coordsToLatLng(outerList);
        List<List<LatLng>>? holes;
        if (poly.length > 1) {
          holes = [
            for (int i = 1; i < poly.length; i++)
              _coordsToLatLng(poly[i] as List<dynamic>)
          ];
        }
        if (points.isNotEmpty) {
          result.add(RiskPolygon(
            points: points,
            holePointsList: holes,
            riskClass: riskClass,
            riskName: riskName,
            probMean: probMean,
            probMax: probMax,
            areaKm2: areaKm2,
          ));
        }
      }
    }
  }

  return result;
}

List<LatLng> _coordsToLatLng(List<dynamic> ring) {
  final List<LatLng> pts = [];
  for (final pt in ring) {
    if (pt is List<dynamic> && pt.length >= 2) {
      final lng = (pt[0] as num).toDouble();
      final lat = (pt[1] as num).toDouble();
      pts.add(LatLng(lat, lng));
    }
  }
  return pts;
}
