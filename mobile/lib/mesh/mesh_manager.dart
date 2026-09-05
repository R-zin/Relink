import 'dart:async';
import 'package:flutter/foundation.dart';

import '../models/mesh_message.dart';
import '../services/sync_service.dart';
import '../storage/outbox_dao.dart';
import 'mesh_message_codec.dart';
import 'nearby_transport.dart';
import 'seen_store.dart';

/// The brain of the offline mesh: handles store-carry-forward flooding,
/// deduplication via [SeenStore], priority queuing in [OutboxDao], and
/// auto-flushing via [SyncService] when connectivity is available.
class MeshManager extends ChangeNotifier {
  MeshManager({
    required this.localDeviceId,
    NearbyTransport? transport,
    SeenStore? seenStore,
    OutboxDao? outboxDao,
    SyncService? syncService,
  })  : transport = transport ?? NearbyTransport(localDeviceId: localDeviceId),
        _seenStore = seenStore ?? SeenStore(),
        _outboxDao = outboxDao ?? OutboxDao(),
        _syncService = syncService ?? SyncService() {
    _initTransportListeners();
  }

  final String localDeviceId;
  final NearbyTransport transport;
  final SeenStore _seenStore;
  final OutboxDao _outboxDao;
  final SyncService _syncService;

  String? lastPayloadSummary;
  final List<String> messageHistory = [];

  void _initTransportListeners() {
    transport.addListener(notifyListeners);

    transport.onPayloadReceived = (senderEndpointId, bytes) async {
      await _handleIncomingBytes(senderEndpointId, bytes);
    };

    transport.onPeerConnected = (peer) {
      _log('🤝 Peer connected: ${peer.deviceId} (${peer.endpointId})');
      // Burst sync recent community notices if needed
    };

    transport.onPeerDisconnected = (endpointId) {
      _log('👋 Peer disconnected: $endpointId');
    };
  }

  void _log(String line) {
    final time = DateTime.now().toIso8601String().substring(11, 19);
    messageHistory.insert(0, '[$time] $line');
    if (messageHistory.length > 50) messageHistory.removeLast();
    notifyListeners();
  }

  Future<void> _handleIncomingBytes(String senderEndpointId, Uint8List bytes) async {
    try {
      final msg = MeshMessageCodec.decode(bytes);
      lastPayloadSummary = '${msg.type.wire} from ${msg.originDeviceId.substring(0, 8)}';
      _log('📥 Received ${msg.type.wire} [ID: ${msg.id.substring(0, 8)}] from $senderEndpointId');

      // 1. Drop self-reflections
      if (msg.originDeviceId == localDeviceId) {
        _log('↩️ Dropping self-reflection packet');
        return;
      }

      // 2. Deduplication check
      final alreadySeen = await _seenStore.contains(msg.id);
      if (alreadySeen) {
        _log('🔁 Duplicate packet ${msg.id.substring(0, 8)} already seen — dropping');
        return;
      }

      // 3. Mark as seen
      await _seenStore.add(msg.id);

      // 4. Store in local outbox for store-carry-forward
      await _outboxDao.enqueue(msg);
      _log('💾 Enqueued ${msg.type.wire} to local outbox');

      // 5. If this node has internet/route, attempt immediate flush
      _syncService.flush();

      // 6. Mesh Flooding: if TTL > 1, decrement and forward to other peers
      if (msg.ttl > 1) {
        final forwardedMsg = msg.copyWith(ttl: msg.ttl - 1);
        final encodedBytes = MeshMessageCodec.encode(forwardedMsg);
        final forwardedCount = await transport.broadcastBytes(
          encodedBytes,
          exceptEndpointId: senderEndpointId,
        );
        if (forwardedCount > 0) {
          _log('🔄 Forwarded ${msg.type.wire} (TTL ${msg.ttl} -> ${forwardedMsg.ttl}) to $forwardedCount other peer(s)');
        }
      }
    } catch (e) {
      _log('⚠️ Error handling incoming payload: $e');
    }
  }

  /// Broadcast a newly originated message to all connected peers and enqueue locally.
  Future<int> broadcastMessage(MeshMessage message) async {
    // 1. Record in seen store
    await _seenStore.add(message.id);

    // 2. Save locally in outbox
    await _outboxDao.enqueue(message);

    // 3. Send to all connected mesh peers
    final bytes = MeshMessageCodec.encode(message);
    final count = await transport.broadcastBytes(bytes);
    _log('📡 Broadcasted ${message.type.wire} to $count peer(s)');

    // 4. Also trigger local sync in case this device is online
    _syncService.flush();

    return count;
  }

  Future<bool> startMesh() => transport.start();
  Future<void> stopMesh() => transport.stop();

  @override
  void dispose() {
    transport.removeListener(notifyListeners);
    super.dispose();
  }
}
