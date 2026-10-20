import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:relink_mobile/locator/trilateration.dart';

void main() {
  group('Trilateration.trilaterate', () {
    // A known true position and three observation points around it (metres).
    // We forward-simulate the RSSI each observer would measure from the exact
    // distance, then assert the solver recovers a point close to the truth.
    test('recovers a known point from 3 ideal observations', () {
      const truePoint = LatLng(9.9816, 76.2999); // Kochi-ish
      final observers = <LatLng>[
        const LatLng(9.9816 + 0.0005, 76.2999), // ~55 m north
        const LatLng(9.9816 - 0.0004, 76.2999 + 0.0005), // SW-ish
        const LatLng(9.9816 - 0.0004, 76.2999 - 0.0005), // SE-ish
      ];

      const distance = Distance();
      final observations = observers.map((p) {
        final d = distance.as(LengthUnit.Meter, p, truePoint); // metres
        // Invert d = 10^((txPower - rssi)/(10n))  →  rssi = txPower - 10n·log10(d)
        final rssi = (Trilateration.txPowerAt1m -
                10 * Trilateration.pathLossExponent * (log(d) / ln10))
            .round();
        return Observation(lat: p.latitude, lng: p.longitude, rssi: rssi);
      }).toList();

      final estimate = Trilateration.trilaterate(observations);
      expect(estimate, isNotNull);

      final errorM =
          distance.as(LengthUnit.Meter, estimate!, truePoint);
      // Ideal (noise-free) inputs should land within a few metres.
      expect(errorM, lessThan(10.0));
    });

    test('returns null with fewer than 3 observations', () {
      expect(Trilateration.trilaterate(const []), isNull);
      expect(
        Trilateration.trilaterate(const [
          Observation(lat: 9.98, lng: 76.29, rssi: -60),
          Observation(lat: 9.99, lng: 76.30, rssi: -62),
        ]),
        isNull,
      );
    });

    test('returns null for collinear/degenerate anchors', () {
      // Three points on one straight line → the normal-equations matrix is
      // singular and no unique solution exists.
      final observations = <Observation>[
        const Observation(lat: 9.9800, lng: 76.2999, rssi: -60),
        const Observation(lat: 9.9801, lng: 76.2999, rssi: -61),
        const Observation(lat: 9.9802, lng: 76.2999, rssi: -62),
      ];
      expect(Trilateration.trilaterate(observations), isNull);
    });

    test('rssiToDistanceM is monotonic and 1m at txPower', () {
      expect(Trilateration.rssiToDistanceM(Trilateration.txPowerAt1m.round()),
          closeTo(1.0, 1e-6));
      final near = Trilateration.rssiToDistanceM(-50);
      final far = Trilateration.rssiToDistanceM(-80);
      expect(far, greaterThan(near));
    });
  });
}
