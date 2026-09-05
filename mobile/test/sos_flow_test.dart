import 'package:flutter_test/flutter_test.dart';
import 'package:relink_mobile/models/medical_profile.dart';
import 'package:relink_mobile/models/mesh_message.dart';
import 'package:relink_mobile/screens/sos/sos_controller.dart';
import 'package:relink_mobile/services/sync_service.dart';
import 'package:relink_mobile/storage/outbox_dao.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<OutboxDao> freshDao(String name) async {
    // Delete any stale file from a prior run (named ffi DBs persist on disk).
    await databaseFactoryFfi.deleteDatabase(name);
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

  test('SOS send hits POST /sos with the expected body', () async {
    final dao = await freshDao('sos_flow.db');
    final calls = <MapEntry<String, Map<String, dynamic>>>[];
    final sync = SyncService(
      outbox: dao,
      poster: (path, body) async {
        calls.add(MapEntry(path, body));
        return <String, dynamic>{'id': 'evt-1'};
      },
    );
    final controller = SosController(outbox: dao, sync: sync);

    final sent = await controller.sendSos(
      lat: 9.98,
      lng: 76.28,
      profile: const MedicalProfile(
        plaintext: PlaintextMedical(name: 'Asha', bloodGroup: 'O+'),
      ),
      deviceId: 'device-9',
      messageId: 'sos-1',
      now: DateTime.utc(2026, 9, 5, 8),
    );

    expect(sent, isTrue);
    expect(calls.single.key, '/sos');
    expect(calls.single.value, {
      'device_id': 'device-9',
      'client_msg_id': 'sos-1', // Phase 3 idempotent relay-flush key
      'lat': 9.98,
      'lng': 76.28,
      'plaintext_medical': {'name': 'Asha', 'blood_group': 'O+'},
    });
    expect(await dao.pendingCount(), 0);
  });

  test('offline send queues the SOS in the outbox (fallback)', () async {
    final dao = await freshDao('sos_offline.db');
    var calls = 0;
    final sync = SyncService(
      outbox: dao,
      poster: (path, body) async {
        calls++;
        throw StateError('offline'); // generic failure => stop draining
      },
    );
    final controller = SosController(outbox: dao, sync: sync);

    final sent = await controller.sendSos(
      lat: 9.98,
      lng: 76.28,
      profile: const MedicalProfile(), // empty card is fine for the fallback
      deviceId: 'device-9',
      messageId: 'sos-offline-1',
    );

    expect(sent, isFalse);
    expect(calls, 1);
    final pending = await dao.pending();
    expect(pending.single.id, 'sos-offline-1');
    expect(pending.single.type, MessageType.sos);
    expect(pending.single.priority, MessagePriority.high);
  });
}
