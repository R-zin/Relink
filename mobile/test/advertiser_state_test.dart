import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relink_mobile/locator/advertiser_state.dart';
import 'package:relink_mobile/locator/ble_transport.dart';

/// In-memory transport that records the exact order of advertising calls and
/// simulates a slow stop (so any overlap would be observable). No platform
/// channel — mirrors how mesh_manager_test.dart fakes MeshTransportApi.
class FakeBleTransport extends ChangeNotifier implements BleTransportApi {
  BleTransportStatus _status = BleTransportStatus.idle;
  @override
  BleTransportStatus get status => _status;

  final StreamController<BleScanResult> _scans =
      StreamController<BleScanResult>.broadcast();
  @override
  Stream<BleScanResult> get scanResults => _scans.stream;

  /// Ordered log of radio ops: 'adv:<bytes>' and 'stop'.
  final List<String> calls = [];

  /// True while a beacon is (simulated) on-air.
  bool onAir = false;

  @override
  Future<bool> startScan() async => true;
  @override
  Future<void> stopScan() async {}

  @override
  Future<bool> startAdvertising(Uint8List data) async {
    // An overlap bug would show up as startAdvertising while already on-air.
    if (onAir) calls.add('OVERLAP!');
    onAir = true;
    calls.add('adv:${data.length}');
    return true;
  }

  @override
  Future<void> stopAdvertising() async {
    // Simulate a real controller teardown delay.
    await Future.delayed(const Duration(milliseconds: 5));
    onAir = false;
    calls.add('stop');
  }
}

void main() {
  group('AdvertiserState', () {
    test('starts silent', () {
      final t = FakeBleTransport();
      final adv = AdvertiserState(t);
      expect(adv.currentMode, AdvertiserMode.silent);
    });

    test('silent → querying → found → silent sequence, never overlapping',
        () async {
      final t = FakeBleTransport();
      final adv = AdvertiserState(t);

      await adv.broadcastQuery(Uint8List.fromList([1, 2, 3]));
      expect(adv.currentMode, AdvertiserMode.querying);

      await adv.broadcastFound(Uint8List.fromList([4, 5, 6]));
      expect(adv.currentMode, AdvertiserMode.broadcastingFound);

      await adv.goSilent();
      expect(adv.currentMode, AdvertiserMode.silent);

      // Every start is preceded by a completed stop; no OVERLAP marker.
      // Frames are 3 bytes; sequence: stop → adv → stop → adv → stop.
      expect(t.calls, isNot(contains('OVERLAP!')));
      expect(
        t.calls,
        ['stop', 'adv:3', 'stop', 'adv:3', 'stop'],
      );
    });

    test('20 rapid toggles complete strictly ordered with no overlap',
        () async {
      final t = FakeBleTransport();
      final adv = AdvertiserState(t);
      final payload = Uint8List.fromList([9]);

      // Fire 20 alternating transitions without awaiting between them — the
      // serialized chain must still apply them one at a time.
      final futures = <Future<void>>[];
      for (var i = 0; i < 20; i++) {
        futures.add(
            i.isEven ? adv.broadcastFound(payload) : adv.goSilent());
      }
      await Future.wait(futures);

      expect(t.calls, isNot(contains('OVERLAP!')));
      // No 'adv' is immediately followed by another 'adv' without a 'stop'.
      for (var i = 0; i + 1 < t.calls.length; i++) {
        if (t.calls[i].startsWith('adv:')) {
          expect(t.calls[i + 1], 'stop',
              reason: 'advertisement at index $i not torn down before next op');
        }
      }
    });
  });
}
