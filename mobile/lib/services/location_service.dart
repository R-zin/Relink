import 'package:geolocator/geolocator.dart';

/// Result of a one-shot location attempt. [position] is null when the fix
/// failed or was refused — callers must offer manual pin placement instead of
/// dead-ending (GPS indoors often times out).
class LocationResult {
  final Position? position;
  final String? error; // plain-language, safe to show in the UI
  final bool permanentlyDenied;

  const LocationResult._(this.position, this.error, this.permanentlyDenied);

  factory LocationResult.ok(Position position) =>
      LocationResult._(position, null, false);

  factory LocationResult.failed(String error,
          {bool permanentlyDenied = false}) =>
      LocationResult._(null, error, permanentlyDenied);
}

/// Thin geolocator wrapper: runtime permission + one-shot fix, 8 s timeout.
class LocationService {
  /// One-shot GPS fix at high accuracy. Never throws — failures come back as
  /// [LocationResult.failed] so forms can fall back to manual pin placement.
  Future<LocationResult> getCurrent() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return LocationResult.failed(
            'Location is turned off on this phone');
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        return LocationResult.failed(
          'Location permission is blocked — enable it in app settings',
          permanentlyDenied: true,
        );
      }
      if (permission == LocationPermission.denied) {
        return LocationResult.failed('Location permission was declined');
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 8));
      return LocationResult.ok(position);
    } catch (_) {
      return LocationResult.failed("Couldn't get a GPS fix — drag the pin instead");
    }
  }

  Future<void> openAppSettings() => Geolocator.openAppSettings();
}
