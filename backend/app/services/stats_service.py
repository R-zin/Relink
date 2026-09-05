"""Consolidated hazard metrics for `GET /stats` (Phase 4).

Fans out to the external telemetry adapters concurrently. Each adapter opens
its OWN DB session — SQLAlchemy's AsyncSession does not permit concurrent
operations on a shared session. Optional metrics (marine, eonet) degrade to
`{"unavailable": true}` on failure so one bad source never blocks the rest.
"""

import asyncio
import logging
from datetime import UTC, datetime

from app.config import get_settings
from app.db import SessionLocal
from app.services.external_apis import dams, eonet, gfm, glofas, marine, weather

log = logging.getLogger(__name__)


async def _run(adapter_get, label: str, *, optional: bool = False) -> dict:
    try:
        async with SessionLocal() as db:
            return await adapter_get(db)
    except Exception as exc:  # noqa: BLE001
        if not optional:
            # Required metrics have fixtures; reaching here means even the
            # fixture failed — re-raise so the caller sees a real error.
            raise
        log.warning("optional metric %s unavailable: %s", label, exc)
        return {"unavailable": True, "source_label": label}


async def get_stats_metrics(region: str | None = None) -> dict:
    s = get_settings()
    glofas_m, weather_m, dams_m, gfm_m, marine_m, eonet_m = await asyncio.gather(
        _run(glofas.get_glofas, "glofas"),
        _run(weather.get_weather, "weather"),
        _run(dams.get_dams, "dams"),
        _run(gfm.get_gfm, "gfm"),
        _run(marine.get_marine, "marine", optional=True),
        _run(eonet.get_eonet, "eonet", optional=True),
    )
    return {
        "region": region or s.REGION_NAME,
        "fetched_at": datetime.now(UTC).isoformat(),
        "metrics": {
            "glofas": glofas_m,
            "weather": weather_m,
            "dams": dams_m,
            "gfm": gfm_m,
            "marine": marine_m,
            "eonet": eonet_m,
        },
    }
