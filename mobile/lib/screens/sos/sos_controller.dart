import 'package:uuid/uuid.dart';

import '../../models/medical_profile.dart';
import '../../models/mesh_message.dart';
import '../../services/sync_service.dart';
import '../../storage/outbox_dao.dart';

/// Pure SOS orchestration, split from the widgets so the flow is testable
/// without a running app (Phase 2 §10: "send calls the expected API path").
///
/// Same contract as the screens: enqueue first (outbox is the source of
/// truth), then attempt one immediate flush over the internet path.
class SosController {
  SosController({required OutboxDao outbox, required SyncService sync})
      : _outbox = outbox,
        _sync = sync;

  final OutboxDao _outbox;
  final SyncService _sync;

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
      },
      // TODO(phase3): AES-GCM encrypt profile.sensitive here.
      encryptedPayload: null,
    );
    await _outbox.enqueue(message);
    await _sync.flushOnce();
    return _sync.lastFlushSentAll;
  }
}
