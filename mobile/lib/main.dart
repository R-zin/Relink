import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'config.dart';
import 'mesh/mesh_manager.dart';
import 'screens/home_shell.dart';
import 'services/api_client.dart';
import 'services/location_service.dart';
import 'services/medical_profile_store.dart';
import 'services/sync_service.dart';
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
  late final ApiClient _apiClient;
  late final SyncService _syncService;
  MeshManager? _meshManager;

  @override
  void initState() {
    super.initState();
    _outbox = OutboxDao();
    _apiClient = ApiClient();
    _syncService = SyncService(outbox: _outbox, poster: _apiClient.postJson)
      ..start();
    _initMesh();
  }

  Future<void> _initMesh() async {
    final devId = await getDeviceId();
    final mgr = MeshManager(
      localDeviceId: devId,
      outboxDao: _outbox,
      syncService: _syncService,
    );
    await mgr.startMesh();
    if (mounted) setState(() => _meshManager = mgr);
  }

  @override
  void dispose() {
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
        Provider<ApiClient>.value(value: _apiClient),
        Provider<SyncService>.value(value: _syncService),
        ChangeNotifierProvider<MeshManager?>.value(value: _meshManager),
        Provider<LocationService>(create: (_) => LocationService()),
        Provider<MedicalProfileStore>(create: (_) => MedicalProfileStore()),
      ],
      child: MaterialApp(
        title: 'RELINK',
        theme: buildRelinkTheme(),
        home: const HomeShell(),
      ),
    );
  }
}
