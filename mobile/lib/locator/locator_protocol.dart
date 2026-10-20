import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Wire protocol for the missing-person BLE locator.
///
/// This is a NEW, connectionless raw-BLE layer that runs alongside — and fully
/// independently of — the Nearby Connections mesh (`lib/mesh/`). It exists
/// because Nearby Connections exposes neither advertisement payloads nor RSSI,
/// both of which this feature needs.
///
/// Contract (do not change without a coordinated update — both the rescuer and
/// the matched phone must agree byte-for-byte):
///
/// A QUERY or FOUND rides as **manufacturer data** (company id
/// [manufacturerCompanyId]) inside a legacy BLE advertisement that also carries
/// the app-owned [locatorServiceUuid]. The service UUID is the scan-filter key
/// (Android background scan delivery is only reliable with a UUID filter); the
/// manufacturer data carries the actual packet.
///
/// Frame layout (11 bytes):
/// ```
/// [0]    version    = protocolVersion
/// [1]    type       = typeQuery | typeFound
/// [2..9] personHash = first 8 bytes of SHA-256(normalizedPersonName)
/// [10]   sequence   = rolling counter (dedup / replay aid)
/// ```
class LocatorProtocol {
  LocatorProtocol._();

  /// App-owned 128-bit service UUID that identifies RELINK locator traffic.
  /// Random v4, minted once for this feature — MUST NEVER CHANGE once devices
  /// ship, or rescuer/victim phones stop seeing each other. Distinct from the
  /// Nearby Connections service id (`in.relink.mesh`).
  static const String locatorServiceUuid =
      '59d6e9dd-5538-44fd-887e-92c97e5a492c';

  /// Bluetooth SIG company identifier used in the manufacturer-specific data
  /// field. 0xFFFF is a reserved/test ID — fine for a self-contained build
  /// where every device is ours.
  static const int manufacturerCompanyId = 0xFFFF;

  static const int protocolVersion = 0x01;
  static const int typeQuery = 0x01;
  static const int typeFound = 0x02;

  /// Fixed on-wire frame size in bytes.
  static const int frameLength = 11;
  static const int _personHashLength = 8;

  /// Canonical form both sides hash: trim, collapse internal whitespace,
  /// lowercase. Without this, "Rahul Nair" and "  rahul   NAIR " would hash
  /// differently and never match.
  static String normalizePersonName(String name) =>
      name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static final Sha256 _sha = Sha256();

  static Future<Uint8List> personHash(String name) async {
    final digest = await _sha.hash(utf8.encode(normalizePersonName(name)));
    return Uint8List.fromList(digest.bytes.sublist(0, _personHashLength));
  }

  /// Encode a QUERY ("is person [name] nearby?") advertisement payload.
  static Future<Uint8List> encodeQuery(String name, int sequence) =>
      _encode(typeQuery, name, sequence);

  /// Encode a FOUND ("yes, I am person [name]") advertisement payload. The
  /// victim's responder builds its frame from its own pre-computed hash rather
  /// than via this helper, but the helper is kept for tests and symmetric use.
  static Future<Uint8List> encodeFound(String name, int sequence) =>
      _encode(typeFound, name, sequence);

  static Future<Uint8List> _encode(int type, String name, int sequence) async {
    final hash = await personHash(name);
    final frame = Uint8List(frameLength);
    frame[0] = protocolVersion;
    frame[1] = type;
    frame.setRange(2, 2 + _personHashLength, hash);
    frame[10] = sequence & 0xFF;
    return frame;
  }

  /// Parse a manufacturer-data payload into a [LocatorPacket], or return null
  /// for anything that isn't a well-formed current-version locator frame.
  /// Never throws — a radio layer must not crash on a malformed advertisement.
  static LocatorPacket? decode(Uint8List bytes) {
    if (bytes.length != frameLength) return null;
    if (bytes[0] != protocolVersion) return null;
    final type = bytes[1];
    if (type != typeQuery && type != typeFound) return null;
    return LocatorPacket(
      type: type == typeQuery ? LocatorPacketType.query : LocatorPacketType.found,
      personHash: Uint8List.fromList(bytes.sublist(2, 2 + _personHashLength)),
      sequence: bytes[10],
    );
  }

  /// True when [packet]'s person hash equals the hash of [myName]. Async
  /// because hashing is async; callers in the scan path pre-hash their own name
  /// once and compare bytes directly (see [LocatorPacket.matchesHash]).
  static Future<bool> matchesName(LocatorPacket packet, String myName) async =>
      packet.matchesHash(await personHash(myName));
}

enum LocatorPacketType { query, found }

/// A decoded locator advertisement.
class LocatorPacket {
  final LocatorPacketType type;
  final Uint8List personHash;
  final int sequence;

  const LocatorPacket({
    required this.type,
    required this.personHash,
    required this.sequence,
  });

  bool get isQuery => type == LocatorPacketType.query;
  bool get isFound => type == LocatorPacketType.found;

  /// Constant-length byte comparison against a pre-computed hash.
  bool matchesHash(Uint8List myHash) {
    if (myHash.length != personHash.length) return false;
    for (var i = 0; i < personHash.length; i++) {
      if (personHash[i] != myHash[i]) return false;
    }
    return true;
  }

  @override
  String toString() =>
      'LocatorPacket(${type.name}, seq=$sequence, hash=${personHash.map((b) => b.toRadixString(16).padLeft(2, '0')).join()})';
}
