import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/hazard_stats.dart';
import '../../services/api_client.dart';
import '../../theme.dart';

/// Live hazard dashboard (Phase 4): AI risk review, GloFAS river-discharge
/// forecast, rainfall bars, and dam fullness. Every card names its data
/// source ("IMD", "GloFAS", "CWC Dams", "Copernicus GFM").
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsData {
  _StatsData(this.stats, this.review);
  final HazardStats stats;
  final AiReview review;
}

class _StatsScreenState extends State<StatsScreen> {
  late Future<_StatsData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_StatsData> _load() async {
    final api = context.read<ApiClient>();
    // Stats first (required), AI review second (may fall back to the rule).
    final stats = await api.getStats();
    final review = await api.getAiReview();
    return _StatsData(stats, review);
  }

  Future<void> _refresh() async {
    final f = _load();
    setState(() => _future = f);
    await f;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<_StatsData>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return _ErrorPane(onRetry: _refresh);
            }
            final data = snap.data!;
            final stats = data.stats;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                _AiReviewCard(review: data.review),
                const SizedBox(height: 14),
                _RiverCard(stats: stats),
                const SizedBox(height: 14),
                _RainfallCard(stats: stats),
                const SizedBox(height: 14),
                _DamsCard(stats: stats),
                const SizedBox(height: 14),
                _FloodExtentCard(stats: stats),
              ],
            );
          },
        ),
      ),
    );
  }
}

// --- AI risk review ---------------------------------------------------------

class _AiReviewCard extends StatelessWidget {
  const _AiReviewCard({required this.review});

  final AiReview review;

