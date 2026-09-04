/// Mirrors the backend's `ClusterOut` / `ClusterResultOut` schemas from
/// `GET /reports/clusters`.
class ReportCluster {
  final String clusterId;
  final double centroidLat;
  final double centroidLng;
  final int reportCount;
  final int totalConfirmations;
  final DateTime? lastConfirmedAt;
  final String? sampleDescription;
  final List<String> reportIds;

  const ReportCluster({
    required this.clusterId,
    required this.centroidLat,
    required this.centroidLng,
    required this.reportCount,
    required this.totalConfirmations,
    this.lastConfirmedAt,
    this.sampleDescription,
    required this.reportIds,
  });

  /// The member report a "Confirm — I see this too" tap should confirm.
  /// NOTE: the backend does not identify the representative member — it uses
  /// the highest-confirmation member's description for `sample_description`
  /// but `report_ids` keeps DBSCAN label order (Phase 1 clustering.py). Any
  /// member id is valid for the confirm endpoint; we use the first, and the
  /// map refetches after confirming so totals stay correct regardless.
  String get confirmTargetId => reportIds.first;

  factory ReportCluster.fromJson(Map<String, dynamic> json) => ReportCluster(
        clusterId: json['cluster_id'] as String,
        centroidLat: (json['centroid_lat'] as num).toDouble(),
        centroidLng: (json['centroid_lng'] as num).toDouble(),
        reportCount: (json['report_count'] as num).toInt(),
        totalConfirmations: (json['total_confirmations'] as num?)?.toInt() ?? 0,
        lastConfirmedAt: json['last_confirmed_at'] != null
            ? DateTime.parse(json['last_confirmed_at'] as String)
            : null,
        sampleDescription: json['sample_description'] as String?,
        reportIds: (json['report_ids'] as List)
            .map((e) => e.toString())
            .toList(growable: false),
      );
}

class ClusterResult {
  final List<ReportCluster> clusters;
  final List<String> noise;

  const ClusterResult({required this.clusters, required this.noise});

  factory ClusterResult.fromJson(Map<String, dynamic> json) => ClusterResult(
        clusters: (json['clusters'] as List)
            .map((e) => ReportCluster.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        noise:
            (json['noise'] as List).map((e) => e.toString()).toList(growable: false),
      );
}
