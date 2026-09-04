import 'package:flutter_test/flutter_test.dart';
import 'package:relink_mobile/models/mesh_message.dart';
import 'package:relink_mobile/services/api_client.dart';
import 'package:relink_mobile/services/sync_service.dart';
import 'package:relink_mobile/storage/outbox_dao.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

MeshMessage _msg(String id, MessageType type,
    {MessagePriority priority = MessagePriority.normal,
    DateTime? timestamp,
    Map<String, dynamic>? payload}) {
  return MeshMessage(
    id: id,
    type: type,
    originDeviceId: 'device-1',
    priority: priority,
    timestamp: (timestamp ?? DateTime.now().toUtc()).toIso8601String(),
    payload: payload ?? {'lat': 9.98, 'lng': 76.28},
  );
}

Future<OutboxDao> _freshDao(String name) async {
  final db = await databaseFactoryFfi.openDatabase(
    name,
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
      },
    ),
  );
  return OutboxDao(db);
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('sos posts before report; success marks both sent', () async {
    final dao = await _freshDao('sync_ok.db');
    final base = DateTime.utc(2026, 9, 5, 8);
    await dao.enqueue(_msg('report-1', MessageType.report, timestamp: base,
        payload: {'type': 'water', 'lat': 9.98, 'lng': 76.28}));
    await dao.enqueue(_msg('sos-1', MessageType.sos,
        priority: MessagePriority.high,
        timestamp: base.add(const Duration(minutes: 5))));

    final calls = <String>[];
    final sync = SyncService(
      outbox: dao,
      poster: (path, body) async {
        calls.add(path);
        return <String, dynamic>{'ok': true};
      },
    );

    await sync.flushOnce();

    expect(calls, ['/sos', '/reports']);
    expect(await dao.pendingCount(), 0);
    expect(sync.lastFlushSentAll, isTrue);
  });

  test('network failure leaves both pending and bumps retry count', () async {
    final dao = await _freshDao('sync_fail.db');
    await dao.enqueue(_msg('sos-1', MessageType.sos,
        priority: MessagePriority.high));
    await dao.enqueue(_msg('report-1', MessageType.report,
        payload: {'type': 'obstacle', 'lat': 9.9, 'lng': 76.2}));

    final sync = SyncService(
      outbox: dao,
      poster: (path, body) async =>
          throw ApiException('no connection'), // statusCode null => network
    );

    await sync.flushOnce();

    expect(await dao.pendingCount(), 2);
    expect(await dao.retryCount('sos-1'), 1);
    // The report is untouched (flush stops at first network error) — retry
    // count stays 0 but it's still pending.
    expect(await dao.retryCount('report-1'), 0);
    expect(sync.lastFlushSentAll, isFalse);
  });

  test('4xx keeps the message pending but does not stop the drain', () async {
    final dao = await _freshDao('sync_4xx.db');
    await dao.enqueue(_msg('report-bad', MessageType.report,
        payload: {'type': 'water', 'lat': 9.9, 'lng': 76.2}));
    await dao.enqueue(_msg('report-good', MessageType.report,
        payload: {'type': 'water', 'lat': 9.9, 'lng': 76.2}));

    final paths = <String>[];
    final sync = SyncService(
      outbox: dao,
      poster: (path, body) async {
        paths.add(path);
        if (paths.length == 1) {
          throw ApiException('validation failed', statusCode: 422);
        }
        return <String, dynamic>{'ok': true};
      },
    );

    await sync.flushOnce();

    expect(paths, ['/reports', '/reports']);
    expect(await dao.pendingCount(), 1); // report-bad remains
    expect(await dao.retryCount('report-bad'), 1);
  });
}
