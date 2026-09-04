import 'package:flutter_test/flutter_test.dart';
import 'package:relink_mobile/models/mesh_message.dart';
import 'package:relink_mobile/storage/outbox_dao.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

MeshMessage _msg(
  String id,
  MessageType type, {
  MessagePriority priority = MessagePriority.normal,
  DateTime? timestamp,
}) {
  return MeshMessage(
    id: id,
    type: type,
    originDeviceId: 'test-device',
    ttl: 6,
    priority: priority,
    timestamp: (timestamp ?? DateTime.now().toUtc()).toIso8601String(),
    payload: {'lat': 9.98, 'lng': 76.28},
  );
}

void main() {
  late Database db;
  late OutboxDao dao;
  var dbCounter = 0;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    // A uniquely-named database per test: sqflite_ffi caches connections by
    // path, so a shared name (including inMemoryDatabasePath) would leak rows
    // between tests in the same process.
    db = await databaseFactoryFfi.openDatabase(
      'outbox_test_${dbCounter++}.db',
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE outbox (
              id TEXT PRIMARY KEY,
              type TEXT NOT NULL,
              priority TEXT NOT NULL,
              ttl INTEGER NOT NULL,
              payload TEXT NOT NULL,
              status TEXT NOT NULL DEFAULT 'pending',
              retry_count INTEGER NOT NULL DEFAULT 0,
              created_at TEXT NOT NULL,
              last_attempt_at TEXT
            )
          ''');
          await db.execute('''
            CREATE TABLE seen_ids (
              id TEXT PRIMARY KEY,
              seen_at TEXT NOT NULL
            )
          ''');
        },
      ),
    );
    dao = OutboxDao(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('sos is dequeued before reports, reports in creation order', () async {
    final base = DateTime.utc(2026, 9, 5, 8);
    await dao.enqueue(_msg('report-1', MessageType.report, timestamp: base));
    await dao.enqueue(
        _msg('sos-1', MessageType.sos,
            priority: MessagePriority.high,
            timestamp: base.add(const Duration(minutes: 2))));
    await dao.enqueue(_msg('report-2', MessageType.report,
        timestamp: base.add(const Duration(minutes: 1))));

    final pending = await dao.pending();
    expect(pending.map((m) => m.id), ['sos-1', 'report-1', 'report-2']);
    expect(await dao.pendingCount(), 3);
  });

  test('sos jumps the queue even when it was created later', () async {
    final base = DateTime.utc(2026, 9, 5, 8);
    // Reports timestamped earlier than the SOS — priority must still win.
    await dao.enqueue(_msg('report-early-1', MessageType.report, timestamp: base));
    await dao.enqueue(_msg('report-early-2', MessageType.report,
        timestamp: base.add(const Duration(minutes: 1))));
    await dao.enqueue(_msg(
      'sos-late',
      MessageType.sos,
      priority: MessagePriority.high,
      timestamp: base.add(const Duration(hours: 1)),
    ));

    final pending = await dao.pending();
    expect(pending.map((m) => m.id),
        ['sos-late', 'report-early-1', 'report-early-2']);
  });

  test('markSent removes message from pending', () async {
    await dao.enqueue(
        _msg('sos-1', MessageType.sos, priority: MessagePriority.high));
    await dao.enqueue(_msg('report-1', MessageType.report));

    await dao.markSent('sos-1');

    final pending = await dao.pending();
    expect(pending.map((m) => m.id), ['report-1']);
    expect(await dao.pendingCount(), 1);
  });

  test('markFailed keeps message in pending and bumps retry_count', () async {
    await dao.enqueue(_msg('report-1', MessageType.report));
    await dao.markFailed('report-1');

    final pending = await dao.pending();
    expect(pending.map((m) => m.id), ['report-1']);
    expect(await dao.pendingCount(), 1);

    final row = (await db
            .query('outbox', where: 'id = ?', whereArgs: ['report-1']))
        .single;
    expect(row['retry_count'], 1);
    expect(row['status'], 'failed');
    expect(row['last_attempt_at'], isNotNull);
  });

  test('enqueue is idempotent (insert or replace on same id)', () async {
    await dao.enqueue(_msg('report-1', MessageType.report));
    await dao.enqueue(_msg('report-1', MessageType.report));
    expect(await dao.pendingCount(), 1);
  });

  test('round-trip preserves mesh message fields', () async {
    final original = MeshMessage(
      id: 'abc-123',
      type: MessageType.sos,
      originDeviceId: 'device-9',
      ttl: 4,
      priority: MessagePriority.high,
      timestamp: DateTime.utc(2026, 9, 5, 9, 30).toIso8601String(),
      payload: {'lat': 9.98, 'lng': 76.28, 'note': 'trapped'},
      encryptedPayload: 'dGVzdA==',
    );
    await dao.enqueue(original);

    final restored = (await dao.pending()).single;
    expect(restored.id, original.id);
    expect(restored.type, MessageType.sos);
    expect(restored.originDeviceId, 'device-9');
    expect(restored.ttl, 4);
    expect(restored.priority, MessagePriority.high);
    expect(restored.timestamp, original.timestamp);
    expect(restored.payload['note'], 'trapped');
    expect(restored.encryptedPayload, 'dGVzdA==');
  });

  test('mesh message wire mapping round-trips', () {
    for (final type in MessageType.values) {
      expect(MessageType.fromWire(type.wire), type);
    }
    expect(MessageType.sos.wire, 'SOS');
    expect(MessageType.missingPerson.wire, 'MISSING_PERSON');
  });
}
