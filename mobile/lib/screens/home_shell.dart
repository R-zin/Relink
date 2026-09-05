import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../mesh/mesh_manager.dart';
import '../theme.dart';
import 'alerts/alerts_screen.dart';
import 'debug/outbox_viewer.dart';
import 'locator/locator_screen.dart';
import 'map/map_screen.dart';
import 'sos/sos_screen.dart';
import 'stats/stats_screen.dart';
import 'submit/submit_hub.dart';

/// Bottom-nav shell: SOS · Map · Find · Submit · Alerts · Stats.
///
/// SOS is the first item and visually dominant (master plan: one tap from
/// anywhere). Long-press the app-bar title to open the dev-only outbox viewer.
/// Find (the BLE missing-person locator) was added on the locator branch.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  StreamSubscription<SosRelayNotice>? _relaySub;

  static const _screens = [
    SosScreen(),
    MapScreen(),
    LocatorScreen(),
    SubmitHub(),
    AlertsScreen(),
    StatsScreen(),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Subscribe once to inbound SOS relay events so any tab can show the calm
    // "relayed a beacon" banner. Guard against re-subscribing on rebuilds.
    final mesh = context.read<MeshManager?>();
    if (mesh != null && _relaySub == null) {
      _relaySub = mesh.relayNotices.listen(_onRelayNotice);
    }
  }

  void _onRelayNotice(SosRelayNotice notice) {
    if (!mounted) return;
    final who = notice.victimName != null ? ' for ${notice.victimName}' : '';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 6),
        content: Row(
          children: [
            const Icon(Icons.broadcast_on_personal_outlined),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Relayed an emergency beacon$who — will upload when signal returns.',
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _relaySub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mesh = context.watch<MeshManager?>();
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onLongPress: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const OutboxViewer()),
          ),
          child: const Text('RELINK'),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: _MeshRadarPill(mesh: mesh)),
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          NavigationDestination(
            icon: _SosNavIcon(selected: _index == 0),
            label: 'SOS',
          ),
          const NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Map',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_search_outlined),
            selectedIcon: Icon(Icons.person_search),
            label: 'Find',
          ),
          const NavigationDestination(
            icon: Icon(Icons.add_circle_outline),
            selectedIcon: Icon(Icons.add_circle),
            label: 'Submit',
          ),
          const NavigationDestination(
            icon: Icon(Icons.notifications_outlined),
            selectedIcon: Icon(Icons.notifications),
            label: 'Alerts',
          ),
          const NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: 'Stats',
          ),
        ],
      ),
    );
  }
}

/// AppBar "Live Mesh Radar" (phase_3.md §5.2): green pill when ≥1 peer is
/// connected, amber "searching" otherwise. Watches the shared [MeshManager].
class _MeshRadarPill extends StatelessWidget {
  const _MeshRadarPill({required this.mesh});

  final MeshManager? mesh;

  @override
  Widget build(BuildContext context) {
    final peers = mesh?.peerCount ?? 0;
    final connected = peers > 0;
    final color = connected ? const Color(0xFF3D9B6E) : const Color(0xFFC99417);
    final dot = connected ? '🟢' : '🟡';
    final label = connected ? '$peers Peer${peers == 1 ? '' : 's'} Nearby' : 'Searching for mesh…';

    return Tooltip(
      message: connected
          ? 'Offline mesh active — $peers phone${peers == 1 ? '' : 's'} in range'
          : 'Looking for nearby phones to form an offline mesh',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(dot, style: const TextStyle(fontSize: 11)),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The SOS nav entry is deliberately bigger than its neighbours.
/// alarmRed is RESERVED for SOS — this is exactly its one allowed home in
/// the chrome.
class _SosNavIcon extends StatelessWidget {
  const _SosNavIcon({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: selected ? RelinkColors.alarmRed : RelinkColors.alarmRed.withValues(alpha: 0.85),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: RelinkColors.alarmRed.withValues(alpha: 0.35),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Center(
        child: Text(
          'SOS',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 15,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}
