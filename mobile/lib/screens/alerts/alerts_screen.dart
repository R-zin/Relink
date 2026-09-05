import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/alert.dart';
import '../../services/api_client.dart';
import '../../theme.dart';

/// Official NDMA Sachet alerts for the region (Phase 4).
///
/// Red/Orange alerts carry the reserved alarm-red badge; everything else uses
/// calm severity chips. Official alert text is quoted verbatim (master plan
/// §2) — we don't paraphrase government warnings.
class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  late Future<List<Alert>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Alert>> _load() => context.read<ApiClient>().listAlerts();

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
        child: FutureBuilder<List<Alert>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return _MessagePane(
                icon: Icons.cloud_off_outlined,
                title: "Can't reach the alert service right now.",
                body: 'Official alerts will appear here as soon as your phone is back online.',
                onRetry: _refresh,
              );
            }
            final alerts = snap.data ?? const [];
            if (alerts.isEmpty) {
              return _MessagePane(
                icon: Icons.notifications_none,
                title: 'No active alerts for your region.',
                body: "When authorities issue a warning, you'll get a notification here — even if the app is closed.",
                onRetry: _refresh,
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              itemCount: alerts.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) => _AlertCard(alert: alerts[i]),
            );
          },
        ),
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.alert});

  final Alert alert;

  @override
  Widget build(BuildContext context) {
    final urgent = alert.isUrgent;
    final color = _severityColor(alert.severity);
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: urgent ? RelinkColors.alarmRed.withValues(alpha: 0.6) : Colors.black12,
          width: urgent ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _SeverityChip(label: alert.severity ?? 'Unknown', color: color, urgent: urgent),
                if (alert.isTest) ...[
                  const SizedBox(width: 8),
                  const _SeverityChip(label: 'DEMO', color: Colors.blueGrey, urgent: false),
                ],
                const Spacer(),
                if (alert.issuedAt != null)
                  Text(
                    DateFormat('d MMM, h:mm a').format(alert.issuedAt!.toLocal()),
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              alert.headline ?? alert.event ?? 'Official alert',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1.35),
            ),
            if (alert.areaDesc != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.place_outlined, size: 15, color: Colors.black54),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(alert.areaDesc!, style: const TextStyle(fontSize: 13, color: Colors.black54)),
                  ),
                ],
              ),
            ],
            if ((alert.description ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(alert.description!, style: const TextStyle(fontSize: 14, height: 1.4)),
            ],
            if ((alert.instruction ?? '').isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: RelinkColors.primary.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.verified_user_outlined, size: 16, color: RelinkColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        alert.instruction!,
                        style: const TextStyle(fontSize: 13, height: 1.4, color: RelinkColors.text),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'Source: ${alert.sender ?? 'NDMA Sachet'} · quoted verbatim',
              style: const TextStyle(fontSize: 11, color: Colors.black45),
            ),
          ],
        ),
      ),
    );
  }

  static Color _severityColor(String? severity) {
    switch ((severity ?? '').toLowerCase()) {
      case 'red':
      case 'extreme':
        return RelinkColors.alarmRed;
      case 'orange':
      case 'severe':
        return RelinkColors.pinHazard;
      case 'yellow':
      case 'moderate':
        return const Color(0xFFC9A227);
      default:
        return RelinkColors.primary;
    }
  }
}

class _SeverityChip extends StatelessWidget {
  const _SeverityChip({required this.label, required this.color, required this.urgent});

  final String label;
  final Color color;
  final bool urgent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: urgent ? color : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: urgent ? Colors.white : color,
        ),
      ),
    );
  }
}

class _MessagePane extends StatelessWidget {
  const _MessagePane({required this.icon, required this.title, required this.body, this.onRetry});

  final IconData icon;
  final String title;
  final String body;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Icon(icon, size: 56, color: Colors.black38),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(body, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: Colors.black54)),
              if (onRetry != null) ...[
                const SizedBox(height: 16),
                TextButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Try again')),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
