import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Offline storage for the delay-tolerant queue.
///
/// `outbox`  — unsent mesh messages (SOS-first ordering handled by OutboxDao)
/// `seen_ids` — dedupe set for the Phase 3 flooding protocol (24 h expiry
///              sweep ships with Phase 3; the table exists from Phase 1 so
///              the app never needs an on-device migration).
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  static const _name = 'relink.db';
  static const _version = 1;

  Database? _db;

  Future<Database> get database async => _db ??= await _open();

  /// Visible for testing — lets tests point at an in-memory ffi database.
  Future<Database> _open({String? path}) async {
    final dbPath = path ?? p.join(await _databasesPath(), _name);
    return openDatabase(
      dbPath,
      version: _version,
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
    );
  }

  Future<String> _databasesPath() async {
    try {
      // Normal path on device.
      return await getDatabasesPath();
    } catch (_) {
      // Host-VM unit tests (sqflite_common_ffi) — fall back to a temp dir.
      final dir = await getApplicationDocumentsDirectory();
      return dir.path;
    }
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
