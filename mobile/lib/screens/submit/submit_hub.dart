import 'package:flutter/material.dart';

import 'missing_person_form.dart';
import 'report_form.dart';
import 'shelter_form.dart';

/// Entry point for the three submission flows (Phase 2 §6).
class SubmitHub extends StatelessWidget {
  const SubmitHub({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('What do you want to share?',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          const Text(
              'Everything you send also helps people around you — it appears on the shared map.'),
          const SizedBox(height: 20),
          _HubCard(
            icon: Icons.warning_amber_outlined,
            title: 'Report a hazard',
            subtitle: 'Flooded road, disease outbreak, unsafe water',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ReportForm()),
            ),
          ),
          const SizedBox(height: 12),
          _HubCard(
            icon: Icons.home_outlined,
            title: 'Add a shelter / relief camp',
            subtitle: 'Share a safe place others can go to',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ShelterForm()),
            ),
          ),
          const SizedBox(height: 12),
          _HubCard(
            icon: Icons.person_search_outlined,
            title: 'Report a missing person',
            subtitle: 'Last-seen location and description',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MissingPersonForm()),
            ),
          ),
        ],
      ),
    );
  }
}

class _HubCard extends StatelessWidget {
  const _HubCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        leading: Icon(icon, size: 32),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
