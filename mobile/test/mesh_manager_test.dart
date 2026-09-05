import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relink_mobile/mesh/mesh_manager.dart';
import 'package:relink_mobile/mesh/mesh_message_codec.dart';
import 'package:relink_mobile/mesh/nearby_transport.dart';
import 'package:relink_mobile/mesh/seen_store.dart';
import 'package:relink_mobile/models/mesh_message.dart';
import 'package:relink_mobile/services/sync_service.dart';
import 'package:relink_mobile/storage/community_store.dart';
import 'package:relink_mobile/storage/outbox_dao.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// In-memory transport fake — no Nearby Connections plugin / platform channel.
class FakeTransport extends ChangeNotifier implements MeshTransportApi {
  @override
  MeshTransportStatus status = MeshTransportStatus.idle;
  @override
  int get peerCount => 0;
  @override
  List<String> get eventLog => const [];

  @override
  Future<void> Function(String endpointId, Uint8List bytes)? onPayloadReceived;
  @override
  void Function(PeerInfo peer)? onPeerConnected;
  @override
  void Function(String endpointId)? onPeerDisconnected;

  final List<Uint8List> broadcasted = [];

  @override
  Future<bool> start() async => true;
  @override
  Future<void> stop() async {}
  @override
  Future<int> broadcastBytes(Uint8List bytes, {String? exceptEndpointId}) async {
    broadcasted.add(bytes);
    return 1;
  }

  @override
  Future<void> sendToEndpoint(String endpointId, Uint8List bytes) async {}

  @override
  Future<int> sendTestMessage(String message) async => 0;
}

