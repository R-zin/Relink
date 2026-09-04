/// Mirrors the backend's `SosEventOut` schema (used by the debug viewer and
/// later the dashboard-side flows; the SOS form itself only needs POST /sos).
class SosEvent {
  final String id;
  final double lat;
  final double lng;
  final Map<String, dynamic>? plaintextMedical;
  final String status;
  final DateTime createdAt;

  const SosEvent({
    required this.id,
    required this.lat,
    required this.lng,
    this.plaintextMedical,
    this.status = 'active',
    required this.createdAt,
  });

  factory SosEvent.fromJson(Map<String, dynamic> json) => SosEvent(
        id: json['id'] as String,
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        plaintextMedical: json['plaintext_medical'] as Map<String, dynamic>?,
        status: json['status'] as String? ?? 'active',
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
