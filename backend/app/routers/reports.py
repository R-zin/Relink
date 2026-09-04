import uuid

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import get_db
from app.models import Report
from app.schemas import (
    ClusterResultOut,
    ConfirmResult,
    ReportCreate,
    ReportOut,
    ReportType,
)
from app.services import bounding_box, parse_device_uuid, upsert_device, within_radius
from app.services.clustering import cluster_reports

router = APIRouter(prefix="/reports", tags=["reports"])


@router.post("", status_code=201, response_model=ReportOut)
async def create_report(body: ReportCreate, db: AsyncSession = Depends(get_db)):
    device_uuid = parse_device_uuid(body.device_id)
    await upsert_device(db, device_uuid)
    report = Report(
        type=body.type.value,
        lat=body.lat,
        lng=body.lng,
        description=body.description,
        device_id=device_uuid,
    )
    db.add(report)
    await db.commit()
    await db.refresh(report)
    return report


@router.post("/{report_id}/confirm", response_model=ConfirmResult)
async def confirm_report(report_id: uuid.UUID, db: AsyncSession = Depends(get_db)):
    stmt = (
        update(Report)
        .where(Report.id == report_id)
        .values(confirm_count=Report.confirm_count + 1, last_confirmed_at=func.now())
        .returning(Report.id, Report.confirm_count, Report.last_confirmed_at)
    )
    row = (await db.execute(stmt)).one_or_none()
    if row is None:
        raise HTTPException(status_code=404, detail="report not found")
    await db.commit()
    return ConfirmResult(id=row.id, confirm_count=row.confirm_count, last_confirmed_at=row.last_confirmed_at)


@router.get("", response_model=list[ReportOut])
async def list_reports(
    type: ReportType | None = Query(default=None),
    lat: float | None = Query(default=None, ge=-90, le=90),
    lng: float | None = Query(default=None, ge=-180, le=180),
    radius_km: float = Query(default=25, gt=0, le=500),
    limit: int = Query(default=200, ge=1, le=1000),
    db: AsyncSession = Depends(get_db),
):
    stmt = select(Report)
    if type is not None:
        stmt = stmt.where(Report.type == type.value)
    if lat is not None and lng is not None:
        min_lat, max_lat, min_lng, max_lng = bounding_box(lat, lng, radius_km)
        stmt = stmt.where(Report.lat.between(min_lat, max_lat), Report.lng.between(min_lng, max_lng))
        rows = (await db.execute(stmt)).scalars().all()
        return within_radius(rows, lat, lng, radius_km)[:limit]
    stmt = stmt.order_by(Report.created_at.desc()).limit(limit)
    return (await db.execute(stmt)).scalars().all()


@router.get("/clusters", response_model=ClusterResultOut)
async def report_clusters(
    type: ReportType | None = Query(default=None),
    eps_m: float = Query(default=500, gt=0, le=50_000),
    min_samples: int = Query(default=2, ge=1, le=100),
    db: AsyncSession = Depends(get_db),
):
    stmt = select(Report)
    if type is not None:
        stmt = stmt.where(Report.type == type.value)
    rows = (await db.execute(stmt)).scalars().all()
    return cluster_reports(list(rows), eps_m=eps_m, min_samples=min_samples)
