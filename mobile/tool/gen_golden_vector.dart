// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

/// Dev tool: emit a deterministic AES-256-GCM golden vector as JSON to stdout.
///
/// The backend test `tests/test_medical_crypto.py` loads the JSON file this
/// writes and proves Python can decrypt exactly what Dart produces — the
/// cross-language contract (phase_3.md §8/§10).
///
/// Run from mobile/:
///   dart run tool/gen_golden_vector.dart > ../backend/tests/golden_vector.json
Future<void> main() async {
  // Fixed key + fixed nonce => fully deterministic ciphertext. This is a TEST
  // vector only; the app uses a random nonce per message (see medical_crypto.dart).
  final key = base64Decode('AvhVqE/lK/Jv/o5kalpkYjBKHJSxolRrw9j52m1qqCQ=');
  final nonce = base64Decode('MTIzNDU2Nzg5MGFi'); // "1234567890ab" — exactly 12 bytes
  final sensitive = <String, dynamic>{
    'conditions': 'Asthma, Type-2 Diabetes',
    'medications': 'Salbutamol inhaler, Metformin 500mg',
    'insurance_provider': 'Star Health',
    'insurance_policy_number': 'P/161130/01/2024/000001',
  };

  final algo = AesGcm.with256bits();
  final box = await algo.encrypt(
    utf8.encode(jsonEncode(sensitive)),
    secretKey: SecretKey(key),
    nonce: nonce,
  );

  final out = {
    'comment':
        'Golden cross-language vector. Dart AesGcm.with256bits SecretBox.concatenation() == base64([12B nonce][ciphertext][16B tag]). Python AESGCM must decrypt to `expected`.',
    'key_base64': base64Encode(key),
    'nonce_base64': base64Encode(nonce),
    'ciphertext_base64': base64Encode(box.concatenation()),
    'expected': sensitive,
  };
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(out));
}
