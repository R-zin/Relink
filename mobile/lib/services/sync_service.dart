import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../storage/outbox_dao.dart';
import 'api_client.dart';

/// Internet-only outbox sync — TEMPORARY.
///
/// Phase 3 replaces the transport half of this with mesh-aware logic (BLE
/// flooding + flush-when-any-hop-has-internet). Keep this class small and
/// replaceable; screens enqueue to the outbox and call [flushOnce], they
/// never POST directly.
class SyncService {
  SyncService({
    OutboxDao? outbox,
    Future<Map<String, dynamic>> Function(String path, Map<String, dynamic> body)?
        poster,
    Connectivity? connectivity,
  })  : _outbox = outbox ?? OutboxDao(),
        _poster = poster ?? ApiClient().postJson,
        _connectivity = connectivity ?? Connectivity();

  final OutboxDao _outbox;
  final Future<Map<String, dynamic>> Function(
      String path, Map<String, dynamic> body) _poster;
  final Connectivity _connectivity;

  /// Give up on a message after this many failed attempts (Phase 3 may refine).
  static const maxRetries = 5;

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  Timer? _debounce;
  bool _flushing = false;

  /// Outcome of a [flushOnce] — the SOS/submit screens use this to pick the
  /// "sent" vs "saved — will send when connected" banner.
  bool lastFlushSentAll = false;

  /// Start flushing automatically whenever connectivity returns. Safe to call
  /// once from app startup.
  void start() {
    _subscription ??=
        _connectivity.onConnectivityChanged.listen((results) {
      final online = results.any((r) =>
          r == ConnectivityResult.mobile ||
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.ethernet);
      if (!online) return;
      // 2 s trailing debounce — connectivity events arrive in bursts.
      _debounce?.cancel();
      _debounce = Timer(const Duration(seconds: 2), flush);
    });
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    _debounce?.cancel();
  }

  /// Fire-and-forget flush used by the connectivity listener.
  void flush() {
    unawaited(flushOnce());
  }

  /// Drain the outbox over HTTP. At most one flush in flight; SOS first
  /// (outbox ordering contract). Stops at the first network error to avoid
  /// hot-looping while offline.
  Future<void> flushOnce() async {
    if (_flushing) return;
    _flushing = true;
    lastFlushSentAll = false;
    try {
      final pending = await _outbox.pending();
      var allSent = true;
      for (final msg in pending) {
        await _outbox.markSending(msg.id);
        final req = envelopeRequest(msg);
        try {
          await _poster(req.path, req.body);
          await _outbox.markSent(msg.id);
        } on ApiException catch (e) {
          allSent = false;
          if (e.isNetworkError) {
            // Offline (or server unreachable): leave this and everything
            // after it for the next connectivity event.
            await _outbox.markFailed(msg.id);
            break;
          }
          // 4xx: the server rejected the payload — retrying won't help
          // forever; markFailed and skip permanently after maxRetries.
          await _outbox.markFailed(msg.id);
          if (await _outbox.retryCount(msg.id) >= maxRetries) {
            await _outbox.markSent(msg.id); // dead-letter: stop retrying
          }
        } catch (_) {
          allSent = false;
          await _outbox.markFailed(msg.id);
          break;
        }
      }
      lastFlushSentAll = allSent;
    } finally {
      _flushing = false;
    }
  }
}
