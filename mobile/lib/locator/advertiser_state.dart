import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'ble_transport.dart';

/// What the locator's advertiser is currently doing.
enum AdvertiserMode {
  /// Not advertising at all.
  silent,

  /// Broadcasting a QUERY beacon ("is person X nearby?").
  querying,

  /// Broadcasting a FOUND beacon ("I am person X").
  broadcastingFound,
}

/// Race-free silent ↔ querying ↔ FOUND advertiser.
///
/// The requirement (task 4): switching advertisement states must never leave
/// two beacons overlapping, and must never drop a transition. Every mutation is
/// funneled through a single chained future ([_chain]) so transitions are
/// executed strictly one-at-a-time, in call order. Each transition awaits
/// [BleTransportApi.stopAdvertising] to completion *before* starting the next
/// advertisement — and because the transport's stopAdvertising resolves only
/// when the controller has actually torn the previous beacon down, the old and
/// new advertisements can never be on-air simultaneously.
class AdvertiserState {
  AdvertiserState(this._transport);

  final BleTransportApi _transport;

  final ValueNotifier<AdvertiserMode> mode =
      ValueNotifier(AdvertiserMode.silent);

  /// Serializes every transition. Each new transition is appended to the tail
  /// of this chain, so concurrent `set*` calls queue instead of racing.
  Future<void> _chain = Future.value();

  /// Fire-and-forget transition to [mode] with an optional new payload. The
  /// returned future completes when the transition has actually been applied
  /// (so tests can await determinism); UI callers may ignore it.
  Future<void> _enqueue(AdvertiserMode next, Uint8List? payload) {
    final completer = Completer<void>();
    _chain = _chain.then((_) async {
      try {
        // Tear the current beacon down FIRST. Awaited, so no overlap.
        await _transport.stopAdvertising();
        if (next != AdvertiserMode.silent && payload != null) {
          await _transport.startAdvertising(payload);
        }
        mode.value = next;
        completer.complete();
      } catch (e, st) {
        completer.completeError(e, st);
        // Leave the radio silent on failure rather than half-switched.
        mode.value = AdvertiserMode.silent;
      }
    });
    return completer.future;
  }

  /// Stop advertising entirely.
  Future<void> goSilent() => _enqueue(AdvertiserMode.silent, null);

  /// Switch to broadcasting a QUERY beacon carrying [payload].
  Future<void> broadcastQuery(Uint8List payload) =>
      _enqueue(AdvertiserMode.querying, payload);

  /// Switch to broadcasting a FOUND beacon carrying [payload].
  Future<void> broadcastFound(Uint8List payload) =>
      _enqueue(AdvertiserMode.broadcastingFound, payload);

  /// Current mode as a plain value (for non-listening call sites).
  AdvertiserMode get currentMode => mode.value;

  Future<void> dispose() async {
    await goSilent();
    mode.dispose();
  }
}
