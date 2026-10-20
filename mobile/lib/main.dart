import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'config.dart';
import 'locator/fbp_ble_transport.dart';
import 'locator/locator_service.dart';
import 'mesh/mesh_manager.dart';
import 'screens/home_shell.dart';
import 'services/alert_poller.dart';
import 'services/api_client.dart';
import 'services/location_service.dart';
import 'services/medical_profile_store.dart';
import 'services/notification_service.dart';
import 'services/sync_service.dart';
import 'storage/community_store.dart';
import 'storage/outbox_dao.dart';
import 'theme.dart';

void main() {
  runApp(const RelinkApp());
}

class RelinkApp extends StatefulWidget {
  const RelinkApp({super.key});

  @override
  State<RelinkApp> createState() => _RelinkAppState();
}

class _RelinkAppState extends State<RelinkApp> {
  late final OutboxDao _outbox;
  late final CommunityStore _communityStore;
  late final ApiClient _apiClient;
  late final SyncService _syncService;
  late final NotificationService _notificationService;
  late final AlertPoller _alertPoller;
  late final LocatorService _locatorService;
  MeshManager? _meshManager;

  @override
  void initState() {
    super.initState();
    _outbox = OutboxDao();
    _communityStore = CommunityStore();
    _apiClient = ApiClient();
    _syncService = SyncService(outbox: _outbox, poster: _apiClient.postJson)
      ..start();
    _notificationService = NotificationService()..init();
    _alertPoller = AlertPoller(
      api: _apiClient,
      notifications: _notificationService,
    )..start();
    // Raw-BLE missing-person locator. Headless engine (no radios yet): the
    // transport only starts scanning/advertising when the follow-up Locator UI
    // arms a target or starts a query, so this shares the controller with the
    // mesh without disturbing it.
    _locatorService = LocatorService(transport: FbpBleTransport());
    _initMesh();
  }

  Future<void> _initMesh() async {
    final devId = await getDeviceId();
    final mgr = MeshManager(
      localDeviceId: devId,
      outboxDao: _outbox,
      syncService: _syncService,
      communityStore: _communityStore,
    );
    await mgr.startMesh();
    if (mounted) setState(() => _meshManager = mgr);
  }

  @override
  void dispose() {
    _alertPoller.dispose();
    _locatorService.dispose();
    _meshManager?.stopMesh();
    _meshManager?.dispose();
    _syncService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<OutboxDao>.value(value: _outbox),
        Provider<CommunityStore>.value(value: _communityStore),
        Provider<ApiClient>.value(value: _apiClient),
        Provider<SyncService>.value(value: _syncService),
        ChangeNotifierProvider<MeshManager?>.value(value: _meshManager),
        ChangeNotifierProvider<LocatorService>.value(value: _locatorService),
        Provider<LocationService>(create: (_) => LocationService()),
        Provider<MedicalProfileStore>(create: (_) => MedicalProfileStore()),
        Provider<NotificationService>.value(value: _notificationService),
      ],
      child: MaterialApp(
        title: 'RELINK',
        theme: buildRelinkTheme(),
        home: const HomeShell(),
      ),
    );
  }
}
