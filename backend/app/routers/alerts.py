from fastapi import APIRouter, Depends, Query
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import get_db
from app.models import AlertCache
from app.schemas import AlertOut
from app.services import alerts_service

router = APIRouter(prefix="/alerts", tags=["alerts"])


@router.get("", response_model=list[AlertOut])
async def list_alerts(
    state: str = Query(default="kerala"),
    include_expired: bool = Query(default=False),
    limit: int = Query(default=50, ge=1, le=200),
    db: AsyncSession = Depends(get_db),
):
    stmt = (
        select(AlertCache)
        .where(AlertCache.state == state.lower())
        .order_by(AlertCache.issued_at.desc().nulls_last(), AlertCache.created_at.desc())
        .limit(limit)
    )
    if not include_expired:
        # Active = no expiry recorded, or expiry still in the future.
        from sqlalchemy import or_, func

        stmt = stmt.where(or_(AlertCache.expires.is_(None), AlertCache.expires > func.now()))
    result = await db.execute(stmt)
    return result.scalars().all()


@router.post("/test-alert", status_code=201, response_model=AlertOut)
async def trigger_test_alert(db: AsyncSession = Depends(get_db)):
    """Demo trigger: synthesises a Red flood warning so judges can watch the
    end-to-end alerting path (dashboard ticker + phone heads-up notification)."""
    return await alerts_service.create_test_alert(db)


@router.post("/poll", status_code=202)
async def manual_poll(db: AsyncSession = Depends(get_db)):
    """Ops convenience: run one Sachet poll immediately (outside the schedule)."""
    count = await alerts_service.poll_sachet(db)
    return {"upserted": count}