  @override
  Widget build(BuildContext context) {
    final color = switch (review.riskTag) {
      'Severe' => RelinkColors.alarmRed,
      'High' => RelinkColors.pinHazard,
      'Moderate' => RelinkColors.primary,
      _ => const Color(0xFF3D9B6E),
    };
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Risk assessment', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const Spacer(),
              _TagBadge(label: review.riskTag, color: color),
            ],
          ),
          const SizedBox(height: 10),
          Text(review.summaryText, style: const TextStyle(fontSize: 14, height: 1.5)),
          const SizedBox(height: 10),
          Row(
            children: [
              _SourcePill(review.source == 'llm' ? 'AI review' : 'Rule-based'),
              const Spacer(),
              if (review.generatedAt != null)
                Text(
                  'Updated ${DateFormat('h:mm a').format(review.generatedAt!.toLocal())}',
                  style: const TextStyle(fontSize: 11, color: Colors.black45),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// --- River discharge (GloFAS) -----------------------------------------------

class _RiverCard extends StatelessWidget {
  const _RiverCard({required this.stats});

  final HazardStats stats;

  @override
  Widget build(BuildContext context) {
    final glofas = stats.glofas;
    final forecast = stats.glofasForecast;
    final discharge = (glofas['discharge_m3s'] as num?)?.toDouble();
    final trend = glofas['trend'] as String? ?? 'steady';

    final spots = <FlSpot>[];
    final labels = <String>[];
    for (var i = 0; i < forecast.length; i++) {
      final d = (forecast[i]['discharge_m3s'] as num?)?.toDouble();
      if (d == null) continue;
      spots.add(FlSpot(i.toDouble(), d));
      final date = forecast[i]['date'] as String? ?? '';
      labels.add(date.length >= 10 ? date.substring(8, 10) : date);
    }

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeader(
            title: 'Periyar river discharge',
            source: glofas['source_label'] as String? ?? 'GloFAS',
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                discharge == null ? '—' : discharge.toStringAsFixed(0),
                style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 6),
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text('m³/s', style: TextStyle(fontSize: 14, color: Colors.black54)),
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _TrendChip(trend: trend),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (spots.length >= 2)
            SizedBox(
              height: 140,
              child: LineChart(
                LineChartData(
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: 1,
                        getTitlesWidget: (v, meta) {
                          final i = v.toInt();
                          if (i < 0 || i >= labels.length || i % 2 != 0) return const SizedBox.shrink();
                          return Text(labels[i], style: const TextStyle(fontSize: 10, color: Colors.black45));
                        },
                      ),
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: RelinkColors.primary,
                      barWidth: 3,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: RelinkColors.primary.withValues(alpha: 0.12),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            const Text('No forecast curve available.', style: TextStyle(fontSize: 13, color: Colors.black54)),
          const SizedBox(height: 6),
          const Text('7-day forecast', style: TextStyle(fontSize: 11, color: Colors.black45)),
        ],
      ),
    );
  }
}

// --- Rainfall (Open-Meteo, cited IMD) ---------------------------------------

class _RainfallCard extends StatelessWidget {
  const _RainfallCard({required this.stats});

  final HazardStats stats;

  @override
  Widget build(BuildContext context) {
    final weather = stats.weather;
    final rain24 = (weather['rainfall_24h_mm'] as num?)?.toDouble();
    final gust = (weather['max_gust_kmh'] as num?)?.toDouble();
    final hourly = stats.weatherHourly;

    // Past 24 h of precipitation, most recent last.
    final past = hourly
        .where((h) => (h['precipitation_mm'] as num?) != null)
        .map((h) => (h['precipitation_mm'] as num).toDouble())
        .toList();
    final bars = past.length > 24 ? past.sublist(0, 24) : past;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeader(title: 'Rainfall & wind', source: weather['source_label'] as String? ?? 'IMD'),
          const SizedBox(height: 8),
          Row(
            children: [
              _BigStat(value: rain24 == null ? '—' : rain24.toStringAsFixed(1), unit: 'mm', label: 'rain, 24 h'),
              const SizedBox(width: 24),
              _BigStat(value: gust == null ? '—' : gust.toStringAsFixed(0), unit: 'km/h', label: 'max gust'),
            ],
          ),
          const SizedBox(height: 12),
          if (bars.isNotEmpty)
            SizedBox(
              height: 110,
              child: BarChart(
                BarChartData(
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  titlesData: const FlTitlesData(show: false),
                  barTouchData: const BarTouchData(enabled: false),
                  barGroups: [
                    for (var i = 0; i < bars.length; i++)
                      BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: bars[i] < 0.05 ? 0.05 : bars[i],
                            width: 5,
                            color: bars[i] > 10 ? RelinkColors.pinHazard : RelinkColors.primary,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            )
          else
            const Text('No rainfall data available.', style: TextStyle(fontSize: 13, color: Colors.black54)),
          const SizedBox(height: 6),
          const Text('Hourly rainfall, last 24 h', style: TextStyle(fontSize: 11, color: Colors.black45)),
        ],
      ),
    );
  }
}

// --- Dam fullness (CWC static dataset) --------------------------------------

class _DamsCard extends StatelessWidget {
  const _DamsCard({required this.stats});

  final HazardStats stats;

  @override
  Widget build(BuildContext context) {
    final dams = stats.dams;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardHeader(title: 'Reservoir levels', source: 'CWC Dams'),
          const SizedBox(height: 4),
          const Text(
            'Latest published storage (cached dataset)',
            style: TextStyle(fontSize: 11, color: Colors.black45),
          ),
          const SizedBox(height: 10),
          if (dams.isEmpty)
            const Text('No reservoir data available.', style: TextStyle(fontSize: 13, color: Colors.black54))
          else
            ...dams.map((d) {
              final name = d['name'] as String? ?? '';
              final pct = (d['storage_pct'] as num?)?.toDouble() ?? 0;
              final danger = (d['danger_level_pct'] as num?)?.toDouble() ?? 95;
              final over = pct >= danger;
              final near = !over && pct >= danger - 10;
              final color = over
                  ? RelinkColors.alarmRed
                  : near
                      ? RelinkColors.pinHazard
                      : RelinkColors.primary;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
                        Text('${pct.toStringAsFixed(1)}%', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: (pct / 100).clamp(0, 1),
                        minHeight: 8,
                        backgroundColor: Colors.black12,
                        valueColor: AlwaysStoppedAnimation(color),
                      ),
                    ),
                    if (over)
                      const Padding(
                        padding: EdgeInsets.only(top: 3),
                        child: Text('Above danger level', style: TextStyle(fontSize: 11, color: RelinkColors.alarmRed, fontWeight: FontWeight.w600)),
                      ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

// --- Satellite flood extent (Copernicus GFM) --------------------------------

class _FloodExtentCard extends StatelessWidget {
  const _FloodExtentCard({required this.stats});

  final HazardStats stats;

  @override
  Widget build(BuildContext context) {
    final gfm = stats.gfm;
    final observedAtRaw = gfm['observed_at'] as String?;
    final observedAt = observedAtRaw == null ? null : DateTime.tryParse(observedAtRaw);
    final count = gfm['polygon_count'] as int? ?? 0;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeader(title: 'Satellite flood extent', source: gfm['source_label'] as String? ?? 'Copernicus GFM'),
          const SizedBox(height: 8),
          Text(
            count > 0
                ? '$count inundated area${count == 1 ? '' : 's'} detected along the Periyar floodplain.'
                : 'No inundation polygons in the latest observation.',
            style: const TextStyle(fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.satellite_alt_outlined, size: 15, color: Colors.black54),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  observedAt != null
                      ? 'Observed ${DateFormat('d MMM, h:mm a').format(observedAt.toLocal())} — latest satellite pass, not live'
                      : 'Observation time unavailable',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// --- shared bits ------------------------------------------------------------

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.black12)),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }
}

class _CardHeader extends StatelessWidget {
  const _CardHeader({required this.title, required this.source});

  final String title;
  final String source;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
        _SourcePill(source),
      ],
    );
  }
}

class _SourcePill extends StatelessWidget {
  const _SourcePill(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: RelinkColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: RelinkColors.primary)),
    );
  }
}

class _TagBadge extends StatelessWidget {
  const _TagBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final severe = label == 'Severe';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: severe ? color : color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: severe ? Colors.white : color),
      ),
    );
  }
}

class _BigStat extends StatelessWidget {
  const _BigStat({required this.value, required this.unit, required this.label});

  final String value;
  final String unit;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
            const SizedBox(width: 3),
            Padding(padding: const EdgeInsets.only(bottom: 3), child: Text(unit, style: const TextStyle(fontSize: 12, color: Colors.black54))),
          ],
        ),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.black45)),
      ],
    );
  }
}

class _TrendChip extends StatelessWidget {
  const _TrendChip({required this.trend});

  final String trend;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (trend) {
      'rising' => (Icons.trending_up, RelinkColors.alarmRed),
      'falling' => (Icons.trending_down, const Color(0xFF3D9B6E)),
      _ => (Icons.trending_flat, Colors.black45),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(trend, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
      ],
    );
  }
}

class _ErrorPane extends StatelessWidget {
  const _ErrorPane({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        const Icon(Icons.cloud_off_outlined, size: 56, color: Colors.black38),
        const SizedBox(height: 16),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              Text("Can't load hazard data right now.", textAlign: TextAlign.center, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              SizedBox(height: 8),
              Text('Live conditions will appear here once your phone reconnects.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Colors.black54)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Center(child: TextButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Try again'))),
      ],
    );
  }
}
