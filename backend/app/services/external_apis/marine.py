"""Coastal swell for Cochin port via the Open-Meteo Marine API (no auth).

Cited as "INCOIS (Open-Meteo)" in UI copy — master plan §7. Optional metric:
failures are non-fatal and simply mark the metric unavailable.
"""

from datetime import UTC, datetime

import httpx
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.services.external_apis.cache import cached_fetch

METRIC = "marine"
_TIMEOUT = 10.0
# Cochin port approach
_LAT, _LNG = 9.94, 76.22


async def _fetch() -> dict:
    s = get_settings()
    params = {
        "latitude": _LAT,
        "longitude": _LNG,
        "hourly": "wave_height,swell_wave_height,swell_wave_period",
        "forecast_days": 2,
        "timezone": "UTC",
    }
    async with httpx.AsyncClient(timeout=_TIMEOUT) as client:
        resp = await client.get(f"{s.OPEN_METEO_MARINE_URL}/v1/marine", params=params)
        resp.raise_for_status()
        body = resp.json()

    hourly = body["hourly"]
    now = datetime.now(UTC)
    heights = [
        h for t, h in zip(hourly["time"], hourly["wave_height"], strict=False)
        if h is not None and datetime.fromisoformat(t).replace(tzinfo=UTC) >= now
    ]
    swells = [
        h for t, h in zip(hourly["time"], hourly["swell_wave_height"], strict=False)
        if h is not None and datetime.fromisoformat(t).replace(tzinfo=UTC) >= now
    ]
    if not heights:
        raise ValueError("marine API returned no wave-height values")
    return {
        "wave_height_m": round(heights[0], 2),
        "max_wave_24h_m": round(max(heights[:24]), 2),
        "swell_height_m": round(swells[0], 2) if swells else None,
        "source_label": "INCOIS (Open-Meteo Marine)",
    }


async def get_marine(db: AsyncSession, ttl_minutes: int | None = None) -> dict:
    s = get_settings()
    return await cached_fetch(db, METRIC, _fetch, ttl_minutes or s.STATS_TTL_MINUTES)
