import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:relink_mobile/locator/locator_protocol.dart';

void main() {
  group('LocatorProtocol encode/decode round-trip', () {
    test('QUERY round-trips type, person hash, and sequence', () async {
      final bytes = await LocatorProtocol.encodeQuery('Rahul Nair', 7);
      expect(bytes.length, LocatorProtocol.frameLength);

      final packet = LocatorProtocol.decode(bytes);
      expect(packet, isNotNull);
      expect(packet!.isQuery, isTrue);
      expect(packet.isFound, isFalse);
      expect(packet.sequence, 7);
      expect(
        packet.matchesHash(await LocatorProtocol.personHash('Rahul Nair')),
        isTrue,
      );
    });

    test('FOUND round-trips type and hash', () async {
      final bytes = await LocatorProtocol.encodeFound('Priya Nair', 200);
      final packet = LocatorProtocol.decode(bytes);
      expect(packet, isNotNull);
      expect(packet!.isFound, isTrue);
      expect(packet.sequence, 200);
      expect(
        packet.matchesHash(await LocatorProtocol.personHash('Priya Nair')),
        isTrue,
      );
    });

    test('sequence wraps to a single byte', () async {
      final bytes = await LocatorProtocol.encodeQuery('X', 256 + 9);
      final packet = LocatorProtocol.decode(bytes);
      expect(packet!.sequence, 9);
    });
  });

  group('LocatorProtocol hash matching', () {
    test('a QUERY for person X matches person X, not person Y', () async {
      final bytes = await LocatorProtocol.encodeQuery('Rahul Nair', 1);
      final packet = LocatorProtocol.decode(bytes)!;
      expect(await LocatorProtocol.matchesName(packet, 'Rahul Nair'), isTrue);
      expect(await LocatorProtocol.matchesName(packet, 'Asha Verma'), isFalse);
    });

    test('normalization makes case/whitespace variants match', () async {
      expect(
        LocatorProtocol.normalizePersonName('  Rahul   NAIR '),
        'rahul nair',
      );
      final hashA = await LocatorProtocol.personHash('Rahul Nair');
      final hashB = await LocatorProtocol.personHash('  RAHUL   nair');
      expect(hashA, equals(hashB));
    });

    test('matchesHash rejects wrong-length hashes', () async {
      final bytes = await LocatorProtocol.encodeQuery('Rahul Nair', 1);
      final packet = LocatorProtocol.decode(bytes)!;
      expect(packet.matchesHash(Uint8List.fromList([1, 2, 3])), isFalse);
    });
  });

  group('LocatorProtocol malformed input', () {
    test('rejects wrong length', () {
      expect(LocatorProtocol.decode(Uint8List.fromList([1, 2, 3])), isNull);
      expect(
        LocatorProtocol.decode(
            Uint8List(LocatorProtocol.frameLength + 1)),
        isNull,
      );
    });

    test('rejects wrong version', () {
      final frame = Uint8List(LocatorProtocol.frameLength)
        ..[0] = 0x99 // bad version
        ..[1] = LocatorProtocol.typeQuery;
      expect(LocatorProtocol.decode(frame), isNull);
    });

    test('rejects unknown type byte', () {
      final frame = Uint8List(LocatorProtocol.frameLength)
        ..[0] = LocatorProtocol.protocolVersion
        ..[1] = 0x7F; // not QUERY/FOUND
      expect(LocatorProtocol.decode(frame), isNull);
    });
  });
}
