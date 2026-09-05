import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Local high-priority emergency notifications (Phase 4).
///
/// Replaces FCM with a reliable local channel: when a Severe/Red alert
/// arrives (via backend sync or BLE mesh), we raise an immediate heads-up
/// banner in the system tray — even if the app is backgrounded. Failures
/// never block alert delivery into the app UI.
class NotificationService {
  NotificationService() : _plugin = FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  static const String channelId = 'relink_alerts_high';
  static const String channelName = 'Severe Alerts';
  static const String channelDesc =
      'High-priority heads-up alerts for official disaster warnings (Red/Orange).';

  Future<void> init() async {
    if (_initialized) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidInit);
    await _plugin.initialize(settings: settings);

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        channelId,
        channelName,
        description: channelDesc,
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        showBadge: true,
      ),
    );
    // Android 13+ runtime permission.
    await android?.requestNotificationsPermission();
    _initialized = true;
  }

  /// Raise an immediate heads-up banner for an urgent official alert.
  Future<void> showEmergencyAlert({
    required int id,
    required String title,
    required String body,
  }) async {
    if (!_initialized) await init();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDesc,
        importance: Importance.max,
        priority: Priority.high,
        category: AndroidNotificationCategory.alarm,
        fullScreenIntent: true, // heads-up even over the lock screen
        playSound: true,
        enableVibration: true,
        ticker: 'RELINK emergency alert',
      ),
    );
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: details,
      );
    } catch (_) {
      // Notification failure must never block alert delivery — the Alerts
      // screen still shows it.
    }
  }
}
