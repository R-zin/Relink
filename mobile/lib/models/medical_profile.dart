import 'dart:convert';

/// Medical card carried in an SOS (master plan §5).
///
/// The [plaintext] half is broadcast openly — responders need it instantly.
/// The sensitive half is collected in the same form and, from Phase 3, travels
/// AES-GCM-encrypted in `MeshMessage.encryptedPayload`. For now it is stored
/// locally in plaintext (see medical_profile_store.dart).
class EmergencyContact {
  final String? name;
  final String? phone;

  const EmergencyContact({this.name, this.phone});

  bool get isEmpty =>
      (name == null || name!.trim().isEmpty) &&
      (phone == null || phone!.trim().isEmpty);

  Map<String, dynamic> toJson() => {
        if (name != null && name!.trim().isNotEmpty) 'name': name!.trim(),
        if (phone != null && phone!.trim().isNotEmpty) 'phone': phone!.trim(),
      };

  factory EmergencyContact.fromJson(Map<String, dynamic> json) =>
      EmergencyContact(
        name: json['name'] as String?,
        phone: json['phone'] as String?,
      );
}

class PlaintextMedical {
  final String? name;
  final String? bloodGroup;
  final List<String> allergies;
  final EmergencyContact? emergencyContact;

  const PlaintextMedical({
    this.name,
    this.bloodGroup,
    this.allergies = const [],
    this.emergencyContact,
  });

  /// True when nothing worth sending has been filled in.
  bool get isEmpty =>
      (name == null || name!.trim().isEmpty) &&
      (bloodGroup == null || bloodGroup!.isEmpty) &&
      allergies.isEmpty &&
      (emergencyContact == null || emergencyContact!.isEmpty);

  /// Shape matches the backend's `PlaintextMedical` schema; empty fields are
  /// omitted rather than sent as empty strings.
  Map<String, dynamic> toJson() => {
        if (name != null && name!.trim().isNotEmpty) 'name': name!.trim(),
        if (bloodGroup != null && bloodGroup!.isNotEmpty)
          'blood_group': bloodGroup,
        if (allergies.isNotEmpty) 'allergies': allergies,
        if (emergencyContact != null && !emergencyContact!.isEmpty)
          'emergency_contact': emergencyContact!.toJson(),
      };

  factory PlaintextMedical.fromJson(Map<String, dynamic> json) =>
      PlaintextMedical(
        name: json['name'] as String?,
        bloodGroup: json['blood_group'] as String?,
        allergies: (json['allergies'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        emergencyContact: json['emergency_contact'] is Map<String, dynamic>
            ? EmergencyContact.fromJson(
                json['emergency_contact'] as Map<String, dynamic>)
            : null,
      );
}

/// Sensitive half — Phase 3 encrypts this before it leaves the device.
class SensitiveMedical {
  final String? conditions;
  final String? medications;
  final String? insuranceProvider;
  final String? insurancePolicyNumber;

  const SensitiveMedical({
    this.conditions,
    this.medications,
    this.insuranceProvider,
    this.insurancePolicyNumber,
  });

  bool get isEmpty =>
      _blank(conditions) &&
      _blank(medications) &&
      _blank(insuranceProvider) &&
      _blank(insurancePolicyNumber);

  static bool _blank(String? s) => s == null || s.trim().isEmpty;

  Map<String, dynamic> toJson() => {
        if (!_blank(conditions)) 'conditions': conditions!.trim(),
        if (!_blank(medications)) 'medications': medications!.trim(),
        if (!_blank(insuranceProvider))
          'insurance_provider': insuranceProvider!.trim(),
        if (!_blank(insurancePolicyNumber))
          'insurance_policy_number': insurancePolicyNumber!.trim(),
      };

  factory SensitiveMedical.fromJson(Map<String, dynamic> json) =>
      SensitiveMedical(
        conditions: json['conditions'] as String?,
        medications: json['medications'] as String?,
        insuranceProvider: json['insurance_provider'] as String?,
        insurancePolicyNumber: json['insurance_policy_number'] as String?,
      );
}

/// The full card as persisted locally.
class MedicalProfile {
  final PlaintextMedical plaintext;
  final SensitiveMedical sensitive;

  const MedicalProfile({
    this.plaintext = const PlaintextMedical(),
    this.sensitive = const SensitiveMedical(),
  });

  /// The plaintext half is what responders need first; "completeness" for the
  /// SOS confirmation sheet is judged on it.
  bool get hasPlaintextInfo => !plaintext.isEmpty;

  String encode() => jsonEncode({
        'plaintext': plaintext.toJson(),
        'sensitive': sensitive.toJson(),
      });

  factory MedicalProfile.decode(String raw) {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return MedicalProfile(
      plaintext: json['plaintext'] is Map<String, dynamic>
          ? PlaintextMedical.fromJson(json['plaintext'] as Map<String, dynamic>)
          : const PlaintextMedical(),
      sensitive: json['sensitive'] is Map<String, dynamic>
          ? SensitiveMedical.fromJson(json['sensitive'] as Map<String, dynamic>)
          : const SensitiveMedical(),
    );
  }
}
