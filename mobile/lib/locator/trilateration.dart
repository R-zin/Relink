import 'dart:math';

import 'package:latlong2/latlong.dart';

/// RSSI-based position estimation, deliberately free of any BLE/Android import
/// so it is unit-testable in isolation (task 5).
///
/// Method:
///  1. Convert each observation's RSSI to an estimated distance with the
///     log-distance path-loss model.
///  2. Project every fix into a local tangent plane (equirectangular, centred
///     on the centroid) so we can work in metres instead of degrees.
///  3. Solve a linearized least-squares for the point whose distances to all
///     anchors best match the estimated distances, then project back to lat/lng.
///
/// Accuracy is bounded by BLE path-loss noise — expect tens of metres indoors,
/// not metres. This is a triage aid, not a survey tool.
class Observation {
  final double lat;
  final double lng;
  final int rssi;

  /// Measured TX power (dBm) of the transmitter when the advertisement carried
  /// it; falls back to [Trilateration.txPowerAt1m] when null.
  final int? txPowerLevel;

  const Observation({
    required this.lat,
    required this.lng,
    required this.rssi,
    this.txPowerLevel,
  });
}

class Trilateration {
  Trilateration._();

  /// Measured RSSI at 1 metre (dBm). Calibration placeholder — real value
  /// depends on the transmitting phone's TX power and antenna; tune in the
  /// field. Hackathon scope per master plan.
  static const double txPowerAt1m = -59.0;

  /// Path-loss exponent: 2.0 = free space, higher indoors/obstructed.
  static const double pathLossExponent = 2.0;

  static const double _earthRadiusM = 6371000.0;

  /// Log-distance path-loss inversion: distance (metres) from RSSI. Uses the
  /// transmitter's measured [txPowerLevel] when available, else [txPowerAt1m].
  static double rssiToDistanceM(int rssi, {int? txPowerLevel}) {
    final tx = (txPowerLevel ?? txPowerAt1m.round()).toDouble();
    return pow(10.0, (tx - rssi) / (10.0 * pathLossExponent)).toDouble();
  }

  /// Estimate the transmitter's position from ≥3 observations. Returns null
  /// when there are too few usable points.
  static LatLng? trilaterate(List<Observation> observations) {
    if (observations.length < 3) return null;

    // Local tangent-plane projection about the centroid.
    final centroidLat =
        observations.map((o) => o.lat).reduce((a, b) => a + b) /
            observations.length;
    final centroidLng =
        observations.map((o) => o.lng).reduce((a, b) => a + b) /
            observations.length;
    final cosLat = cos(centroidLat * pi / 180.0);

    // Anchors in metres relative to the centroid.
    final anchors = observations
        .map((o) => _Anchor(
              x: (o.lng - centroidLng) * (pi / 180.0) * _earthRadiusM * cosLat,
              y: (o.lat - centroidLat) * (pi / 180.0) * _earthRadiusM,
              d: rssiToDistanceM(o.rssi, txPowerLevel: o.txPowerLevel),
            ))
        .toList();

    // Linearized least squares. Subtract anchor 0's circle equation from each
    // of the others to get a linear system  A·p ≈ b  where p = (x, y):
    //   2(x_i − x_0)·x + 2(y_i − y_0)·y = (x_i²+y_i²−d_i²) − (x_0²+y_0²−d_0²)
    final a0 = anchors[0];
    final rows = <List<double>>[];
    final rhs = <double>[];
    for (var i = 1; i < anchors.length; i++) {
      final ai = anchors[i];
      rows.add([2 * (ai.x - a0.x), 2 * (ai.y - a0.y)]);
      rhs.add((ai.x * ai.x + ai.y * ai.y - ai.d * ai.d) -
          (a0.x * a0.x + a0.y * a0.y - a0.d * a0.d));
    }

    final solution = _leastSquares2(rows, rhs);
    if (solution == null) return null;

    // Project metres back to lat/lng.
    final dx = solution[0];
    final dy = solution[1];
    final lat = centroidLat + dy / _earthRadiusM * (180.0 / pi);
    final lng = centroidLng + dx / (_earthRadiusM * cosLat) * (180.0 / pi);
    return LatLng(lat, lng);
  }

  /// Solve the 2-unknown least-squares problem min |A p − b| via the normal
  /// equations (AᵀA) p = Aᵀb. Returns [x, y], or null if AᵀA is singular
  /// (collinear anchors).
  static List<double>? _leastSquares2(List<List<double>> a, List<double> b) {
    var sxx = 0.0, sxy = 0.0, syy = 0.0, sx = 0.0, sy = 0.0;
    for (var i = 0; i < a.length; i++) {
      final r0 = a[i][0], r1 = a[i][1];
      sxx += r0 * r0;
      sxy += r0 * r1;
      syy += r1 * r1;
      sx += r0 * b[i];
      sy += r1 * b[i];
    }
    final det = sxx * syy - sxy * sxy;
    if (det.abs() < 1e-9) return null; // degenerate geometry
    final x = (sx * syy - sy * sxy) / det;
    final y = (sxx * sy - sxy * sx) / det;
    return [x, y];
  }
}

class _Anchor {
  final double x;
  final double y;
  final double d;
  const _Anchor({required this.x, required this.y, required this.d});
}
