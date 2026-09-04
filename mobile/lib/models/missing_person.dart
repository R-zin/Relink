/// Mirrors the backend's `MissingPersonOut` schema.
class MissingPerson {
  final String id;
  final String name;
  final double? lastSeenLat;
  final double? lastSeenLng;
  final String? description;
  final String status;
  final DateTime createdAt;

  const MissingPerson({
    required this.id,
    required this.name,
    this.lastSeenLat,
    this.lastSeenLng,
    this.description,
    this.status = 'missing',
    required this.createdAt,
  });

  factory MissingPerson.fromJson(Map<String, dynamic> json) => MissingPerson(
        id: json['id'] as String,
        name: json['name'] as String,
        lastSeenLat: (json['last_seen_lat'] as num?)?.toDouble(),
        lastSeenLng: (json['last_seen_lng'] as num?)?.toDouble(),
        description: json['description'] as String?,
        status: json['status'] as String? ?? 'missing',
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
