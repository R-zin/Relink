import 'package:flutter_test/flutter_test.dart';
import 'package:relink_mobile/models/mesh_message.dart';
import 'package:relink_mobile/services/api_client.dart';

/// Golden-map assertions: each MeshMessage.type maps to the correct Phase 1
/// endpoint and request-body shape (Phase 2 §10).
void main() {
  MeshMessage envelope(MessageType type, Map<String, dynamic> payload,
          {String? encryptedPayload}) =>
      MeshMessage(
        id: 'msg-1',
        type: type,
        originDeviceId: 'device-9',
        priority: type == MessageType.sos
            ? MessagePriority.high
            : MessagePriority.normal,
        timestamp: '2026-09-05T08:00:00.000Z',
        payload: payload,
        encryptedPayload: encryptedPayload,
      );

  test('SOS -> /sos with device_id + coords + medical fields', () {
    final req = envelopeRequest(
      envelope(MessageType.sos, {
        'lat': 9.98,
        'lng': 76.28,
        'plaintext_medical': {'name': 'Asha', 'blood_group': 'O+'},
      }, encryptedPayload: 'Y2lwaGVy'),
    );

    expect(req.path, '/sos');
    expect(req.body, {
      'device_id': 'device-9',
      'lat': 9.98,
      'lng': 76.28,
      'plaintext_medical': {'name': 'Asha', 'blood_group': 'O+'},
      'encrypted_medical': 'Y2lwaGVy',
    });
  });

  test('SOS omits absent optional fields', () {
    final req =
        envelopeRequest(envelope(MessageType.sos, {'lat': 9.9, 'lng': 76.2}));
    expect(req.body, {
      'device_id': 'device-9',
      'lat': 9.9,
      'lng': 76.2,
    });
  });

  test('REPORT -> /reports with type + description + device_id', () {
    final req = envelopeRequest(
      envelope(MessageType.report, {
        'type': 'water',
        'lat': 9.98,
        'lng': 76.28,
        'description': 'knee-deep water',
      }),
    );

    expect(req.path, '/reports');
    expect(req.body, {
      'type': 'water',
      'lat': 9.98,
      'lng': 76.28,
      'description': 'knee-deep water',
      'device_id': 'device-9',
    });
  });

  test('SHELTER -> /shelters with name + contact_info + added_by', () {
    final req = envelopeRequest(
      envelope(MessageType.shelter, {
        'name': 'Govt. HSS Relief Camp',
        'lat': 10.0,
        'lng': 76.3,
        'contact_info': '+91 90000 00000',
      }),
    );

    expect(req.path, '/shelters');
    expect(req.body, {
      'name': 'Govt. HSS Relief Camp',
      'lat': 10.0,
      'lng': 76.3,
      'contact_info': '+91 90000 00000',
      'added_by': 'device-9',
    });
  });

  test('MISSING_PERSON -> /missing-persons with last_seen + reporter id', () {
    final req = envelopeRequest(
      envelope(MessageType.missingPerson, {
        'name': 'Ravi',
        'last_seen_lat': 9.97,
        'last_seen_lng': 76.27,
        'description': 'blue shirt, approx 60',
      }),
    );

    expect(req.path, '/missing-persons');
    expect(req.body, {
      'name': 'Ravi',
      'last_seen_lat': 9.97,
      'last_seen_lng': 76.27,
      'description': 'blue shirt, approx 60',
      'reporter_device_id': 'device-9',
    });
  });
}
