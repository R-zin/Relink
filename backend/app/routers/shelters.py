import uuid

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import get_db
from app.models import Shelter
from app.schemas import ConfirmResult, ShelterCreate, ShelterOut
from app.services import bounding_box, parse_device_uuid, upsert_device, within_radius

router = APIRouter(prefix="/shelters", tags=["shelters"])


def _trust_order(stmt):
    """Most-confirmed, most-recently-verified first."""
    return stmt.order_by(Shelter.confirm_count.desc(), Shelter.last_confirmed_at.desc().nulls_last())


@router.post("", status_code=201, response_model=ShelterOut)
async def create_shelter(body: ShelterCreate, db: AsyncSession = Depends(get_db)):
    device_uuid = parse_device_uuid(body.added_by)
    await upsert_device(db, device_uuid)
    shelter = Shelter(
        name=body.name,
        lat=body.lat,
        lng=body.lng,
        contact_info=body.contact_info,
        added_by=device_uuid,
    )
    db.add(shelter)
    await db.commit()
    await db.refresh(shelter)
    return shelter


@router.post("/{shelter_id}/confirm", response_model=ConfirmResult)
async def confirm_shelter(shelter_id: uuid.UUID, db: AsyncSession = Depends(get_db)):
    stmt = (
        update(Shelter)
        .where(Shelter.id == shelter_id)
        .values(confirm_count=Shelter.confirm_count + 1, last_confirmed_at=func.now())
        .returning(Shelter.id, Shelter.confirm_count, Shelter.last_confirmed_at)
    )
    row = (await db.execute(stmt)).one_or_none()
    if row is None:
        raise HTTPException(status_code=404, detail="shelter not found")
    await db.commit()
    return ConfirmResult(id=row.id, confirm_count=row.confirm_count, last_confirmed_at=row.last_confirmed_at)


@router.get("", response_model=list[ShelterOut])
async def list_shelters(
    lat: float | None = Query(default=None, ge=-90, le=90),
    lng: float | None = Query(default=None, ge=-180, le=180),
    radius_km: float = Query(default=50, gt=0, le=1000),
    db: AsyncSession = Depends(get_db),
):
    stmt = _trust_order(select(Shelter))
    if lat is not None and lng is not None:
        min_lat, max_lat, min_lng, max_lng = bounding_box(lat, lng, radius_km)
        stmt = stmt.where(Shelter.lat.between(min_lat, max_lat), Shelter.lng.between(min_lng, max_lng))
        rows = (await db.execute(stmt)).scalars().all()
        return within_radius(rows, lat, lng, radius_km)
    return (await db.execute(stmt)).scalars().all()
