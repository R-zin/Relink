/// Mirrors the backend's `ReportOut` schema (snake_case JSON).
class Report {
  final String id;
  final String type; // 'obstacle' | 'disease' | 'water'
  final double lat;
  final double lng;
  final String? description;
  final int confirmCount;
  final DateTime? lastConfirmedAt;
  final DateTime createdAt;

  const Report({
    required this.id,
    required this.type,
    required this.lat,
    required this.lng,
    this.description,
    this.confirmCount = 0,
    this.lastConfirmedAt,
    required this.createdAt,
  });

  factory Report.fromJson(Map<String, dynamic> json) => Report(
        id: json['id'] as String,
        type: json['type'] as String,
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        description: json['description'] as String?,
        confirmCount: (json['confirm_count'] as num?)?.toInt() ?? 0,
        lastConfirmedAt: json['last_confirmed_at'] != null
            ? DateTime.parse(json['last_confirmed_at'] as String)
            : null,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  /// User-facing label for a report type (map chips, bottom sheets).
  static String typeLabel(String type) => switch (type) {
        'obstacle' => 'Flooded / blocked road',
        'disease' => 'Disease outbreak',
        'water' => 'Water contamination',
        _ => type,
      };
}
