/// Typed view over the `GET /stats` consolidated metrics payload.
///
/// Kept as one lightly-typed wrapper (the per-source shapes differ) with
/// null-safe accessors so the Stats screen never crashes when an optional
/// metric is unavailable.
class HazardStats {
  const HazardStats({required this.region, required this.fetchedAt, required this.metrics});

  final String region;
  final DateTime? fetchedAt;
  final Map<String, dynamic> metrics;

  factory HazardStats.fromJson(Map<String, dynamic> json) => HazardStats(
        region: json['region'] as String? ?? '',
        fetchedAt: json['fetched_at'] is String ? DateTime.tryParse(json['fetched_at'] as String) : null,
        metrics: (json['metrics'] as Map?)?.cast<String, dynamic>() ?? const {},
      );

  Map<String, dynamic> toJson() => {
        'region': region,
        if (fetchedAt != null) 'fetched_at': fetchedAt!.toIso8601String(),
        'metrics': metrics,
      };

  Map<String, dynamic> get glofas => (metrics['glofas'] as Map?)?.cast<String, dynamic>() ?? const {};
  Map<String, dynamic> get weather => (metrics['weather'] as Map?)?.cast<String, dynamic>() ?? const {};
  Map<String, dynamic> get gfm => (metrics['gfm'] as Map?)?.cast<String, dynamic>() ?? const {};
  Map<String, dynamic> get marine => (metrics['marine'] as Map?)?.cast<String, dynamic>() ?? const {};

  List<Map<String, dynamic>> get dams =>
      (((metrics['dams'] as Map?)?['dams']) as List?)?.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList() ??
      const [];

  List<Map<String, dynamic>> get glofasForecast =>
      ((glofas['forecast']) as List?)?.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList() ?? const [];

  List<Map<String, dynamic>> get weatherHourly =>
      ((weather['hourly']) as List?)?.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList() ?? const [];
}

/// The AI operational risk review from `GET /stats/ai-review`.
class AiReview {
  const AiReview({
    required this.region,
    required this.summaryText,
    required this.riskTag,
    required this.source,
    this.generatedAt,
  });

  final String region;
  final String summaryText;
  final String riskTag;
  final String source; // 'llm' | 'rule'
  final DateTime? generatedAt;

  factory AiReview.fromJson(Map<String, dynamic> json) => AiReview(
        region: json['region'] as String? ?? '',
        summaryText: json['summary_text'] as String? ?? '',
        riskTag: json['risk_tag'] as String? ?? 'Low',
        source: json['source'] as String? ?? 'rule',
        generatedAt: json['generated_at'] is String ? DateTime.tryParse(json['generated_at'] as String) : null,
      );
}
