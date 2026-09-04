from fastapi import APIRouter, Depends, Query
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import get_db
from app.models import SosEvent
from app.schemas import SosCreate, SosCreated, SosEventOut, SosStatus
from app.services import parse_device_uuid, upsert_device

router = APIRouter(prefix="/sos", tags=["sos"])


@router.post("", status_code=201, response_model=SosCreated)
async def create_sos(body: SosCreate, db: AsyncSession = Depends(get_db)):
    device_uuid = parse_device_uuid(body.device_id)
    await upsert_device(db, device_uuid)
    event = SosEvent(
        device_id=device_uuid,
        lat=body.lat,
        lng=body.lng,
        plaintext_medical=(body.plaintext_medical.model_dump() if body.plaintext_medical else None),
        encrypted_medical=body.encrypted_medical,  # stored opaquely — never inspected server-side
    )
    db.add(event)
    await db.commit()
    await db.refresh(event)
    return SosCreated(id=event.id, created_at=event.created_at)


@router.get("", response_model=list[SosEventOut])
async def list_sos(
    status: SosStatus | None = Query(default=None),
    limit: int = Query(default=100, ge=1, le=1000),
    db: AsyncSession = Depends(get_db),
):
    stmt = select(SosEvent).order_by(SosEvent.created_at.desc()).limit(limit)
    if status is not None:
        stmt = stmt.where(SosEvent.status == status.value)
    result = await db.execute(stmt)
    return result.scalars().all()
