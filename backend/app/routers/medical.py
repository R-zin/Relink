import os

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from app.services.medical_crypto import MedicalDecryptError, decrypt_medical

router = APIRouter(prefix="/medical", tags=["medical"])

# Break-glass demo auth (phase_3.md §8). A shared static passphrase is
# intentional hackathon scope — real responder auth is a roadmap item.
_DEMO_PASS = os.environ.get("DECRYPT_DEMO_PASS", "relink-demo")


class DecryptRequest(BaseModel):
    ciphertext: str  # base64 envelope: [12B nonce][ciphertext][16B tag]
    demo_pass: str


class DecryptResponse(BaseModel):
    status: str
    decrypted_data: dict


@router.post("/decrypt", response_model=DecryptResponse)
async def medical_decrypt(body: DecryptRequest):
    """Responder break-glass decrypt of an SOS medical card's sensitive fields.

    Decrypted on view, never stored. Auth is a static demo passphrase.
    """
    if body.demo_pass != _DEMO_PASS:
        # constant-time-ish: compare directly, no length/timing oracle worth
        # hardening for a static hackathon passphrase.
        raise HTTPException(status_code=401, detail="unauthorized")
    try:
        data = decrypt_medical(body.ciphertext)
    except MedicalDecryptError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    return DecryptResponse(status="success", decrypted_data=data)
