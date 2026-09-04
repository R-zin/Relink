import 'dart:convert';

/// Mesh message schema from the master plan (CLAUDE.md §7).
///
/// The outbox stores this verbatim as JSON; the BLE flooding protocol in
/// Phase 3 sends it as-is. Do not add fields without updating the master plan.
enum MessageType {
  sos('SOS'),
  report('REPORT'),
  missingPerson('MISSING_PERSON'),
  shelter('SHELTER');

  const MessageType(this.wire);
  final String wire;

  static MessageType fromWire(String value) => MessageType.values.firstWhere(
        (t) => t.wire == value,
        orElse: () => throw ArgumentError('unknown message type: $value'),
      );
}

enum MessagePriority {
  high('high'),
  normal('normal');

  const MessagePriority(this.wire);
  final String wire;

  static MessagePriority fromWire(String value) =>
      MessagePriority.values.firstWhere(
        (p) => p.wire == value,
        orElse: () => throw ArgumentError('unknown priority: $value'),
      );
}

class MeshMessage {
  final String id; // uuid v4
  final MessageType type;
  final String originDeviceId;
  final int ttl;
  final MessagePriority priority;
  final String timestamp; // ISO8601
  final Map<String, dynamic> payload;
  final String? encryptedPayload; // base64 AES-GCM (medical card, SOS only)

  const MeshMessage({
    required this.id,
    required this.type,
    required this.originDeviceId,
    this.ttl = 6,
    this.priority = MessagePriority.normal,
    required this.timestamp,
    required this.payload,
    this.encryptedPayload,
  });

  MeshMessage copyWith({int? ttl}) => MeshMessage(
        id: id,
        type: type,
        originDeviceId: originDeviceId,
        ttl: ttl ?? this.ttl,
        priority: priority,
        timestamp: timestamp,
        payload: payload,
        encryptedPayload: encryptedPayload,
      );

  factory MeshMessage.fromJson(Map<String, dynamic> json) => MeshMessage(
        id: json['id'] as String,
        type: MessageType.fromWire(json['type'] as String),
        originDeviceId: json['origin_device_id'] as String,
        ttl: (json['ttl'] as num?)?.toInt() ?? 6,
        priority: MessagePriority.fromWire(json['priority'] as String? ?? 'normal'),
        timestamp: json['timestamp'] as String,
        payload: Map<String, dynamic>.from(json['payload'] as Map? ?? const {}),
        encryptedPayload: json['encrypted_payload'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.wire,
        'origin_device_id': originDeviceId,
        'ttl': ttl,
        'priority': priority.wire,
        'timestamp': timestamp,
        'payload': payload,
        if (encryptedPayload != null) 'encrypted_payload': encryptedPayload,
      };

  String encode() => jsonEncode(toJson());

  factory MeshMessage.decode(String raw) =>
      MeshMessage.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}
