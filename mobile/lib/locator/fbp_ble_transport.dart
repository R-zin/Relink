import 'dart:async';
import 'dart:typed_data';

import 'package:ble_peripheral/ble_peripheral.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:permission_handler/permission_handler.dart';

import 'ble_transport.dart';
import 'locator_protocol.dart';

/// Raw-BLE transport for the locator.
///
/// Two plugins, one radio:
///  * **Scan** — `flutter_blue_plus`, with a **service-UUID filter**
///    ([LocatorProtocol.locatorServiceUuid]). Android only guarantees
///    background-capable scan delivery for UUID-filtered scans, and the filter
///    keeps the mesh's Nearby Connections traffic out of this stream.
///  * **Advertise** — `ble_peripheral` (flutter_blue_plus is central/scan-only
///    and has no advertising API). The QUERY/FOUND frame rides in manufacturer
///    data, with the locator service UUID in the primary advertisement (which
///    is what the scanner's `withServices` filter matches). Note: this plugin
///    hardcodes connectable advertisements — harmless to the locator (peers
///    only read the beacon, they don't connect), but the advertisement is not
///    strictly non-connectable.
///
/// Coexistence: this shares the BLE controller with `NearbyTransport` (mesh)
/// the way any two short BLE operations do — the Android stack time-slices
/// them. They never share a GATT connection, a service id, or a scan stream.
class FbpBleTransport extends ChangeNotifier implements BleTransportApi {
  BleTransportStatus _status = BleTransportStatus.idle;
  @override
  BleTransportStatus get status => _status;

  bool _scanning = false;
  bool _advertising = false;
  bool _peripheralInitialized = false;

  final StreamController<BleScanResult> _scanController =
      StreamController<BleScanResult>.broadcast();
  StreamSubscription<List<fbp.ScanResult>>? _fbpScanSub;

  @override
  Stream<BleScanResult> get scanResults => _scanController.stream;

  void _setStatus(BleTransportStatus s) {
    _status = s;
    notifyListeners();
  }

  Future<bool> _ensurePermissions() async {
    _setStatus(BleTransportStatus.requestingPermissions);
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    final ok = statuses.values.every((s) => s.isGranted);
    if (!ok) _setStatus(BleTransportStatus.error);
    return ok;
  }

  @override
  Future<bool> startScan() async {
    if (_scanning) return true;
    if (!await _ensurePermissions()) return false;
    try {
      // Filter by the locator service UUID so only our advertisements surface.
      await fbp.FlutterBluePlus.startScan(
        withServices: [fbp.Guid(LocatorProtocol.locatorServiceUuid)],
      );
      _fbpScanSub ??= fbp.FlutterBluePlus.onScanResults.listen((results) {
        for (final r in results) {
          final data = r.advertisementData
              .manufacturerData[LocatorProtocol.manufacturerCompanyId];
          if (data == null) continue;
          _scanController.add(BleScanResult(
            manufacturerData: Uint8List.fromList(data),
            rssi: r.rssi,
            at: DateTime.now().toUtc(),
            txPowerLevel: r.advertisementData.txPowerLevel,
          ));
        }
      });
      _scanning = true;
      _setStatus(BleTransportStatus.scanning);
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[FbpBleTransport] startScan error: $e');
      _setStatus(BleTransportStatus.error);
      return false;
    }
  }

  @override
  Future<void> stopScan() async {
    if (!_scanning) return;
    try {
      await fbp.FlutterBluePlus.stopScan();
    } catch (e) {
      if (kDebugMode) debugPrint('[FbpBleTransport] stopScan error: $e');
    }
    _scanning = false;
    if (!_advertising) _setStatus(BleTransportStatus.idle);
  }

  @override
  Future<bool> startAdvertising(Uint8List manufacturerData) async {
    if (!await _ensurePermissions()) return false;
    try {
      if (!_peripheralInitialized) {
        await BlePeripheral.initialize();
        _peripheralInitialized = true;
      }
      await BlePeripheral.startAdvertising(
        services: [LocatorProtocol.locatorServiceUuid],
        manufacturerData: ManufacturerData(
          manufacturerId: LocatorProtocol.manufacturerCompanyId,
          data: manufacturerData,
        ),
      );
      _advertising = true;
      _setStatus(BleTransportStatus.advertising);
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[FbpBleTransport] startAdvertising error: $e');
      _advertising = false;
      _setStatus(BleTransportStatus.error);
      return false;
    }
  }

  @override
  Future<void> stopAdvertising() async {
    if (!_advertising) return;
    try {
      // Resolves once the controller has dropped the previous beacon — the
      // AdvertiserState machine depends on this to prevent beacon overlap.
      await BlePeripheral.stopAdvertising();
    } catch (e) {
      if (kDebugMode) debugPrint('[FbpBleTransport] stopAdvertising error: $e');
    }
    _advertising = false;
    if (!_scanning) _setStatus(BleTransportStatus.idle);
  }

  @override
  Future<void> dispose() async {
    await stopScan();
    await stopAdvertising();
    await _fbpScanSub?.cancel();
    await _scanController.close();
    super.dispose();
  }
}
