import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../models/mesh_message.dart';
import 'database.dart';

/// One community-forum entry (hazard report / missing person / shelter) held
/// in the local SQLite cache so the Map and Community Feed render fully offline.
///
/// [hops] is how many mesh relays delivered the message: 0 for items this
/// device created itself or fetched from the cloud, N for a message relayed
/// through N peers. Drives the "📡 Via Mesh (N hops)" trust badge.
class CommunityItem {
  final String id; // mesh message id
  final MessageType type;
  final Map<String, dynamic> payload;
  final String originDeviceId;
  final int hops;
  final DateTime timestamp;

  const CommunityItem({
    required this.id,
    required this.type,
    required this.payload,
    required this.originDeviceId,
    required this.hops,
    required this.timestamp,
  });

  double? get lat => (payload['lat'] as num?)?.toDouble() ??
      (payload['last_seen_lat'] as num?)?.toDouble();
  double? get lng => (payload['lng'] as num?)?.toDouble() ??
      (payload['last_seen_lng'] as num?)?.toDouble();

  /// True for mesh-delivered data (vs cloud-verified). Badge copy key.
  bool get viaMesh => hops > 0;

  /// Short human summary used by the map sheet / feed card.
  String get title {
    switch (type) {
      case MessageType.report:
        return (payload['description'] as String?)?.trim().isNotEmpty == true
            ? payload['description'] as String
            : 'Hazard: ${payload['type'] ?? 'report'}';
      case MessageType.missingPerson:
        return 'Missing: ${payload['name'] ?? 'unknown'}';
      case MessageType.shelter:
        return payload['name'] as String? ?? 'Shelter';
      case MessageType.sos:
        return 'Emergency SOS';
    }
  }
}

/// DAO over the `community_items` table (Phase 3 local forum cache).
class CommunityStore {
  CommunityStore([Database? db]) : _dbOverride = db;

  final Database? _dbOverride;

  Future<Database> get _db async => _dbOverride ?? AppDatabase.instance.database;

  static const int maxHops = 6; // matches initial TTL

  /// Insert (or replace) a message into the cache. [hops] is computed by the
  /// caller: 0 for self-originated, `maxHops - msg.ttl` for received messages.
  Future<void> upsert(
    MeshMessage msg, {
    required int hops,
    bool synced = false,
  }) async {
    final db = await _db;
    await db.insert(
      'community_items',
      {
        'id': msg.id,
        'type': msg.type.wire,
        'payload': jsonEncode(msg.payload),
        'origin_device_id': msg.originDeviceId,
        'hops': hops,
        'timestamp': msg.timestamp,
        'synced': synced ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Recent items of any community type, newest first. SOS is excluded — it is
  /// an emergency relay, not forum content.
  Future<List<CommunityItem>> recent({int limit = 50}) async {
    final db = await _db;
    final rows = await db.query(
      'community_items',
      where: "type != ?",
      whereArgs: [MessageType.sos.wire],
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  /// The [limit] most recent community messages as re-broadcastable
  /// [MeshMessage]s — used for the peer-greeting burst sync when a new offline
  /// peer connects.
  Future<List<MeshMessage>> recentMessages({int limit = 10}) async {
    final db = await _db;
    final rows = await db.query(
      'community_items',
      where: "type != ?",
      whereArgs: [MessageType.sos.wire],
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    return rows.map((r) {
      final payload =
          Map<String, dynamic>.from(jsonDecode(r['payload'] as String) as Map);
      return MeshMessage(
        id: r['id'] as String,
        type: MessageType.fromWire(r['type'] as String),
        originDeviceId: r['origin_device_id'] as String,
        ttl: maxHops, // re-flood with a fresh budget
        priority: MessagePriority.normal,
        timestamp: r['timestamp'] as String,
        payload: payload,
      );
    }).toList(growable: false);
  }

  Future<int> count() async {
    final db = await _db;
    final result = await db
        .rawQuery('SELECT COUNT(*) AS c FROM community_items');
    return (result.first['c'] as int?) ?? 0;
  }

  CommunityItem _fromRow(Map<String, Object?> r) => CommunityItem(
        id: r['id'] as String,
        type: MessageType.fromWire(r['type'] as String),
        payload:
            Map<String, dynamic>.from(jsonDecode(r['payload'] as String) as Map),
        originDeviceId: r['origin_device_id'] as String,
        hops: (r['hops'] as num?)?.toInt() ?? 0,
        timestamp: DateTime.parse(r['timestamp'] as String),
      );
}
