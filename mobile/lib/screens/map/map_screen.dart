import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' hide MapController;
import 'package:flutter_map/flutter_map.dart' as fmap show MapController;
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../config.dart';
import '../../models/cluster.dart';
import '../../models/mesh_message.dart';
import '../../models/missing_person.dart';
import '../../models/report.dart';
import '../../models/shelter.dart';
import '../../services/api_client.dart';
import '../../services/location_service.dart';
import '../../storage/community_store.dart';
import '../../theme.dart';
import '../../utils/relative_time.dart';

/// State for the live map: layer toggles + fetched data + plain-language
/// loading/error states. Colocated with the screen per Phase 2 §3.
///
/// Phase 3: also reads the local [CommunityStore] so pins received over the
/// offline mesh render with a "📡 Via Mesh (N hops)" badge even with no signal.
class MapController extends ChangeNotifier {
  MapController({
    required ApiClient api,
    required LocationService location,
    CommunityStore? communityStore,
  })  : _api = api,
        _location = location,
        _communityStore = communityStore;

  final ApiClient _api;
  final LocationService _location;
  final CommunityStore? _communityStore;

  bool showShelters = true;
  bool showHazards = true;
  bool showMissing = true;

  List<ReportCluster> clusters = [];
  List<Report> noiseReports = [];
  List<Shelter> shelters = [];
  List<MissingPerson> missingPersons = [];
  List<CommunityItem> meshItems = []; // offline mesh-gossiped pins

  LatLng center = const LatLng(kDemoCenterLat, kDemoCenterLng);
  LatLng? userLocation;
  bool loading = false;
  String? error;

  bool _started = false;

  Future<void> init() async {
    if (_started) return;
    _started = true;
    final fix = await _location.getCurrent();
    if (fix.position != null) {
      userLocation = LatLng(fix.position!.latitude, fix.position!.longitude);
      center = userLocation!;
      notifyListeners();
    }
    await refresh();
  }

  Future<LatLng?> locateUser() async {
    final fix = await _location.getCurrent();
    if (fix.position != null) {
      userLocation = LatLng(fix.position!.latitude, fix.position!.longitude);
      center = userLocation!;
      notifyListeners();
      return userLocation;
    }
    return null;
  }

  void toggle(String layer) {
    switch (layer) {
      case 'shelters':
        showShelters = !showShelters;
      case 'hazards':
        showHazards = !showHazards;
      case 'missing':
        showMissing = !showMissing;
    }
    notifyListeners();
    refresh();
  }

  Future<void> refresh() async {
    loading = true;
    error = null;
    notifyListeners();
    var anyFailed = false;
    // Offline mesh-gossiped pins always come from local SQLite — works with no
    // signal, which is the entire point of the mesh.
    try {
      meshItems = await _communityStore?.recent(limit: 100) ?? [];
    } catch (_) {
      meshItems = [];
    }
    try {
      if (showHazards) {
        try {
          final result = await _api.reportClusters();
          final allReports = await _api.listReports();
          clusters = result.clusters;
          final noiseIds = result.noise.toSet();
          final byId = {for (final r in allReports) r.id: r};
          noiseReports = [
            for (final id in noiseIds)
              if (byId.containsKey(id)) byId[id]!,
          ];
        } catch (_) {
          anyFailed = true;
        }
      }
      if (showShelters) {
        try {
          shelters = await _api.listShelters(
              lat: center.latitude, lng: center.longitude);
        } catch (_) {
          anyFailed = true;
        }
      }
      if (showMissing) {
        try {
          missingPersons = await _api.searchMissingPersons(
              lat: center.latitude, lng: center.longitude);
        } catch (_) {
          anyFailed = true;
        }
      }
    } finally {
      loading = false;
      error = anyFailed ? "Couldn't reach the server — showing what we have" : null;
      notifyListeners();
    }
  }

  Future<void> confirmCluster(ReportCluster cluster) =>
      _confirm(() => _api.confirmReport(cluster.confirmTargetId));

  Future<void> confirmShelter(Shelter shelter) =>
      _confirm(() => _api.confirmShelter(shelter.id));

  Future<void> _confirm(Future<void> Function() call) async {
    try {
      await call();
    } catch (_) {
      // The refresh below shows the un-bumped count; the user can tap again.
    }
    await refresh();
  }
}

