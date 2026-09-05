import 'dart:convert';
import 'dart:typed_data';

import '../models/mesh_message.dart';

/// Codec for serializing/deserializing MeshMessage over Nearby Connections BLE.
/// Master plan §7: UTF-8 JSON wire representation with a strict 32 KB payload guard.
class MeshMessageCodec {
  /// Strict limit: Nearby Connections payload under P2P_CLUSTER should avoid
  /// huge blobs that cause buffer saturation on low-end BLE stacks.
  static const int maxPayloadBytes = 32 * 1024; // 32 KB

  static Uint8List encode(MeshMessage message) {
    final raw = message.encode();
    final bytes = Uint8List.fromList(utf8.encode(raw));
    if (bytes.length > maxPayloadBytes) {
      throw ArgumentError(
        'MeshMessage payload (${bytes.length} bytes) exceeds limit of $maxPayloadBytes bytes',
      );
    }
    return bytes;
  }

  static MeshMessage decode(Uint8List bytes) {
    if (bytes.length > maxPayloadBytes) {
      throw ArgumentError(
        'Incoming payload (${bytes.length} bytes) exceeds limit of $maxPayloadBytes bytes',
      );
    }
    final raw = utf8.decode(bytes);
    return MeshMessage.decode(raw);
  }
}
