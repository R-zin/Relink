import 'package:flutter/material.dart';

import '../theme.dart';
import 'alerts/alerts_screen.dart';
import 'debug/outbox_viewer.dart';
import 'map/map_screen.dart';
import 'sos/sos_screen.dart';
import 'stats/stats_screen.dart';
import 'submit/submit_hub.dart';

/// Bottom-nav shell: SOS · Map · Submit · Alerts · Stats.
///
/// SOS is the center item and visually dominant (master plan: one tap from
/// anywhere). Long-press the app-bar title to open the dev-only outbox viewer.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _screens = [
    SosScreen(),
    MapScreen(),
    SubmitHub(),
    AlertsScreen(),
    StatsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onLongPress: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const OutboxViewer()),
          ),
          child: const Text('RELINK'),
        ),
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