MeshMessage _msg(
  String id,
  MessageType type, {
  String origin = 'peer-device',
  int ttl = 6,
  Map<String, dynamic>? payload,
}) {
  return MeshMessage(
    id: id,
    type: type,
    originDeviceId: origin,
    ttl: ttl,
    priority: type == MessageType.sos ? MessagePriority.high : MessagePriority.normal,
    timestamp: DateTime.utc(2026, 9, 5, 8).toIso8601String(),
    payload: payload ?? {'lat': 9.98, 'lng': 76.28},
  );
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  var counter = 0;
  Future<Database> freshDb() async {
    // sqflite_ffi named DBs persist on disk across separate `flutter test`
    // runs (the counter restarts at 0 each process), so a prior run's
    // seen_ids would dedup-drop the very messages the tests deliver. Delete
    // the file first to guarantee isolation.
    final name = 'mesh_test_${counter++}.db';
    await databaseFactoryFfi.deleteDatabase(name);
    return databaseFactoryFfi.openDatabase(
      name,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE outbox (
              id TEXT PRIMARY KEY, type TEXT NOT NULL, priority TEXT NOT NULL,
              ttl INTEGER NOT NULL, payload TEXT NOT NULL,
              status TEXT NOT NULL DEFAULT 'pending',
              retry_count INTEGER NOT NULL DEFAULT 0,
              created_at TEXT NOT NULL, last_attempt_at TEXT
            )
          ''');
          await db.execute(
              'CREATE TABLE seen_ids (id TEXT PRIMARY KEY, seen_at TEXT NOT NULL)');
          await db.execute('''
            CREATE TABLE community_items (
              id TEXT PRIMARY KEY, type TEXT NOT NULL, payload TEXT NOT NULL,
              origin_device_id TEXT NOT NULL, hops INTEGER NOT NULL DEFAULT 0,
              timestamp TEXT NOT NULL, synced INTEGER NOT NULL DEFAULT 0
            )
          ''');
        },
      ),
    );
  }

  /// Build a MeshManager on a FakeTransport (no BLE), and drive inbound packets
  /// by invoking the registered callback directly.
  Future<({MeshManager mgr, FakeTransport transport, CommunityStore community, OutboxDao outbox, Database db})>
      build() async {
    final db = await freshDb();
    final outbox = OutboxDao(db);
    final community = CommunityStore(db);
    final transport = FakeTransport();
    final sync = SyncService(
      outbox: outbox,
      // A no-op delay keeps flushOnce in-flight across an event-loop turn so
      // its `finally { _flushing = false }` completes within the awaited
      // handler — otherwise the flush can resolve after deliver() returns and
      // mark the message sent non-deterministically.
      poster: (path, body) async {
        await Future<void>.delayed(Duration.zero);
        return <String, dynamic>{};
      },
    );
    final mgr = MeshManager(
      localDeviceId: 'local-device',
      transport: transport,
      seenStore: SeenStore(db),
      outboxDao: outbox,
      syncService: sync,
      communityStore: community,
    );
    return (mgr: mgr, transport: transport, community: community, outbox: outbox, db: db);
  }

  /// Deliver an inbound packet through the transport's registered handler.
  /// The handler returns Future<void>, so we can await full DB handling.
  Future<void> deliver(FakeTransport t, String ep, Uint8List bytes) async {
    final handler = t.onPayloadReceived;
    if (handler != null) await handler(ep, bytes);
  }

  test('incoming community report is cached with mesh hops and deduplicated', () async {
    final b = await build();
    final report = _msg('r1-00000000-0000-4000-8000-000000000001', MessageType.report,
        ttl: 4, payload: {'type': 'water', 'lat': 9.98, 'lng': 76.28, 'description': 'flooded'});
    final bytes = MeshMessageCodec.encode(report);

    await deliver(b.transport, 'ep-1', bytes);
    var items = await b.community.recent();
    expect(items.single.id, 'r1-00000000-0000-4000-8000-000000000001');
    expect(items.single.hops, 2); // 6 - 4
    expect(items.single.viaMesh, isTrue);

    // Same packet again -> deduped, still one row.
    await deliver(b.transport, 'ep-1', bytes);
    items = await b.community.recent();
    expect(items.length, 1);
  });

  test('self-originated reflection is dropped (not cached, not queued)', () async {
    final b = await build();
    final own = _msg('own-00000000-0000-4000-8000-000000000002', MessageType.report, origin: 'local-device');
    await deliver(b.transport, 'ep-1', MeshMessageCodec.encode(own));
    expect(await b.community.recent(), isEmpty);
    expect(await b.outbox.pendingCount(), 0);
  });

  test('incoming SOS enqueues for carry-forward and emits a relay notice', () async {
    final b = await build();
    SosRelayNotice? notice;
    final sub = b.mgr.relayNotices.listen((n) => notice = n);

    final sos = _msg('sos-00000000-0000-4000-8000-000000000003', MessageType.sos, payload: {
      'lat': 9.98,
      'lng': 76.28,
      'plaintext_medical': {'name': 'Rahul Nair', 'blood_group': 'O+'},
    });
    await deliver(b.transport, 'ep-1', MeshMessageCodec.encode(sos));

    // The relay notice fired with the victim's first name (broadcast stream
    // delivers on the event queue, so pump it).
    await pumpEventQueue();
    expect(notice, isNotNull);
    expect(notice!.victimName, 'Rahul');

    // SOS is NEVER added to the community forum cache (it's an emergency relay,
    // not forum content).
    expect(await b.community.recent(), isEmpty);

    // It reached the outbox and was flushed (this fake is online) — the row
    // exists and is marked sent, proving store-carry-forward -> flush worked.
    expect((await b.outbox.pending()).where((m) => m.id == sos.id), isEmpty);
    final dbRow = await b.db
        .query('outbox', where: 'id = ?', whereArgs: [sos.id]);
    expect(dbRow.single['status'], 'sent');
    expect(dbRow.single['priority'], 'high');
    await sub.cancel();
  });

  test('inbound packet with ttl>1 is re-flooded with ttl-1', () async {
    final b = await build();
    final report = _msg('fwd-00000000-0000-4000-8000-000000000006', MessageType.report,
        ttl: 4, payload: {'type': 'obstacle', 'lat': 9.9, 'lng': 76.2});
    await deliver(b.transport, 'ep-1', MeshMessageCodec.encode(report));

    expect(b.transport.broadcasted.length, 1);
    final forwarded = MeshMessageCodec.decode(b.transport.broadcasted.single);
    expect(forwarded.id, report.id); // same id — dedup relies on it
    expect(forwarded.ttl, 3); // decremented
  });

  test('inbound packet at ttl<=1 is stored but NOT re-flooded', () async {
    final b = await build();
    final report = _msg('fwd-00000000-0000-4000-8000-000000000007', MessageType.report,
        ttl: 1, payload: {'type': 'obstacle', 'lat': 9.9, 'lng': 76.2});
    await deliver(b.transport, 'ep-1', MeshMessageCodec.encode(report));

    expect(await b.community.count(), 1); // stored locally
    expect(b.transport.broadcasted, isEmpty); // but not forwarded
  });

  test('codec enforces the 32 KB payload guard', () {
    final big = MeshMessage(
      id: 'big-00000000-0000-4000-8000-000000000004',
      type: MessageType.report,
      originDeviceId: 'dev',
      ttl: 6,
      priority: MessagePriority.normal,
      timestamp: DateTime.utc(2026, 9, 5).toIso8601String(),
      payload: {'blob': 'x' * (33 * 1024)},
    );
    expect(() => MeshMessageCodec.encode(big), throwsArgumentError);
  });

  test('codec round-trips a message with encrypted payload', () {
    final m = _msg('e1-00000000-0000-4000-8000-000000000005', MessageType.sos, payload: {'lat': 1.0, 'lng': 2.0});
    final m2 = MeshMessage(
      id: m.id,
      type: m.type,
      originDeviceId: m.originDeviceId,
      ttl: m.ttl,
      priority: m.priority,
      timestamp: m.timestamp,
      payload: m.payload,
      encryptedPayload: 'Y2lwaGVydGV4dA==',
    );
    final decoded = MeshMessageCodec.decode(
        Uint8List.fromList(MeshMessageCodec.encode(m2)));
    expect(decoded.id, 'e1-00000000-0000-4000-8000-000000000005');
    expect(decoded.encryptedPayload, 'Y2lwaGVydGV4dA==');
    expect(decoded.ttl, 6);
  });
}
