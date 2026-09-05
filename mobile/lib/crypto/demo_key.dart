import 'dart:convert';
import 'dart:typed_data';

/// Loads the pre-shared demo AES-256-GCM key from build config.
///
/// Pass at build/run time:
///   flutter run --dart-define=MEDICAL_CARD_DEMO_KEY=<base64-32-bytes>
///
/// The master plan (§5) locks this to a single symmetric pre-shared key shared
/// between the app build and the responder Command Dashboard. Per-org key
/// rotation is explicitly out of hackathon scope.
///
/// Returns `null` when the key is absent or malformed — callers must fall back
/// to sending the SOS unencrypted rather than blocking an emergency beacon.
class MedicalDemoKey {
  MedicalDemoKey._();

  static const String _raw =
      String.fromEnvironment('MEDICAL_CARD_DEMO_KEY', defaultValue: '');

  /// True when a syntactically valid 32-byte key was supplied.
  static bool get isAvailable => load() != null;

  /// Decode the base64 key into raw bytes, or `null` if missing/invalid.
  static Uint8List? load() {
    if (_raw.isEmpty) return null;
    try {
      final bytes = base64Decode(_raw);
      if (bytes.length != 32) return null; // AES-256 requires exactly 32 bytes
      return bytes;
    } catch (_) {
      return null; // malformed base64
    }
  }
}
