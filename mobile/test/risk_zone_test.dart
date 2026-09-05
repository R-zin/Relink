import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:relink_mobile/models/risk_zone.dart';
import 'package:relink_mobile/theme.dart';

void main() {
  const sampleGeoJson = '''
  {
    "type": "FeatureCollection",
    "features": [
      {
        "type": "Feature",
        "properties": {
          "risk_class": 4,
          "risk_name": "High",
          "prob_mean": 0.65,
          "prob_max": 0.72,
          "area_km2": 1.25
        },
        "geometry": {
          "type": "Polygon",
          "coordinates": [
            [
              [76.0, 10.0],
              [76.2, 10.0],
              [76.2, 10.2],
              [76.0, 10.2],
              [76.0, 10.0]
            ]
          ]
        }
      },
      {
        "type": "Feature",
        "properties": {
          "risk_class": 5,
          "risk_name": "Very High",
          "prob_mean": 0.88,
          "prob_max": 0.95,
          "area_km2": 3.40
        },
        "geometry": {
          "type": "Polygon",
          "coordinates": [
            [
              [77.0, 9.0],
              [77.1, 9.0],
              [77.1, 9.1],
              [77.0, 9.1],
              [77.0, 9.0]
            ]
          ]
        }
      }
    ]
  }
  ''';

  test('parseRiskPolygons parses GeoJSON polygons and attributes', () {
    final polygons = parseRiskPolygons(sampleGeoJson);
    expect(polygons.length, 2);

    final p1 = polygons[0];
    expect(p1.riskClass, 4);
    expect(p1.riskName, 'High');
    expect(p1.probMean, 0.65);
    expect(p1.areaKm2, 1.25);
    expect(p1.points.length, 5);
    expect(p1.isVeryHigh, isFalse);

    final p2 = polygons[1];
    expect(p2.riskClass, 5);
    expect(p2.riskName, 'Very High');
    expect(p2.isVeryHigh, isTrue);
  });

  test('RiskPolygon.contains accurately identifies points inside and outside', () {
    final polygons = parseRiskPolygons(sampleGeoJson);
    final p1 = polygons[0];

    // Inside polygon 1: [76.0 - 76.2, 10.0 - 10.2]
    expect(p1.contains(const LatLng(10.1, 76.1)), isTrue);

    // Outside polygon 1
    expect(p1.contains(const LatLng(10.5, 76.1)), isFalse);
    expect(p1.contains(const LatLng(9.5, 76.1)), isFalse);
  });

  test('RiskPolygon theme colors respect CLAUDE.md §2 alarm-red reservation', () {
    final polygons = parseRiskPolygons(sampleGeoJson);
    for (final poly in polygons) {
      // Alarm red MUST remain reserved for SOS beacons and Severe alert badges only
      expect(poly.themeColor, isNot(equals(RelinkColors.alarmRed)));
    }
  });
}
