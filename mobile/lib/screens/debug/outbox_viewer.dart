import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/sync_service.dart';
import '../../storage/database.dart';
import '../../utils/relative_time.dart';

/// Dev-only outbox inspector (long-press the home app-bar title to open).
/// Lists every queued row and offers a manual "Flush now" — essential for
/// demo debugging.
class OutboxViewer extends StatefulWidget {
  const OutboxViewer({super.key});

  @override
  State<OutboxViewer> createState() => _OutboxViewerState();
}

class _OutboxViewerState extends State<OutboxViewer> {
  List<Map<String, Object?>> _rows = [];
  bool _flushing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('outbox', orderBy: 'created_at DESC');
    if (mounted) setState(() => _rows = rows);
  }

  Future<void> _flush() async {
    setState(() => _flushing = true);
    await context.read<SyncService>().flushOnce();
    await _load();
    if (mounted) setState(() => _flushing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Outbox (debug)'),
        actions: [
          TextButton.icon(
            onPressed: _flushing ? null : _flush,
            icon: _flushing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
            label: const Text('Flush now'),
          ),
        ],
      ),
      body: _rows.isEmpty
          ? const Center(child: Text('Outbox is empty.'))
          : ListView.separated(
              itemCount: _rows.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final row = _rows[i];
                final createdAt =
                    DateTime.tryParse(row['created_at'] as String? ?? '');
                return ListTile(
                  dense: true,
                  title: Text('${row['type']} · ${row['status']}'),
                  subtitle: Text(
                    'retries: ${row['retry_count']} · '
                    '${createdAt != null ? relativeTime(createdAt) : row['created_at']}',
                  ),
                  trailing: Text((row['priority'] as String? ?? '')
                      .toUpperCase()),
                );
              },
            ),
    );
  }
}
