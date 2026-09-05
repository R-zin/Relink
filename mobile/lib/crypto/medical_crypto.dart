import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'demo_key.dart';

/// AES-256-GCM encryption of the SOS medical card's sensitive fields.
///
/// Locked spec (master plan §5, phase_3.md §7):
///   envelope = Base64( [12-byte Nonce] || [Ciphertext] || [16-byte GCM Tag] )
///
/// The `cryptography` package's `SecretBox.concatenation()` produces exactly
/// `nonce || ciphertext || mac`, which matches this layout byte-for-byte, and
/// its `fromConcatenation()` splits it back on decrypt. That gives us a clean
/// cross-platform contract with the Python `AESGCM` backend decrypt endpoint.
///
/// Safety rule (phase_3.md §7.2): if the key is missing/invalid, callers fall
/// back to sending the SOS unencrypted — encryption never blocks a beacon.
class MedicalCrypto {
  MedicalCrypto({AesGcm? algorithm}) : _algo = algorithm ?? AesGcm.with256bits();

  final AesGcm _algo;

  static const int nonceLength = 12; // 96-bit GCM nonce
  static const int tagLength = 16; // 128-bit GCM tag

  /// Encrypt [plaintextJson] (a JSON-encoded map of sensitive fields) with the
  /// demo key. Returns the Base64 envelope string, or `null` when no valid key
  /// is configured (caller must then send unencrypted).
  Future<String?> encryptFields(Map<String, dynamic> plaintextJson) async {
    final keyBytes = MedicalDemoKey.load();
    if (keyBytes == null) return null;
    final plaintext = utf8.encode(jsonEncode(plaintextJson));
    return encryptBytes(plaintext, keyBytes);
  }

  /// Encrypt raw bytes with an explicit key — exposed for tests and for the
  /// golden cross-language vector. Omitting `nonce` lets the `cryptography`
  /// package generate a fresh cryptographically-secure 12-byte nonce per call
  /// (correct for production); a fixed [nonce] is only for deterministic tests.
  Future<String> encryptBytes(
    List<int> plaintext,
    Uint8List keyBytes, {
    List<int>? nonce,
  }) async {
    final secretKey = SecretKey(keyBytes);
    final box = await _algo.encrypt(
      plaintext,
      secretKey: secretKey,
      nonce: nonce ?? _algo.newNonce(),
    );
    // SecretBox.concatenation() == nonce || ciphertext || mac — our wire spec.
    return base64Encode(box.concatenation());
  }

  /// Decrypt a Base64 envelope back to the sensitive-fields map. Throws
  /// [MedicalCryptoException] on malformed input or auth-tag failure. Kept for
  /// completeness/tests — the production decrypt path lives in the backend and
  /// the Phase 4 Command Dashboard, not on-device.
  Future<Map<String, dynamic>> decryptFields(
    String envelopeBase64,
    Uint8List keyBytes,
  ) async {
    final plaintext = await decryptBytes(envelopeBase64, keyBytes);
    try {
      return Map<String, dynamic>.from(
          jsonDecode(utf8.decode(plaintext)) as Map);
    } catch (e) {
      throw MedicalCryptoException('decrypted payload is not valid JSON: $e');
    }
  }

  /// Decrypt a Base64 envelope to raw bytes with an explicit key.
  Future<Uint8List> decryptBytes(
      String envelopeBase64, Uint8List keyBytes) async {
    final Uint8List combined;
    try {
      combined = base64Decode(envelopeBase64);
    } catch (e) {
      throw MedicalCryptoException('ciphertext is not valid base64: $e');
    }
    if (combined.length < nonceLength + tagLength) {
      throw MedicalCryptoException(
          'ciphertext too short (${combined.length} bytes)');
    }
    final box = SecretBox.fromConcatenation(
      combined,
      nonceLength: nonceLength,
      macLength: tagLength,
    );
    try {
      final clear = await _algo.decrypt(box, secretKey: SecretKey(keyBytes));
      return Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      throw MedicalCryptoException(
          'authentication failed — wrong key or corrupted ciphertext');
    } catch (e) {
      throw MedicalCryptoException('decryption failed: $e');
    }
  }
}

class MedicalCryptoException implements Exception {
  MedicalCryptoException(this.message);
  final String message;
  @override
  String toString() => 'MedicalCryptoException: $message';
}
