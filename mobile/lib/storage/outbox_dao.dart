import 'package:sqflite/sqflite.dart';

import '../models/mesh_message.dart';
import 'database.dart';

/// Outbox queue — the Phase 2/3 API.
///
/// Ordering contract (master plan §7): SOS messages are sent ahead of
/// REPORT/SHELTER types. `pending()` sorts high-priority first, then by the
/// message's own timestamp (oldest first) — the timestamp is stored in its
/// own column because SQL can't sort on a field inside the JSON payload.
class OutboxDao {
  OutboxDao([Database? db]) : _dbOverride = db;

  final Database? _dbOverride;

  Future<Database> get _db async => _dbOverride ?? AppDatabase.instance.database;

  static const pendingStatuses = ['pending', 'failed'];

  Future<void> enqueue(MeshMessage msg) async {
    final db = await _db;
    await db.insert(
      'outbox',
      {
        'id': msg.id,
        'type': msg.type.wire,
        'priority': msg.priority.wire,
        'ttl': msg.ttl,
        'payload': msg.encode(),
        'status': 'pending',
        'retry_count': 0,
        // Sort key for the drain order == the message's own timestamp.
        'created_at': msg.timestamp,
        'last_attempt_at': null,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<MeshMessage>> pending({int limit = 50}) async {
    final db = await _db;
    final rows = await db.query(
      'outbox',
      where: "status IN ('pending', 'failed')",
      // SOS (high) outranks REPORT/SHELTER (normal); ties break oldest-first
      // by the message timestamp.
      orderBy: "priority = 'high' DESC, created_at ASC",
      limit: limit,
    );
    return rows
        .map((r) => MeshMessage.decode(r['payload'] as String))
        .toList(growable: false);
  }

  Future<void> markSending(String id) async {
    final db = await _db;
    await db.update('outbox', {'status': 'sending'},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> markSent(String id) async {
    final db = await _db;
    await db.update('outbox', {'status': 'sent'},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> markFailed(String id) async {
    final db = await _db;
    await db.update(
      'outbox',
      {
        'status': 'failed',
        'retry_count': await _retryCount(id) + 1,
        'last_attempt_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> _retryCount(String id) async {
    final db = await _db;
    final rows = await db.query('outbox',
        columns: ['retry_count'], where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return 0;
    return (rows.first['retry_count'] as int?) ?? 0;
  }

  Future<int> pendingCount() async {
    final db = await _db;
    final result = await db.rawQuery(
        "SELECT COUNT(*) AS c FROM outbox WHERE status IN ('pending', 'failed')");
    return (result.first['c'] as int?) ?? 0;
  }
}
