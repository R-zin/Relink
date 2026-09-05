import 'dart:async';
import 'package:flutter/foundation.dart';

import '../models/mesh_message.dart';
import '../services/sync_service.dart';
import '../storage/community_store.dart';
import '../storage/outbox_dao.dart';
import 'mesh_message_codec.dart';
import 'nearby_transport.dart';
import 'seen_store.dart';

/// Notification surfaced to the UI when this device relays an inbound
/// emergency beacon. Carries the victim's display name when present so the
/// banner reads "…for Rahul Nair".
class SosRelayNotice {
  final String messageId;
  final String? victimName;
  final DateTime at;

  SosRelayNotice({required this.messageId, this.victimName, required this.at});
}

/// The brain of the offline mesh: store-carry-forward flooding, deduplication
/// via [SeenStore], priority queuing in [OutboxDao], two-way community gossip
/// into the local [CommunityStore], and auto-flushing via [SyncService] when
/// connectivity is available.
///
/// Single shared instance, provided at the app root (main.dart) — never
/// construct a second one (phase_3.md §3.1 rule 1).
class MeshManager extends ChangeNotifier {
  MeshManager({
    required this.localDeviceId,
    MeshTransportApi? transport,
    SeenStore? seenStore,
    OutboxDao? outboxDao,
    SyncService? syncService,
    CommunityStore? communityStore,
  })  : transport = transport ?? NearbyTransport(localDeviceId: localDeviceId),
        _seenStore = seenStore ?? SeenStore(),
        _outboxDao = outboxDao ?? OutboxDao(),
        _syncService = syncService ?? SyncService(),
        _communityStore = communityStore ?? CommunityStore() {
    _initTransportListeners();
  }

  final String localDeviceId;
  final MeshTransportApi transport;
  final SeenStore _seenStore;
  final OutboxDao _outboxDao;
  final SyncService _syncService;
  final CommunityStore _communityStore;

  String? lastPayloadSummary;
  final List<String> messageHistory = [];

  /// Number of peers currently connected — drives the AppBar mesh radar.
  int get peerCount => transport.peerCount;

  bool get isRunning => transport.status == MeshTransportStatus.running;

  /// Stream of inbound SOS relay events for the "Relayed an emergency beacon"
  /// banner. Broadcast so any screen can listen.
  final StreamController<SosRelayNotice> _relayController =
      StreamController<SosRelayNotice>.broadcast();
  Stream<SosRelayNotice> get relayNotices => _relayController.stream;

  void _initTransportListeners() {
    transport.addListener(notifyListeners);

    transport.onPayloadReceived = (senderEndpointId, bytes) async {
      await _handleIncomingBytes(senderEndpointId, bytes);
    };

    transport.onPeerConnected = (peer) {
      _log('🤝 Peer connected: ${peer.deviceId} (${peer.endpointId})');
      unawaited(_burstSyncTo(peer.endpointId));
    };

    transport.onPeerDisconnected = (endpointId) {
      _log('👋 Peer disconnected: $endpointId');
    };
  }

  /// First [n] chars of [s] for compact logs — safe on short/malformed ids
  /// (a flooding protocol must never crash on a bad packet).
  static String _short(String s, [int n = 8]) =>
      s.length <= n ? s : s.substring(0, n);

  void _log(String line) {
    final time = DateTime.now().toIso8601String().substring(11, 19);
    messageHistory.insert(0, '[$time] $line');
    if (messageHistory.length > 50) messageHistory.removeLast();
    notifyListeners();
  }

