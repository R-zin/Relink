import 'package:shared_preferences/shared_preferences.dart';

import '../models/medical_profile.dart';

/// Persists the medical card form locally (shared_preferences, one JSON blob).
///
/// TODO(phase3): the sensitive half (conditions/medications/insurance) is
/// stored PLAINTEXT here for now — encrypt with AES-GCM before it leaves the
/// device, and consider whether the local copy should also be protected.
class MedicalProfileStore {
  static const _key = 'relink.medical_profile';

  Future<MedicalProfile> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const MedicalProfile();
    try {
      return MedicalProfile.decode(raw);
    } catch (_) {
      // Corrupt blob — treat as empty rather than crash the SOS flow.
      return const MedicalProfile();
    }
  }

  Future<void> save(MedicalProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, profile.encode());
  }
}
