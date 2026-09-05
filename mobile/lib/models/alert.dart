/// An official NDMA Sachet CAP alert as served by `GET /alerts`.
///
/// `severity` is the CAP value verbatim (Extreme/Severe/Moderate/Minor) or
/// the demo color tag (Red/Orange/Yellow). [isUrgent] gates the reserved
/// alarm-red styling and the high-priority OS notification.
class Alert {
  const Alert({
    required this.id,
    required this.severity,
    this.event,
    this.headline,
    this.description,
    this.instruction,
    this.areaDesc,
    this.sender,
    this.issuedAt,
    this.expires,
    this.isTest = false,
  });

  final String id;
  final String? severity;
  final String? event;
  final String? headline;
  final String? description;
  final String? instruction;
  final String? areaDesc;
  final String? sender;
  final DateTime? issuedAt;
  final DateTime? expires;
  final bool isTest;

  factory Alert.fromJson(Map<String, dynamic> json) => Alert(
        id: json['id'] as String,
        severity: json['severity'] as String?,
        event: json['event'] as String?,
        headline: json['headline'] as String?,
        description: json['description'] as String?,
        instruction: json['instruction'] as String?,
        areaDesc: json['area_desc'] as String?,
        sender: json['sender'] as String?,
        issuedAt: _dt(json['issued_at']),
        expires: _dt(json['expires']),
        isTest: (json['is_test'] as int? ?? 0) == 1,
      );

  static DateTime? _dt(dynamic v) =>
      v is String ? DateTime.tryParse(v) : null;

  /// Red/Orange/Severe/Extreme — the alerts that buzz the phone and use the
  /// reserved alarm-red badge.
  bool get isUrgent {
    final s = (severity ?? '').toLowerCase();
    return s == 'red' || s == 'orange' || s == 'severe' || s == 'extreme';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'severity': severity,
        'event': event,
        'headline': headline,
        'description': description,
        'instruction': instruction,
        'area_desc': areaDesc,
        'sender': sender,
        'issued_at': issuedAt?.toIso8601String(),
        'expires': expires?.toIso8601String(),
        'is_test': isTest ? 1 : 0,
      };
}
