import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config.dart';
import '../../mesh/mesh_manager.dart';
import '../../mesh/nearby_transport.dart';
import '../../services/sync_service.dart';
import '../../storage/database.dart';
import '../../theme.dart';
import '../../utils/relative_time.dart';

/// Dev-only debug viewer (long-press the 'RELINK' title on home app-bar).
/// Features:
/// 1. Outbox Store: Inspect pending & sent records + manual flush.
/// 2. Mesh Live Diagnostics: Step 0 hardware smoke test (auto-connect, ping-pong, event log).
/// 3. Offline SOS Relay: Broadcast medical card over BLE mesh to nearby peers.
class OutboxViewer extends StatefulWidget {
  const OutboxViewer({super.key});

  @override
  State<OutboxViewer> createState() => _OutboxViewerState();
}

class _OutboxViewerState extends State<OutboxViewer> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  List<Map<String, Object?>> _rows = [];
  bool _flushing = false;

  NearbyTransport? _transport;
  String _deviceId = 'loading...';
  String _lastMessageReceived = '(none)';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadOutbox();
    _initTransport();
  }

  Future<void> _loadOutbox() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('outbox', orderBy: 'created_at DESC');
    if (mounted) setState(() => _rows = rows);
  }

  Future<void> _initTransport() async {
    final id = await getDeviceId();
    if (!mounted) return;
    setState(() => _deviceId = id);

    final manager = context.read<MeshManager?>();
    if (manager != null) {
      _transport = manager.transport;
      manager.addListener(_onManagerUpdate);
      setState(() {});
      return;
    }

    final transport = NearbyTransport(localDeviceId: id);
    _transport = transport;
    setState(() {});
  }

  void _onManagerUpdate() {
    if (!mounted) return;
    final manager = context.read<MeshManager?>();
    setState(() {
      if (manager?.lastPayloadSummary != null) {
        _lastMessageReceived = manager!.lastPayloadSummary!;
      }
      _loadOutbox();
    });
  }

  @override
  void dispose() {
    try {
      context.read<MeshManager?>()?.removeListener(_onManagerUpdate);
    } catch (_) {}
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _flush() async {
    setState(() => _flushing = true);
    await context.read<SyncService>().flushOnce();
    await _loadOutbox();
    if (mounted) setState(() => _flushing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostics & Mesh'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.outbox), text: 'Outbox Store'),
            Tab(icon: Icon(Icons.radar), text: 'Mesh Probe'),
          ],
        ),
        actions: [
          if (_tabController.index == 0)
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
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOutboxTab(),
          _buildMeshProbeTab(),
        ],
      ),
    );
  }

  Widget _buildOutboxTab() {
    if (_rows.isEmpty) {
      return const Center(child: Text('Outbox is empty.'));
    }
    return ListView.separated(
      itemCount: _rows.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final row = _rows[i];
        final createdAt = DateTime.tryParse(row['created_at'] as String? ?? '');
        return ListTile(
          dense: true,
          title: Text('${row['type']} · ${row['status']}'),
          subtitle: Text(
            'retries: ${row['retry_count']} · '
            '${createdAt != null ? relativeTime(createdAt) : row['created_at']}',
          ),
          trailing: Text((row['priority'] as String? ?? '').toUpperCase()),
        );
      },
    );
  }

  Widget _buildMeshProbeTab() {
    if (_transport == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListenableBuilder(
      listenable: _transport!,
      builder: (context, _) {
        final isRunning = _transport!.status == MeshTransportStatus.running;
        final peerCount = _transport!.peerCount;

        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                color: Colors.white,
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(14.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isRunning
                                      ? (peerCount > 0 ? Colors.green : Colors.amber)
                                      : Colors.grey,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                isRunning
                                    ? (peerCount > 0 ? '$peerCount Peers Connected' : 'Scanning & Advertising')
                                    : 'Mesh Inactive',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          Text(
                            _transport!.status.name.toUpperCase(),
                            style: TextStyle(
                              fontSize: 12,
                              color: isRunning ? RelinkColors.primary : Colors.grey,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Device ID: ${_deviceId.substring(0, 13)}...',
                        style: const TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Last payload: $_lastMessageReceived',
                        style: const TextStyle(fontSize: 12, color: Colors.black87),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: isRunning
                          ? () => _transport!.stop()
                          : () => _transport!.start(),
                      icon: Icon(isRunning ? Icons.stop : Icons.play_arrow),
                      label: Text(isRunning ? 'Stop Mesh' : 'Start Mesh'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isRunning ? Colors.grey[700] : RelinkColors.primary,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: (isRunning && peerCount > 0)
                          ? () {
                              _transport!.sendTestMessage(
                                  'HELLO_RELINK_PING [from ${_deviceId.substring(0, 8)}]');
                            }
                          : null,
                      icon: const Icon(Icons.send),
                      label: const Text('Send Ping'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: RelinkColors.primary,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Live Diagnostic Event Log:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[900],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: _transport!.eventLog.isEmpty
                      ? const Center(
                          child: Text(
                            'No events yet. Tap "Start Mesh" to begin.',
                            style: TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _transport!.eventLog.length,
                          itemBuilder: (context, i) {
                            final line = _transport!.eventLog[i];
                            Color color = Colors.greenAccent;
                            if (line.contains('error') || line.contains('denied') || line.contains('failed')) {
                              color = Colors.redAccent;
                            } else if (line.contains('found') || line.contains('Received')) {
                              color = Colors.yellowAccent;
                            }
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2.0),
                              child: Text(
                                line,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                  color: color,
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
