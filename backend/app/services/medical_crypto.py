"""AES-256-GCM decryption of the SOS medical card's sensitive fields.

Locked cross-platform spec (master plan §5, phase_3.md §7/§8):
    envelope = Base64( [12-byte Nonce] || [Ciphertext] || [16-byte GCM Tag] )

This is exactly what the Dart `cryptography` package's `SecretBox.concatenation()`
emits on-device. Python's `AESGCM.decrypt` expects `nonce || (ciphertext+tag)`
as two arguments, so we split off the 12-byte nonce and pass the rest verbatim.

The pre-shared demo key (MEDICAL_CARD_DEMO_KEY) is base64-encoded 32 bytes,
shared between the app build and this responder-side endpoint.
"""

import base64
import binascii
import json
import os

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

NONCE_LEN = 12
TAG_LEN = 16
KEY_LEN = 32  # AES-256


class MedicalDecryptError(Exception):
    """Raised for any malformed-input / decrypt failure (mapped to 422)."""


def _load_key() -> bytes:
    from app.config import get_settings
    settings = get_settings()
    raw = settings.MEDICAL_CARD_DEMO_KEY or os.environ.get("MEDICAL_CARD_DEMO_KEY", "")
    if not raw:
        raise MedicalDecryptError("server is not configured with MEDICAL_CARD_DEMO_KEY")
    try:
        key = base64.b64decode(raw)
    except binascii.Error as exc:
        raise MedicalDecryptError(f"server key is not valid base64: {exc}") from exc
    if len(key) != KEY_LEN:
        raise MedicalDecryptError(f"server key must be {KEY_LEN} bytes, got {len(key)}")
    return key


def decrypt_medical(envelope_base64: str) -> dict:
    """Decrypt a Base64 envelope to the sensitive-fields dict.

    Raises MedicalDecryptError on malformed base64, short payload, auth-tag
    failure, or non-JSON plaintext.
    """
    key = _load_key()

    try:
        combined = base64.b64decode(envelope_base64)
    except binascii.Error as exc:
        raise MedicalDecryptError(f"ciphertext is not valid base64: {exc}") from exc

    if len(combined) < NONCE_LEN + TAG_LEN:
        raise MedicalDecryptError(
            f"ciphertext too short ({len(combined)} bytes); need at least {NONCE_LEN + TAG_LEN}"
        )

    nonce = combined[:NONCE_LEN]
    ciphertext_and_tag = combined[NONCE_LEN:]

    try:
        plaintext = AESGCM(key).decrypt(nonce, ciphertext_and_tag, associated_data=None)
    except Exception as exc:  # cryptography raises InvalidTag (and friends)
        raise MedicalDecryptError(f"decryption failed — wrong key or corrupted ciphertext: {exc}") from exc

    try:
        return json.loads(plaintext.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise MedicalDecryptError(f"decrypted payload is not valid JSON: {exc}") from exc
