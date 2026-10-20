import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../locator/locator_service.dart';
import '../../theme.dart';

/// Missing-person locator (rescuer + be-findable roles).
///
/// Foreground-only by design: scanning/advertising run while the user is here,
/// and both radios stand down when the screen is left. Calm Humanitarian tone
/// (master plan §2) — the reserved alarm red stays on SOS; the found-person
/// pin uses the missing-person violet.
class LocatorScreen extends StatefulWidget {
  const LocatorScreen({super.key});

  @override
  State<LocatorScreen> createState() => _LocatorScreenState();
}

enum _Role { find, beFound }

class _LocatorScreenState extends State<LocatorScreen> {
  _Role _role = _Role.find;
  final TextEditingController _nameController = TextEditingController();
  final MapController _mapController = MapController();

  bool _querying = false;
  bool _armed = false;
  LatLng? _estimate;

  LocatorService get _locator => context.read<LocatorService>();

  @override
  void dispose() {
    // Foreground scope: stand both radios down when leaving the screen.
    if (_querying) _locator.stopQuery();
    if (_armed) _locator.disarmTarget();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _toggleQuery() async {
    if (_querying) {
      await _locator.stopQuery();
      if (!mounted) return;
      setState(() {
        _querying = false;
        _estimate = null;
      });
      return;
    }
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _toast('Type the person\'s name first');
      return;
    }
    await _locator.startQuery(name);
    if (!mounted) return;
    setState(() => _querying = true);
  }

  Future<void> _toggleArm() async {
    if (_armed) {
      await _locator.disarmTarget();
      setState(() => _armed = false);
      return;
    }
    final ok = await _locator.armAsTarget();
    if (!mounted) return;
    if (ok) {
      setState(() => _armed = true);
    } else {
      _toast(_locator.lastError ??
          'Add your name to the medical card first so a rescuer can find you');
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final locator = context.watch<LocatorService>();
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Text(
            'Find someone nearby',
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          const Text(
            'Works phone-to-phone over Bluetooth — no internet needed.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.black54),
          ),
          const SizedBox(height: 16),
          SegmentedButton<_Role>(
            segments: const [
              ButtonSegment(
                value: _Role.find,
                icon: Icon(Icons.person_search_outlined),
                label: Text('Find someone'),
              ),
              ButtonSegment(
                value: _Role.beFound,
                icon: Icon(Icons.podcasts_outlined),
                label: Text('Be findable'),
              ),
            ],
            selected: {_role},
            onSelectionChanged: (s) => setState(() => _role = s.first),
          ),
          const SizedBox(height: 20),
          if (_role == _Role.find) _buildFindPanel(locator),
          if (_role == _Role.beFound) _buildBeFoundPanel(locator),
        ],
      ),
    );
  }

  // ---- Rescuer role ----

  Widget _buildFindPanel(LocatorService locator) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _nameController,
          enabled: !_querying,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: "Person's name",
            hintText: 'e.g. Rahul Nair',
            prefixIcon: const Icon(Icons.badge_outlined),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onSubmitted: (_) => _toggleQuery(),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: _toggleQuery,
          icon: Icon(_querying ? Icons.stop : Icons.wifi_tethering),
          label: Text(_querying ? 'Stop searching' : 'Start searching'),
        ),
        const SizedBox(height: 16),
        if (_querying) ...[
          _StatusCard(
            icon: Icons.wifi_tethering,
            title: 'Searching for "${_nameController.text.trim()}"…',
            body: locator.foundSamples.isEmpty
                ? 'Broadcasting a Bluetooth query. If their phone is nearby and set to "Be findable", it will answer.'
                : '${locator.foundSamples.length} response${locator.foundSamples.length == 1 ? '' : 's'} received.',
          ),
          const SizedBox(height: 12),
          if (locator.foundSamples.isNotEmpty) _buildResults(locator),
        ],
      ],
    );
  }

  Widget _buildResults(LocatorService locator) {
    final withFix =
        locator.foundSamples.where((s) => s.observerLat != null).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StatusCard(
          icon: Icons.signal_cellular_alt,
          title: 'Signal readings: ${locator.foundSamples.length}',
          body: 'With a GPS fix at this spot: $withFix. '
              'A position estimate needs readings from 3 different spots.',
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: withFix >= 3
                    ? () {
                        final est = locator.estimatePosition();
                        if (!mounted) return;
                        setState(() => _estimate = est);
                        if (est != null) {
                          _mapController.move(est, 17);
                        } else {
                          _toast('Not enough readings with a GPS fix yet');
                        }
                      }
                    : null,
                icon: const Icon(Icons.my_location),
                label: const Text('Estimate position'),
              ),
            ),
            if (_estimate != null) ...[
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Clear estimate',
                onPressed: () => setState(() => _estimate = null),
                icon: const Icon(Icons.close),
              ),
            ],
          ],
        ),
        if (_estimate != null) ...[
          const SizedBox(height: 12),
          _buildEstimateMap(locator),
        ],
      ],
    );
  }

  Widget _buildEstimateMap(LocatorService locator) {
    final est = _estimate!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 240,
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(initialCenter: est, initialZoom: 17),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'in.relink.relink_mobile',
                ),
                MarkerLayer(
                  markers: [
                    // Observation points (this device's fixes) in teal.
                    ...locator.foundSamples
                        .where((s) => s.observerLat != null)
                        .map((s) => Marker(
                              point: LatLng(s.observerLat!, s.observerLng!),
                              width: 22,
                              height: 22,
                              child: const Icon(Icons.location_on,
                                  size: 20, color: RelinkColors.pinShelter),
                            )),
                    // Estimated position in the missing-person violet.
                    Marker(
                      point: est,
                      width: 40,
                      height: 40,
                      child: const Icon(Icons.person_pin_circle,
                          size: 38, color: RelinkColors.pinMissing),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Estimated position: ${est.latitude.toStringAsFixed(5)}, '
          '${est.longitude.toStringAsFixed(5)}\n'
          'Bluetooth ranging is approximate — treat as a search area, not an exact point.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, color: Colors.black54),
        ),
      ],
    );
  }

  // ---- Victim/target role ----

  Widget _buildBeFoundPanel(LocatorService locator) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StatusCard(
          icon: _armed ? Icons.podcasts : Icons.portable_wifi_off,
          title: _armed ? 'You are findable' : 'You are not findable',
          body: _armed
              ? 'Your phone is listening for a rescuer\'s query and will answer if it\'s looking for your name.'
              : 'Turn this on so a rescuer\'s phone can find yours over Bluetooth. Uses the name on your medical card.',
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: _toggleArm,
          icon: Icon(_armed ? Icons.stop : Icons.podcasts_outlined),
          label: Text(_armed ? 'Stop being findable' : 'Be findable'),
        ),
        const SizedBox(height: 12),
        const Text(
          'Tip: set your name under SOS → medical card first, so a rescuer searching for you by name finds a match.',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Colors.black12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: RelinkColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(body,
                      style: const TextStyle(
                          fontSize: 13, height: 1.4, color: Colors.black54)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
