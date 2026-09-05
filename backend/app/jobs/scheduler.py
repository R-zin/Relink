"""APScheduler background jobs (Phase 4).

- `poll_sachet`   every 10 min — ingest NDMA Sachet CAP alerts into alerts_cache.
- `refresh_stats` every 15 min — warm stats_cache so /stats responds instantly.

Both run a single poll immediately at startup so the caches are populated
before the first request. Every job opens its own DB session; failures are
logged, never crash the scheduler.
"""

import logging

from apscheduler.schedulers.asyncio import AsyncIOScheduler

from app.db import SessionLocal
from app.services import alerts_service
from app.services.stats_service import get_stats_metrics

log = logging.getLogger(__name__)

scheduler = AsyncIOScheduler(timezone="UTC")


async def poll_sachet_job() -> None:
    try:
        async with SessionLocal() as db:
            await alerts_service.poll_sachet(db)
    except Exception:  # noqa: BLE001
        log.exception("poll_sachet job failed")


async def refresh_stats_job() -> None:
    try:
        await get_stats_metrics()
    except Exception:  # noqa: BLE001
        log.exception("refresh_stats job failed")


def start_scheduler() -> AsyncIOScheduler:
    if scheduler.running:
        return scheduler
    scheduler.add_job(poll_sachet_job, "interval", minutes=10, id="poll_sachet", replace_existing=True)
    scheduler.add_job(refresh_stats_job, "interval", minutes=15, id="refresh_stats", replace_existing=True)
    scheduler.start()
    log.info("APScheduler started (poll_sachet=10m, refresh_stats=15m)")
    return scheduler


def shutdown_scheduler() -> None:
    if scheduler.running:
        scheduler.shutdown(wait=False)