/// Live map (Phase 2 §7): OSM tiles + toggleable shelter / hazard-cluster /
/// missing-person layers with per-type trust captions.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  late final MapController _controller;
  final fmap.MapController _mapController = fmap.MapController();

  @override
  void initState() {
    super.initState();
    _controller = MapController(
      api: context.read<ApiClient>(),
      location: context.read<LocationService>(),
      communityStore: context.read<CommunityStore?>(),
    )..init();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _controller,
      child: Consumer<MapController>(
        builder: (context, c, _) {
          return Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: c.center,
                  initialZoom: 12,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    // OSM blocks/throttles tile requests without this.
                    userAgentPackageName: 'in.relink.relink_mobile',
                  ),
                  MarkerLayer(markers: _markers(context, c)),
                ],
              ),
              Positioned(
                top: 12,
                right: 12,
                child: _LayerToggles(controller: c),
              ),
              if (c.error != null)
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 16,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          const Icon(Icons.cloud_off_outlined),
                          const SizedBox(width: 8),
                          Expanded(child: Text(c.error!)),
                        ],
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: 12,
                bottom: 72,
                child: FloatingActionButton.small(
                  heroTag: 'map-gps',
                  tooltip: 'My location',
                  onPressed: () async {
                    final pos = await c.locateUser();
                    if (pos != null) {
                      _mapController.move(pos, 15);
                    } else if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Could not get GPS location. Please check device location settings.'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                  child: const Icon(Icons.my_location),
                ),
              ),
              Positioned(
                left: 12,
                bottom: 16,
                child: FloatingActionButton.small(
                  heroTag: 'map-refresh',
                  tooltip: 'Refresh',
                  onPressed: c.loading ? null : c.refresh,
                  child: c.loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  List<Marker> _markers(BuildContext context, MapController c) {
    return [
      if (c.userLocation != null)
        Marker(
          point: c.userLocation!,
          width: 36,
          height: 36,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: RelinkColors.primary.withValues(alpha: 0.2),
            ),
            alignment: Alignment.center,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: RelinkColors.primary,
                border: Border.all(color: Colors.white, width: 2.5),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 4, spreadRadius: 1),
                ],
              ),
            ),
          ),
        ),
      if (c.showHazards) ...[
        for (final cluster in c.clusters)
          _pin(
            LatLng(cluster.centroidLat, cluster.centroidLng),
            RelinkColors.pinHazard,
            badge: '${cluster.reportCount}',
            onTap: () => _showClusterSheet(context, c, cluster),
          ),
        for (final report in c.noiseReports)
          _pin(
            LatLng(report.lat, report.lng),
            RelinkColors.pinHazard,
            small: true,
            onTap: () => _showReportSheet(context, c, report),
          ),
      ],
      if (c.showShelters)
        for (final shelter in c.shelters)
          _pin(
            LatLng(shelter.lat, shelter.lng),
            RelinkColors.pinShelter,
            icon: Icons.home,
            onTap: () => _showShelterSheet(context, c, shelter),
          ),
      if (c.showMissing)
        for (final person in c.missingPersons)
          if (person.lastSeenLat != null && person.lastSeenLng != null)
            _pin(
              LatLng(person.lastSeenLat!, person.lastSeenLng!),
              RelinkColors.pinMissing,
              icon: Icons.person,
              onTap: () => _showMissingSheet(context, person),
            ),
      // Offline mesh-gossiped pins (📡 Via Mesh). These render even with no
      // signal — they come straight from local SQLite.
      for (final item in c.meshItems)
        if (item.lat != null && item.lng != null)
          if (_meshLayerVisible(c, item))
            _pin(
              LatLng(item.lat!, item.lng!),
              _meshColor(item),
              icon: _meshIcon(item),
              small: true,
              onTap: () => _showMeshItemSheet(context, item),
            ),
    ];
  }

  bool _meshLayerVisible(MapController c, CommunityItem item) {
    switch (item.type) {
      case MessageType.report:
        return c.showHazards;
      case MessageType.shelter:
        return c.showShelters;
      case MessageType.missingPerson:
        return c.showMissing;
      case MessageType.sos:
        return false; // SOS relays are not rendered as forum pins
    }
  }

  Color _meshColor(CommunityItem item) {
    switch (item.type) {
      case MessageType.report:
        return RelinkColors.pinHazard;
      case MessageType.shelter:
        return RelinkColors.pinShelter;
      case MessageType.missingPerson:
        return RelinkColors.pinMissing;
      case MessageType.sos:
        return RelinkColors.alarmRed;
    }
  }

  IconData _meshIcon(CommunityItem item) {
    switch (item.type) {
      case MessageType.report:
        return Icons.warning_amber;
      case MessageType.shelter:
        return Icons.home;
      case MessageType.missingPerson:
        return Icons.person;
      case MessageType.sos:
        return Icons.sos;
    }
  }

  void _showMeshItemSheet(BuildContext context, CommunityItem item) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => _Sheet(
        title: item.title,
        body: _meshBody(item),
        trustLine: item.viaMesh
            ? '📡 Received via Mesh (${item.hops} ${item.hops == 1 ? 'hop' : 'hops'}) · reported ${relativeTime(item.timestamp)}'
            : '🌐 Shared from this phone · ${relativeTime(item.timestamp)}',
      ),
    );
  }

  String _meshBody(CommunityItem item) {
    final p = item.payload;
    switch (item.type) {
      case MessageType.report:
        return p['description'] as String? ??
            'Hazard reported nearby (${p['type'] ?? 'unknown'}).';
      case MessageType.shelter:
        final contact = p['contact_info'] as String?;
        return contact != null && contact.isNotEmpty
            ? 'Relief camp / shelter. Contact: $contact'
            : 'Relief camp / shelter';
      case MessageType.missingPerson:
        return p['description'] as String? ?? 'Last seen near this location.';
      case MessageType.sos:
        return 'Emergency SOS relayed through the mesh.';
    }
  }

  Marker _pin(LatLng point, Color color,
      {String? badge, IconData icon = Icons.location_pin, bool small = false, VoidCallback? onTap}) {
    final size = small ? 28.0 : 40.0;
    return Marker(
      point: point,
      width: size + (badge != null ? 18 : 0),
      height: size + (badge != null ? 14 : 0),
      child: GestureDetector(
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(icon, size: size, color: color),
            if (badge != null)
              Positioned(
                top: -6,
                right: -6,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: RelinkColors.text,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    badge,
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // --- bottom sheets ---

  void _showClusterSheet(
      BuildContext context, MapController c, ReportCluster cluster) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => _Sheet(
        title: 'Hazard reported by ${cluster.reportCount} ${cluster.reportCount == 1 ? 'person' : 'people'}',
        body: cluster.sampleDescription ?? 'No description yet',
        trustLine:
            'Confirmed by ${cluster.totalConfirmations} · verified ${relativeTime(cluster.lastConfirmedAt)}',
        confirmLabel: 'Confirm — I see this too',
        onConfirm: () async {
          Navigator.of(sheetContext).pop();
          await c.confirmCluster(cluster);
        },
      ),
    );
  }

  void _showReportSheet(BuildContext context, MapController c, Report report) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => _Sheet(
        title: Report.typeLabel(report.type),
        body: report.description ?? 'No description',
        trustLine:
            'Confirmed by ${report.confirmCount} · verified ${relativeTime(report.lastConfirmedAt)}',
        confirmLabel: 'Confirm — I see this too',
        onConfirm: () async {
          Navigator.of(sheetContext).pop();
          await c.confirmCluster(ReportCluster(
            clusterId: 'single',
            centroidLat: report.lat,
            centroidLng: report.lng,
            reportCount: 1,
            totalConfirmations: report.confirmCount,
            lastConfirmedAt: report.lastConfirmedAt,
            sampleDescription: report.description,
            reportIds: [report.id],
          ));
        },
      ),
    );
  }

  void _showShelterSheet(
      BuildContext context, MapController c, Shelter shelter) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => _Sheet(
        title: shelter.name,
        body: shelter.contactInfo != null
            ? 'Contact: ${shelter.contactInfo}'
            : 'Relief camp / shelter',
        trustLine:
            'Confirmed by ${shelter.confirmCount} · verified ${relativeTime(shelter.lastConfirmedAt)}',
        confirmLabel: 'Confirm — still open',
        onConfirm: () async {
          Navigator.of(sheetContext).pop();
          await c.confirmShelter(shelter);
        },
      ),
    );
  }

  void _showMissingSheet(BuildContext context, MissingPerson person) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => _Sheet(
        title: 'Missing: ${person.name}',
        body: person.description ?? 'No description',
        trustLine: 'Reported ${relativeTime(person.createdAt)}',
      ),
    );
  }
}

