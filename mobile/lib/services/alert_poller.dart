import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/alert.dart';
import 'api_client.dart';
import 'notification_service.dart';

/// Polls `GET /alerts` while the app is running and raises a high-priority
/// OS notification the first time each urgent (Red/Orange/Severe) alert is
/// seen. The seen-id set is persisted so a phone restart doesn't re-buzz old
/// alerts, and so the demo Red alert fired from the dashboard reaches the
/// phone within one poll interval.
class AlertPoller {
  AlertPoller({
    required ApiClient api,
    required NotificationService notifications,
    this.state = 'all',
    this.interval = const Duration(minutes: 2),
  })  : _api = api,
        _notifications = notifications;

  final ApiClient _api;
  final NotificationService _notifications;
  final String state;
  final Duration interval;

  Timer? _timer;
  Set<String> _seen = {};
  bool _loaded = false;
  bool _inFlight = false;

  static const _kSeenKey = 'relink.seen_alert_ids';

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => pollOnce());
    // Kick an immediate poll so a freshly-launched app surfaces any active
    // Red alert without waiting a full interval.
    unawaited(pollOnce());
  }

  void dispose() => _timer?.cancel();

  Future<void> _loadSeen() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _seen = (prefs.getStringList(_kSeenKey) ?? const []).toSet();
    _loaded = true;
  }

  Future<void> _persistSeen() async {
    final prefs = await SharedPreferences.getInstance();
    // Cap the set so years of alerts can't grow it unboundedly.
    final list = _seen.toList();
    await prefs.setStringList(
        _kSeenKey, list.length > 500 ? list.sublist(list.length - 500) : list);
  }

  /// One poll cycle. Exposed for tests. Returns the urgent alerts that were
  /// newly notified this cycle.
  Future<List<Alert>> pollOnce() async {
    if (_inFlight) return const [];
    _inFlight = true;
    try {
      await _loadSeen();
      final alerts = await _api.listAlerts(state: state);
      final fresh = <Alert>[];
      for (final a in alerts) {
        if (!a.isUrgent || _seen.contains(a.id)) continue;
        _seen.add(a.id);
        fresh.add(a);
        await _notifications.showEmergencyAlert(
          id: a.id.hashCode & 0x7fffffff,
          title: a.headline ?? a.event ?? 'Emergency alert',
          body: a.instruction ?? a.areaDesc ?? '',
        );
      }
      if (fresh.isNotEmpty) await _persistSeen();
      return fresh;
    } catch (_) {
      // Offline / backend down — never crash the poller; next cycle retries.
      return const [];
    } finally {
      _inFlight = false;
    }
  }
}
