import os
import secrets

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from app.config import get_settings
from app.services.medical_crypto import MedicalDecryptError, decrypt_medical

router = APIRouter(prefix="/medical", tags=["medical"])


class DecryptRequest(BaseModel):
    ciphertext: str = Field(..., min_length=1, max_length=10_000)
    demo_pass: str = Field(..., min_length=1, max_length=256)


class DecryptResponse(BaseModel):
    status: str
    decrypted_data: dict


@router.post("/decrypt", response_model=DecryptResponse)
async def medical_decrypt(body: DecryptRequest):
    """Responder break-glass decrypt of an SOS medical card's sensitive fields.

    Decrypted on view, never stored. Auth uses constant-time secret comparison.
    """
    settings = get_settings()
    configured_pass = (
        getattr(settings, "DECRYPT_DEMO_PASS", None)
        or os.environ.get("DECRYPT_DEMO_PASS", "relink-demo")
    )

    if not secrets.compare_digest(body.demo_pass.strip().encode("utf-8"), configured_pass.encode("utf-8")):
        raise HTTPException(status_code=401, detail="unauthorized")

    try:
        data = decrypt_medical(body.ciphertext)
    except MedicalDecryptError as exc:
        raise HTTPException(status_code=422, detail="Invalid ciphertext or decryption failed") from exc
    return DecryptResponse(status="success", decrypted_data=data)
