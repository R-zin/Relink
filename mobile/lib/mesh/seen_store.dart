import 'package:sqflite/sqflite.dart';
import '../storage/database.dart';

/// Deduplication store backed by the SQLite `seen_ids` table.
/// Master plan §7: Drop already-seen packets, sweep entries older than 24 hours.
class SeenStore {
  SeenStore([Database? db]) : _dbOverride = db;

  final Database? _dbOverride;

  Future<Database> get _db async => _dbOverride ?? AppDatabase.instance.database;

  Future<bool> contains(String id) async {
    final db = await _db;
    final rows = await db.query(
      'seen_ids',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> add(String id, [DateTime? seenAt]) async {
    final db = await _db;
    final at = (seenAt ?? DateTime.now().toUtc()).toIso8601String();
    await db.insert(
      'seen_ids',
      {'id': id, 'seen_at': at},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Removes entries older than [maxAge] (default 24 hours).
  Future<int> sweep({Duration maxAge = const Duration(hours: 24)}) async {
    final db = await _db;
    final cutoff = DateTime.now().toUtc().subtract(maxAge).toIso8601String();
    return db.delete('seen_ids', where: 'seen_at < ?', whereArgs: [cutoff]);
  }
}
