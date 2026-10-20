import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../services/location_service.dart';
import '../services/medical_profile_store.dart';
import 'advertiser_state.dart';
import 'ble_transport.dart';
import 'locator_protocol.dart';
import 'trilateration.dart';

/// One FOUND reply received from a matched phone: the signal strength we
/// measured and when. Observer coordinates are attached separately (the fix is
/// fetched async after the RSSI arrives) via [FoundSample.withObserver].
class FoundSample {
  final int rssi;
  final DateTime at;
  final double? observerLat;
  final double? observerLng;

  /// Transmitter's measured TX power (dBm) when its advertisement carried it.
  final int? txPowerLevel;

  const FoundSample({
    required this.rssi,
    required this.at,
    this.observerLat,
    this.observerLng,
    this.txPowerLevel,
  });

  FoundSample withObserver(double lat, double lng) => FoundSample(
        rssi: rssi,
        at: at,
        observerLat: lat,
        observerLng: lng,
        txPowerLevel: txPowerLevel,
      );
}

/// Orchestrates the missing-person locator over the raw-BLE transport.
///
/// Two roles share one instance:
///  * **Rescuer** — [startQuery] broadcasts a QUERY beacon and collects the
///    FOUND replies' RSSI (fed to trilateration once ≥3 points have fixes).
///  * **Victim/target** — [armAsTarget] passively scans and answers a QUERY
///    whose person-hash matches the owner's own medical-card name with FOUND.
///
/// This is a NEW layer. It never imports `lib/mesh/` and never touches
/// `NearbyTransport` — it shares the BLE controller with the mesh the same way
/// any two short BLE operations do (time-sliced by the Android stack), and runs
/// only while armed/querying (foreground scope per the branch brief).
class LocatorService extends ChangeNotifier {
  LocatorService({
    required BleTransportApi transport,
    MedicalProfileStore? profileStore,
    LocationService? locationService,
  })  : _transport = transport,
        _profileStore = profileStore ?? MedicalProfileStore(),
        _locationService = locationService ?? LocationService() {
    advertiser = AdvertiserState(_transport);
    _scanSub = _transport.scanResults.listen(_onScanResult);
  }

  final BleTransportApi _transport;
  final MedicalProfileStore _profileStore;
  final LocationService _locationService;

  /// Race-free advertiser, exposed so the follow-up UI can watch its mode.
  late final AdvertiserState advertiser;

  StreamSubscription<BleScanResult>? _scanSub;

  /// The owner's own normalized-name hash, pre-computed once on [armAsTarget]
  /// so the (hot) scan path compares bytes instead of hashing per packet.
  Uint8List? _myNameHash;

  /// Rolling advertisement sequence counter.
  int _sequence = 0;

  /// FOUND samples collected while querying (rescuer role).
  final List<FoundSample> foundSamples = [];

  /// Whether this device is currently armed as a locate target.
  bool get isArmedAsTarget => _myNameHash != null;

  String? lastError;

  int _nextSequence() => (_sequence = (_sequence + 1) & 0xFF);

  void _logError(String msg) {
    lastError = msg;
    if (kDebugMode) debugPrint('[LocatorService] $msg');
    notifyListeners();
  }

  /// Single scan dispatcher (task 3 intent): every locator advertisement the
  /// transport surfaces is decoded once and routed by type. Malformed frames
  /// are ignored without throwing — a radio path must never crash on garbage.
  void _onScanResult(BleScanResult result) {
    final packet = LocatorProtocol.decode(result.manufacturerData);
    if (packet == null) return;
    if (packet.isQuery) {
      unawaited(_onQuery(packet));
    } else if (packet.isFound) {
      _onFound(packet, result);
    }
  }

  /// Victim role: a QUERY arrived. Answer with FOUND only if it's asking for
  /// me (hash matches my medical-card name) and I'm armed. The FOUND frame
  /// echoes my hash so the rescuer can confirm it's the right respondent.
  Future<void> _onQuery(LocatorPacket query) async {
    final myHash = _myNameHash;
    if (myHash == null) return; // not armed as a target
    if (!query.matchesHash(myHash)) return; // asking for someone else
    try {
      final frame = Uint8List(LocatorProtocol.frameLength);
      frame[0] = LocatorProtocol.protocolVersion;
      frame[1] = LocatorProtocol.typeFound;
      frame.setRange(2, 10, myHash);
      frame[10] = _nextSequence();
      await advertiser.broadcastFound(frame);
    } catch (e) {
      _logError('failed to broadcast FOUND: $e');
    }
  }

  /// Rescuer role: a FOUND reply arrived. Record its RSSI as a trilateration
  /// observation point, then attach this device's own GPS fix asynchronously.
  void _onFound(LocatorPacket packet, BleScanResult result) {
    foundSamples.add(FoundSample(
        rssi: result.rssi, at: result.at, txPowerLevel: result.txPowerLevel));
    notifyListeners();
    unawaited(_attachObserverFix(foundSamples.length - 1));
  }

  Future<void> _attachObserverFix(int index) async {
    final fix = await _locationService.getCurrent();
    final pos = fix.position;
    if (pos != null && index < foundSamples.length) {
      foundSamples[index] =
          foundSamples[index].withObserver(pos.latitude, pos.longitude);
      notifyListeners();
    }
  }

  // ---- Rescuer API ----

  /// Begin broadcasting "is [name] nearby?" and listening for FOUND replies.
  Future<void> startQuery(String name) async {
    foundSamples.clear();
    await _transport.startScan();
    final payload = await LocatorProtocol.encodeQuery(name, _nextSequence());
    await advertiser.broadcastQuery(payload);
    notifyListeners();
  }

  /// Stop querying (stop the QUERY beacon, keep collected samples).
  Future<void> stopQuery() async {
    await advertiser.goSilent();
    await _transport.stopScan();
    notifyListeners();
  }

  /// Estimated position once ≥3 observation points have GPS fixes.
  LatLng? estimatePosition() {
    final usable = foundSamples
        .where((s) => s.observerLat != null && s.observerLng != null)
        .map((s) => Observation(
              lat: s.observerLat!,
              lng: s.observerLng!,
              rssi: s.rssi,
              txPowerLevel: s.txPowerLevel,
            ))
        .toList();
    return Trilateration.trilaterate(usable);
  }

  // ---- Victim/target API ----

  /// Arm this device to answer QUERYs for the owner's medical-card name.
  /// Returns false (and sets [lastError]) when no name is on file — without a
  /// name there is nothing to match, so arming would be meaningless.
  Future<bool> armAsTarget() async {
    final profile = await _profileStore.load();
    final name = profile.plaintext.name;
    if (name == null || name.trim().isEmpty) {
      _logError('cannot arm as target: no name in the medical card');
      return false;
    }
    _myNameHash = await LocatorProtocol.personHash(name);
    await _transport.startScan();
    notifyListeners();
    return true;
  }

  /// Stand down: stop answering QUERYs and go silent.
  Future<void> disarmTarget() async {
    _myNameHash = null;
    await advertiser.goSilent();
    await _transport.stopScan();
    notifyListeners();
  }

  @override
  Future<void> dispose() async {
    await _scanSub?.cancel();
    await advertiser.dispose();
    super.dispose();
  }
}