  Future<void> _handleIncomingBytes(String senderEndpointId, Uint8List bytes) async {
    try {
      final msg = MeshMessageCodec.decode(bytes);
      lastPayloadSummary = '${msg.type.wire} from ${_short(msg.originDeviceId)}';
      _log('📥 Received ${msg.type.wire} [ID: ${_short(msg.id)}] from $senderEndpointId');

      // 1. Drop self-reflections
      if (msg.originDeviceId == localDeviceId) {
        _log('↩️ Dropping self-reflection packet');
        return;
      }

      // 2. Deduplication check
      final alreadySeen = await _seenStore.contains(msg.id);
      if (alreadySeen) {
        _log('🔁 Duplicate packet ${_short(msg.id)} already seen — dropping');
        return;
      }

      // 3. Mark as seen
      await _seenStore.add(msg.id);

      // 4. How many relays delivered this? initial TTL (6) minus remaining TTL.
      final hops = (CommunityStore.maxHops - msg.ttl).clamp(0, CommunityStore.maxHops);

      // 5. Type-specific handling.
      if (msg.type == MessageType.sos) {
        await _handleSos(msg);
      } else {
        // Community gossip (REPORT / MISSING_PERSON / SHELTER): land it in the
        // local forum cache so the offline map & feed update immediately.
        await _communityStore.upsert(msg, hops: hops);
        _log('💾 Cached ${msg.type.wire} in local forum ($hops hops)');
        // Also queue for cloud flush when this device next has internet.
        await _outboxDao.enqueue(msg);
      }

      // 6. If this node has internet/route, attempt immediate flush.
      _syncService.flush();

      // 7. Mesh Flooding: if TTL > 1, decrement and forward to other peers.
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

  Future<void> _handleSos(MeshMessage msg) async {
    // Store-carry-forward: always enqueue so any later online hop uploads it.
    await _outboxDao.enqueue(msg);
    _log('💾 Enqueued SOS to outbox for store-carry-forward');

    // Calm relay banner: extract the victim's first name if the plaintext
    // medical card carries one.
    final name = _victimName(msg);
    _relayController.add(SosRelayNotice(
      messageId: msg.id,
      victimName: name,
      at: DateTime.now().toUtc(),
    ));
    _log('🚨 Relaying emergency beacon${name != null ? ' for $name' : ''}');
  }

  String? _victimName(MeshMessage msg) {
    final medical = msg.payload['plaintext_medical'];
    if (medical is Map && medical['name'] is String) {
      final full = (medical['name'] as String).trim();
      if (full.isNotEmpty) return full.split(' ').first;
    }
    return null;
  }

  /// Greet a newly connected peer with the recent local forum items so an
  /// offline phone that just joined receives the latest bulletins without any
  /// user action (phase_3.md §4.3).
  Future<void> _burstSyncTo(String endpointId) async {
    try {
      final recent = await _communityStore.recentMessages(limit: 10);
      if (recent.isEmpty) return;
      var sent = 0;
      for (final m in recent) {
        try {
          await transport.sendToEndpoint(
              endpointId, MeshMessageCodec.encode(m));
          sent++;
        } catch (e) {
          _log('⚠️ Burst send failed to $endpointId: $e');
        }
      }
      if (sent > 0) _log('📤 Burst-synced $sent bulletin(s) to new peer');
    } catch (e) {
      _log('⚠️ Burst sync error: $e');
    }
  }

  /// Broadcast a newly originated message to all connected peers, cache it in
  /// the local forum, and enqueue it for cloud flush.
  Future<int> broadcastMessage(MeshMessage message) async {
    // 1. Record in seen store (dedupe our own reflections).
    await _seenStore.add(message.id);

    // 2. Cache community content locally so the offline map/feed shows it.
    if (message.type != MessageType.sos) {
      await _communityStore.upsert(message, hops: 0);
    }

    // 3. Save locally in outbox (store-carry-forward / cloud flush).
    await _outboxDao.enqueue(message);

    // 4. Send to all connected mesh peers.
    final bytes = MeshMessageCodec.encode(message);
    final count = await transport.broadcastBytes(bytes);
    _log('📡 Broadcasted ${message.type.wire} to $count peer(s)');

    // 5. Also trigger local sync in case this device is online.
    _syncService.flush();

    return count;
  }

  Future<bool> startMesh() => transport.start();
  Future<void> stopMesh() => transport.stop();

  @override
  void dispose() {
    transport.removeListener(notifyListeners);
    _relayController.close();
    super.dispose();
  }
}