class _LayerToggles extends StatelessWidget {
  const _LayerToggles({required this.controller});

  final MapController controller;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _toggleChip('Shelters', RelinkColors.pinShelter,
                controller.showShelters, () => controller.toggle('shelters')),
            _toggleChip('Hazards', RelinkColors.pinHazard,
                controller.showHazards, () => controller.toggle('hazards')),
            _toggleChip('Missing', RelinkColors.pinMissing,
                controller.showMissing, () => controller.toggle('missing')),
            // TODO(phase4): Copernicus GFM flood-extent layer.
            const Opacity(
              opacity: 0.45,
              child: FilterChip(
                label: Text('Flood extent'),
                selected: false,
                onSelected: null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toggleChip(
      String label, Color color, bool selected, VoidCallback onTap) {
    return FilterChip(
      avatar: CircleAvatar(backgroundColor: color, radius: 6),
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }
}

/// Shared bottom-sheet layout for all pin types.
class _Sheet extends StatelessWidget {
  const _Sheet({
    required this.title,
    required this.body,
    required this.trustLine,
    this.confirmLabel,
    this.onConfirm,
  });

  final String title;
  final String body;
  final String trustLine;
  final String? confirmLabel;
  final Future<void> Function()? onConfirm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: theme.textTheme.titleLarge),
          const SizedBox(height: 10),
          Text(body),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.verified_outlined, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(trustLine, style: theme.textTheme.bodySmall),
              ),
            ],
          ),
          if (confirmLabel != null && onConfirm != null) ...[
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => onConfirm!(),
              icon: const Icon(Icons.thumb_up_outlined),
              label: Text(confirmLabel!),
            ),
          ],
        ],
      ),
    );
  }
}
