import 'dart:typed_data';

import 'package:flutter/foundation.dart';

/// One received locator advertisement, already filtered to the locator service
/// UUID by the transport implementation. Carries the raw manufacturer-data
/// frame plus the radio's measured signal strength — the trilateration input.
class BleScanResult {
  final Uint8List manufacturerData;
  final int rssi;
  final DateTime at;

  /// The advertiser's broadcast TX power level (dBm) when it chose to include
  /// it — lets trilateration use a per-device measured reference instead of the
  /// global [Trilateration.txPowerAt1m] placeholder. Often null.
  final int? txPowerLevel;

  const BleScanResult({
    required this.manufacturerData,
    required this.rssi,
    required this.at,
    this.txPowerLevel,
  });
}

/// Coarse lifecycle state, mirroring [MeshTransportStatus] so the locator UI
/// (follow-up branch) can render the same kind of status the mesh radar does.
enum BleTransportStatus {
  idle,
  requestingPermissions,
  scanning,
  advertising,
  error,
}

/// The surface [LocatorService] needs from a raw-BLE transport. Abstracting it
/// lets unit tests drive the scan-dispatch and advertising state machine with
/// an in-memory fake — the real `flutter_blue_plus` implementation needs a
/// platform channel that doesn't exist in `flutter test`. Same pattern as
/// `MeshTransportApi` in `nearby_transport.dart`.
abstract class BleTransportApi implements Listenable {
  BleTransportStatus get status;

  /// Advertisements matching the locator service UUID. The implementation
  /// owns the service-UUID scan filter; subscribers get raw frames + RSSI.
  Stream<BleScanResult> get scanResults;

  Future<bool> startScan();
  Future<void> stopScan();

  /// Start a legacy non-connectable advertisement carrying [manufacturerData]
  /// under the locator service UUID.
  Future<bool> startAdvertising(Uint8List manufacturerData);

  /// Stop the current advertisement. Must complete only once the controller
  /// has actually dropped the previous advertisement — the advertiser state
  /// machine relies on this to guarantee no overlap between successive beacons.
  Future<void> stopAdvertising();
}
