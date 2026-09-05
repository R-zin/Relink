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
    state: str | None = Query(default=None),
    include_expired: bool = Query(default=False),
    limit: int = Query(default=50, ge=1, le=200),
    db: AsyncSession = Depends(get_db),
):
    from sqlalchemy import func, or_
    from app.config import get_settings

    s = get_settings()
    stmt = (
        select(AlertCache)
        .order_by(AlertCache.issued_at.desc().nulls_last(), AlertCache.created_at.desc())
        .limit(limit)
    )

    # When state is specified (and not an 'all' wildcard), filter unless backend is in all-India mode serving legacy 'kerala'
    if state and state.lower() not in ("all", "india", "all_india", "*"):
        if s.ALERTS_STATE.lower() != "all" or state.lower() != "kerala":
            stmt = stmt.where(
                or_(
                    AlertCache.state == state.lower(),
                    AlertCache.area_desc.ilike(f"%{state}%"),
                    AlertCache.is_test == 1,
                )
            )

    if not include_expired:
        # Active = no expiry recorded, or expiry still in the future.
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
