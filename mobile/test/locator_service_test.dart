import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relink_mobile/locator/advertiser_state.dart';
import 'package:relink_mobile/locator/ble_transport.dart';
import 'package:relink_mobile/locator/locator_protocol.dart';
import 'package:relink_mobile/locator/locator_service.dart';
import 'package:relink_mobile/models/medical_profile.dart';
import 'package:relink_mobile/services/location_service.dart';
import 'package:relink_mobile/services/medical_profile_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fake transport: records advertised frames, lets tests push scan results.
class FakeBleTransport extends ChangeNotifier implements BleTransportApi {
  BleTransportStatus _status = BleTransportStatus.idle;
  @override
  BleTransportStatus get status => _status;

  final StreamController<BleScanResult> _scans =
      StreamController<BleScanResult>.broadcast();
  @override
  Stream<BleScanResult> get scanResults => _scans.stream;

  final List<Uint8List> advertised = [];
  bool scanning = false;

  void pushScan(Uint8List frame, {int rssi = -70}) =>
      _scans.add(BleScanResult(
          manufacturerData: frame, rssi: rssi, at: DateTime.now().toUtc()));

  @override
  Future<bool> startScan() async {
    scanning = true;
    return true;
  }

  @override
  Future<void> stopScan() async {
    scanning = false;
  }

  @override
  Future<bool> startAdvertising(Uint8List data) async {
    advertised.add(data);
    return true;
  }

  @override
  Future<void> stopAdvertising() async {}
}

/// A LocationService whose fix always fails — the service tolerates a null
/// position and simply leaves observer coordinates unset.
class _NoFixLocation extends LocationService {
  @override
  Future<LocationResult> getCurrent() async =>
      LocationResult.failed('no fix in test');
}

Future<void> _seedName(String name) async {
  SharedPreferences.setMockInitialValues({
    'relink.medical_profile': MedicalProfile(
      plaintext: PlaintextMedical(name: name),
    ).encode(),
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocatorService victim role', () {
    test('answers a QUERY for its own medical-card name with a FOUND beacon',
        () async {
      await _seedName('Rahul Nair');
      final transport = FakeBleTransport();
      final service = LocatorService(
          transport: transport, locationService: _NoFixLocation());

      expect(await service.armAsTarget(), isTrue);

      final query = await LocatorProtocol.encodeQuery('rahul NAIR', 1);
      transport.pushScan(query);
      await Future.delayed(Duration.zero); // let the scan listener run
      await Future.delayed(Duration.zero);

      expect(transport.advertised, hasLength(1));
      final found = LocatorProtocol.decode(transport.advertised.first)!;
      expect(found.isFound, isTrue);
      expect(found.matchesHash(await LocatorProtocol.personHash('Rahul Nair')),
          isTrue);
    });

    test('ignores a QUERY for a different person', () async {
      await _seedName('Rahul Nair');
      final transport = FakeBleTransport();
      final service = LocatorService(
          transport: transport, locationService: _NoFixLocation());

      await service.armAsTarget();
      transport.pushScan(await LocatorProtocol.encodeQuery('Asha Verma', 1));
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      expect(transport.advertised, isEmpty);
    });

    test('does not answer when not armed', () async {
      await _seedName('Rahul Nair');
      final transport = FakeBleTransport();
      final service = LocatorService(
          transport: transport, locationService: _NoFixLocation());

      transport.pushScan(await LocatorProtocol.encodeQuery('Rahul Nair', 1));
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      expect(transport.advertised, isEmpty);
    });

    test('refuses to arm without a name on the medical card', () async {
      SharedPreferences.setMockInitialValues({});
      final transport = FakeBleTransport();
      final service = LocatorService(
          transport: transport, locationService: _NoFixLocation());

      expect(await service.armAsTarget(), isFalse);
      expect(service.lastError, isNotNull);
    });
  });

  group('LocatorService rescuer role', () {
    test('broadcasts a QUERY beacon and captures FOUND replies with RSSI',
        () async {
      SharedPreferences.setMockInitialValues({});
      final transport = FakeBleTransport();
      final service = LocatorService(
          transport: transport, locationService: _NoFixLocation());

      await service.startQuery('Rahul Nair');
      expect(transport.advertised, hasLength(1));
      expect(LocatorProtocol.decode(transport.advertised.first)!.isQuery,
          isTrue);
      expect(service.advertiser.currentMode, AdvertiserMode.querying);

      transport.pushScan(await LocatorProtocol.encodeFound('Rahul Nair', 1),
          rssi: -63);
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      expect(service.foundSamples, isNotEmpty);
      expect(service.foundSamples.first.rssi, -63);
    });

    test('estimatePosition is null until 3 observers have GPS fixes',
        () async {
      SharedPreferences.setMockInitialValues({});
      final transport = FakeBleTransport();
      final service = LocatorService(
          transport: transport, locationService: _NoFixLocation());

      await service.startQuery('X');
      transport.pushScan(await LocatorProtocol.encodeFound('X', 1), rssi: -60);
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      // _NoFixLocation never supplies coordinates → no usable observations.
      expect(service.estimatePosition(), isNull);
    });
  });
}
