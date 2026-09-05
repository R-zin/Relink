import 'package:uuid/uuid.dart';

import '../../crypto/medical_crypto.dart';
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
///
/// The sensitive half of the medical card is AES-256-GCM encrypted into
/// [MeshMessage.encryptedPayload] before it leaves the device (master plan §5).
/// Safety rule (phase_3.md §7.2): if the key is missing/invalid, the SOS goes
/// out with `encryptedPayload == null` — encryption never blocks a beacon.
class SosController {
  SosController({
    required OutboxDao outbox,
    required SyncService sync,
    MeshManager? meshManager,
    MedicalCrypto? crypto,
  })  : _outbox = outbox,
        _sync = sync,
        _meshManager = meshManager,
        _crypto = crypto ?? MedicalCrypto();

  final OutboxDao _outbox;
  final SyncService _sync;
  final MeshManager? _meshManager;
  final MedicalCrypto _crypto;

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
    // Encrypt the sensitive half. Never let crypto failure block the SOS:
    // any error or missing key -> encryptedPayload stays null and we send
    // plaintext-only (public fields), which responders can still act on.
    String? encryptedPayload;
    if (!profile.sensitive.isEmpty) {
      try {
        encryptedPayload =
            await _crypto.encryptFields(profile.sensitive.toJson());
      } catch (_) {
        encryptedPayload = null; // fall back to unencrypted
      }
    }

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
      },
      // Sensitive fields travel ONLY here (encrypted) — never in plaintext payload.
      encryptedPayload: encryptedPayload,
    );

    // 1. Enqueue to local outbox
    await _outbox.enqueue(message);

    // 2. Primary: Attempt direct internet flush (succeeds if online, graceful if offline)
    await _sync.flushOnce();

    // 3. Fallback: If direct internet flush did not reach backend (offline / no signal),
    // broadcast to nearby peers over BLE mesh to hop to an online device
    if (!_sync.lastFlushSentAll && _meshManager != null) {
      await _meshManager.broadcastMessage(message);
    }
    return _sync.lastFlushSentAll;
  }
}
