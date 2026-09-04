from fastapi import APIRouter, Depends, Query
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import get_db
from app.models import MissingPerson
from app.schemas import MissingPersonCreate, MissingPersonOut
from app.services import bounding_box, parse_device_uuid, upsert_device, within_radius

router = APIRouter(prefix="/missing-persons", tags=["missing-persons"])


@router.post("", status_code=201, response_model=MissingPersonOut)
async def create_missing_person(body: MissingPersonCreate, db: AsyncSession = Depends(get_db)):
    device_uuid = parse_device_uuid(body.reporter_device_id)
    await upsert_device(db, device_uuid)
    record = MissingPerson(
        name=body.name,  # stored as given; search normalizes case
        last_seen_lat=body.last_seen_lat,
        last_seen_lng=body.last_seen_lng,
        description=body.description,
        reporter_device_id=device_uuid,
    )
    db.add(record)
    await db.commit()
    await db.refresh(record)
    return record


@router.get("/search", response_model=list[MissingPersonOut])
async def search_missing_persons(
    name: str | None = Query(default=None),
    lat: float | None = Query(default=None, ge=-90, le=90),
    lng: float | None = Query(default=None, ge=-180, le=180),
    radius_km: float = Query(default=50, gt=0, le=1000),
    db: AsyncSession = Depends(get_db),
):
    stmt = select(MissingPerson)
    if name:
        stmt = stmt.where(MissingPerson.name.ilike(f"%{name}%"))  # case-insensitive substring
    if lat is not None and lng is not None:
        min_lat, max_lat, min_lng, max_lng = bounding_box(lat, lng, radius_km)
        stmt = stmt.where(
            MissingPerson.last_seen_lat.between(min_lat, max_lat),
            MissingPerson.last_seen_lng.between(min_lng, max_lng),
        )
        rows = (await db.execute(stmt)).scalars().all()
        return within_radius(rows, lat, lng, radius_km, lat_attr="last_seen_lat", lng_attr="last_seen_lng")
    stmt = stmt.order_by(MissingPerson.created_at.desc()).limit(50)  # empty query -> newest 50
    return (await db.execute(stmt)).scalars().all()
