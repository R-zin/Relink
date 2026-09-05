"""Rainfall + wind telemetry via the Open-Meteo Forecast API (no auth).

Cited as "IMD (Open-Meteo)" in UI copy — master plan §7. Returns the trailing
24 h rainfall total, the hourly precipitation curve (past 24 h + next 24 h),
and the max forecast wind gust.
"""

from datetime import UTC, datetime

import httpx
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.services.external_apis.cache import cached_fetch

METRIC = "weather"
_TIMEOUT = 10.0


async def _fetch() -> dict:
    s = get_settings()
    params = {
        "latitude": s.SEED_CENTER_LAT,
        "longitude": s.SEED_CENTER_LNG,
        "hourly": "precipitation,wind_gusts_10m",
        "past_days": 1,
        "forecast_days": 2,
        "timezone": "UTC",
    }
    async with httpx.AsyncClient(timeout=_TIMEOUT) as client:
        resp = await client.get(f"{s.OPEN_METEO_BASE_URL}/v1/forecast", params=params)
        resp.raise_for_status()
        body = resp.json()

    hourly = body["hourly"]
    times: list[str] = hourly["time"]
    precip: list[float | None] = hourly["precipitation"]
    gusts: list[float | None] = hourly["wind_gusts_10m"]

    now = datetime.now(UTC)
    hourly_curve = [
        {"time": t, "precipitation_mm": p, "wind_gust_kmh": g}
        for t, p, g in zip(times, precip, gusts, strict=False)
    ]

    # Trailing 24 h rainfall = hours strictly before the current hour.
    past = [p for t, p in zip(times, precip, strict=False) if p is not None and _hour(t) <= now]
    rainfall_24h = round(sum(past[-24:]), 1) if past else 0.0
    future_gusts = [g for t, g in zip(times, gusts, strict=False) if g is not None and _hour(t) > now]
    max_gust = round(max(future_gusts), 1) if future_gusts else 0.0

    return {
        "rainfall_24h_mm": rainfall_24h,
        "max_gust_kmh": max_gust,
        "hourly": hourly_curve,
        "source_label": "IMD (Open-Meteo)",
    }


def _hour(iso: str) -> datetime:
    return datetime.fromisoformat(iso).replace(tzinfo=UTC)


async def get_weather(db: AsyncSession, ttl_minutes: int | None = None) -> dict:
    s = get_settings()
    return await cached_fetch(db, METRIC, _fetch, ttl_minutes or s.STATS_TTL_MINUTES)
