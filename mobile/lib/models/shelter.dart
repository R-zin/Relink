/// Mirrors the backend's `ShelterOut` schema.
class Shelter {
  final String id;
  final String name;
  final double lat;
  final double lng;
  final String? contactInfo;
  final int confirmCount;
  final DateTime? lastConfirmedAt;

  const Shelter({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    this.contactInfo,
    this.confirmCount = 0,
    this.lastConfirmedAt,
  });

  factory Shelter.fromJson(Map<String, dynamic> json) => Shelter(
        id: json['id'] as String,
        name: json['name'] as String,
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        contactInfo: json['contact_info'] as String?,
        confirmCount: (json['confirm_count'] as num?)?.toInt() ?? 0,
        lastConfirmedAt: json['last_confirmed_at'] != null
            ? DateTime.parse(json['last_confirmed_at'] as String)
            : null,
      );
}
