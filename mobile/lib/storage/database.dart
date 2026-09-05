import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Offline storage for the delay-tolerant queue + the community forum cache.
///
/// `outbox`  — unsent mesh messages (SOS-first ordering handled by OutboxDao)
/// `seen_ids` — dedupe set for the Phase 3 flooding protocol (24 h expiry sweep)
/// `community_items` — Phase 3 local forum cache: hazard reports, missing
///              persons, and shelters received/created here, so the Map and
///              Community Feed render 100% offline. `hops` records how many
///              mesh relays delivered it (0 = self or cloud) for the
///              "📡 Via Mesh (N hops)" badge.
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  static const _name = 'relink.db';
  static const _version = 2;

  Database? _db;

  Future<Database> get database async => _db ??= await _open();

  /// Shared DDL for the community cache — used by onCreate (v2) and onUpgrade (1->2).
  static Future<void> _createCommunityItems(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS community_items (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        payload TEXT NOT NULL,
        origin_device_id TEXT NOT NULL,
        hops INTEGER NOT NULL DEFAULT 0,
        timestamp TEXT NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

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
        await _createCommunityItems(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createCommunityItems(db);
        }
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
