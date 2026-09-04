import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Backend base URL. Override at run time:
///   flutter run --dart-define=API_BASE_URL=http://192.168.x.x:8000
/// `10.0.2.2` is the host machine as seen from the Android emulator;
/// physical devices need the dev machine's LAN IP (or a tunnel).
const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:8000',
);

/// Seeded demo region fallback (Phase 1 seeds around Kochi, Kerala) — used
/// when GPS is unavailable so the map still opens somewhere meaningful.
const double kDemoCenterLat = 9.98;
const double kDemoCenterLng = 76.28;

const _kDeviceIdKey = 'relink.device_id';

/// Per-install device id, generated once and persisted. Sent as
/// `origin_device_id` on every mesh message (and as `device_id` to the
/// backend, which upserts a device row for it).
Future<String> getDeviceId() async {
  final prefs = await SharedPreferences.getInstance();
  final existing = prefs.getString(_kDeviceIdKey);
  if (existing != null) return existing;
  final id = const Uuid().v4();
  await prefs.setString(_kDeviceIdKey, id);
  return id;
}
