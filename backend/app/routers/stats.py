from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.db import get_db
from app.schemas import AiReviewOut, StatsOut
from app.services import ai_review
from app.services.stats_service import get_stats_metrics

router = APIRouter(prefix="/stats", tags=["stats"])


@router.get("", response_model=StatsOut)
async def stats(
    region: str | None = Query(default=None),
    db: AsyncSession = Depends(get_db),  # noqa: ARG001 — signature parity; adapters own their sessions
):
    return await get_stats_metrics(region=region)


@router.get("/ai-review", response_model=AiReviewOut)
async def ai_review_endpoint(
    region: str | None = Query(default=None),
    db: AsyncSession = Depends(get_db),
):
    s = get_settings()
    return await ai_review.get_ai_review(db, region=region or s.REGION_NAME)
