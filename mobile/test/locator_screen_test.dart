import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:relink_mobile/locator/ble_transport.dart';
import 'package:relink_mobile/locator/locator_service.dart';
import 'package:relink_mobile/screens/locator/locator_screen.dart';
import 'package:relink_mobile/services/location_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Minimal fake transport for widget tests — no platform channel.
class _FakeTransport extends ChangeNotifier implements BleTransportApi {
  BleTransportStatus _status = BleTransportStatus.idle;
  @override
  BleTransportStatus get status => _status;

  final StreamController<BleScanResult> _scans =
      StreamController<BleScanResult>.broadcast();
  @override
  Stream<BleScanResult> get scanResults => _scans.stream;

  final List<Uint8List> advertised = [];

  @override
  Future<bool> startScan() async => true;
  @override
  Future<void> stopScan() async {}
  @override
  Future<bool> startAdvertising(Uint8List data) async {
    advertised.add(data);
    return true;
  }

  @override
  Future<void> stopAdvertising() async {}
}

class _NoFixLocation extends LocationService {
  @override
  Future<LocationResult> getCurrent() async =>
      LocationResult.failed('no fix in test');
}

Widget _harness(LocatorService service) => MaterialApp(
      home: ChangeNotifierProvider<LocatorService>.value(
        value: service,
        child: const Scaffold(body: LocatorScreen()),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('role switch toggles between Find and Be-findable panels',
      (tester) async {
    final service =
        LocatorService(transport: _FakeTransport(), locationService: _NoFixLocation());
    await tester.pumpWidget(_harness(service));

    // Default: Find panel visible.
    expect(find.text("Person's name"), findsOneWidget);
    expect(find.text('Start searching'), findsOneWidget);

    // Switch to Be findable.
    await tester.tap(find.text('Be findable'));
    await tester.pumpAndSettle();
    expect(find.text('You are not findable'), findsOneWidget);

    // Switch back.
    await tester.tap(find.text('Find someone'));
    await tester.pumpAndSettle();
    expect(find.text("Person's name"), findsOneWidget);
  });

  testWidgets('Start searching broadcasts a QUERY beacon', (tester) async {
    final transport = _FakeTransport();
    final service =
        LocatorService(transport: transport, locationService: _NoFixLocation());
    await tester.pumpWidget(_harness(service));

    await tester.enterText(find.byType(TextField), 'Rahul Nair');
    await tester.tap(find.text('Start searching'));
    await tester.pumpAndSettle();

    expect(transport.advertised, hasLength(1));
    expect(find.text('Stop searching'), findsOneWidget);
  });

  testWidgets('searching without a name shows a toast and does not broadcast',
      (tester) async {
    final transport = _FakeTransport();
    final service =
        LocatorService(transport: transport, locationService: _NoFixLocation());
    await tester.pumpWidget(_harness(service));

    await tester.tap(find.text('Start searching'));
    await tester.pumpAndSettle();

    expect(transport.advertised, isEmpty);
    expect(find.text("Type the person's name first"), findsOneWidget);
  });
}
