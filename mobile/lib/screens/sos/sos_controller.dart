import 'package:uuid/uuid.dart';

import '../../mesh/mesh_manager.dart';
import '../../models/medical_profile.dart';
import '../../models/mesh_message.dart';
import '../../services/sync_service.dart';
import '../../storage/outbox_dao.dart';

/// Pure SOS orchestration, split from the widgets so the flow is testable
/// without a running app (Phase 2 §10: "send calls the expected API path").
///
/// Phase 3 contract: Enqueue first (outbox is local source of truth),
/// broadcast immediately to nearby BLE mesh peers via [MeshManager],
/// and attempt one flush over internet path via [SyncService].
class SosController {
  SosController({
    required OutboxDao outbox,
    required SyncService sync,
    MeshManager? meshManager,
  })  : _outbox = outbox,
        _sync = sync,
        _meshManager = meshManager;

  final OutboxDao _outbox;
  final SyncService _sync;
  final MeshManager? _meshManager;

  /// Returns true when the SOS reached the backend on this attempt,
  /// false when it sits queued for later (offline).
  Future<bool> sendSos({
    required double lat,
    required double lng,
    required MedicalProfile profile,
    required String deviceId,
    String? messageId,
    DateTime? now,
  }) async {
    final message = MeshMessage(
      id: messageId ?? const Uuid().v4(),
      type: MessageType.sos,
      originDeviceId: deviceId,
      ttl: 6,
      priority: MessagePriority.high,
      timestamp: (now ?? DateTime.now().toUtc()).toIso8601String(),
      payload: {
        'lat': lat,
        'lng': lng,
        if (!profile.plaintext.isEmpty)
          'plaintext_medical': profile.plaintext.toJson(),
        if (!profile.sensitive.isEmpty)
          'sensitive_medical': profile.sensitive.toJson(),
      },
      // AES-GCM encryption will wrap sensitive profile in next step
      encryptedPayload: null,
    );

    // 1. Enqueue to local outbox
    await _outbox.enqueue(message);

    // 2. Broadcast to nearby BLE peers if mesh is active
    if (_meshManager != null) {
      await _meshManager.broadcastMessage(message);
    }

    // 3. Attempt direct internet flush (succeeds if online, graceful if offline)
    await _sync.flushOnce();
    return _sync.lastFlushSentAll;
  }
}

