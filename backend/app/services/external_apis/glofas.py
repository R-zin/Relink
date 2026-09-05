"""GloFAS river-discharge forecast via the Open-Meteo Flood API (no auth).

Live source for the Periyar river basin. Returns the latest discharge, the
7-day forecast curve, and a rising/falling/steady trend vs the discharge mean.
"""

import httpx
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.services.external_apis.cache import cached_fetch

METRIC = "glofas"
_TIMEOUT = 10.0


async def _fetch() -> dict:
    s = get_settings()
    params = {
        "latitude": s.GLOFAS_LAT,
        "longitude": s.GLOFAS_LNG,
        "daily": "river_discharge,river_discharge_mean",
        "forecast_days": 7,
    }
    async with httpx.AsyncClient(timeout=_TIMEOUT) as client:
        resp = await client.get(f"{s.OPEN_METEO_FLOOD_URL}/v1/flood", params=params)
        resp.raise_for_status()
        body = resp.json()

    daily = body["daily"]
    times: list[str] = daily["time"]
    discharge: list[float | None] = daily["river_discharge"]
    mean: list[float | None] = daily.get("river_discharge_mean", [None] * len(times))

    latest = discharge[0] if discharge else None
    mean0 = mean[0] if mean else None
    if latest is None:
        raise ValueError("GloFAS returned no discharge values")

    trend = "steady"
    if mean0 is not None:
        if latest > mean0 * 1.05:
            trend = "rising"
        elif latest < mean0 * 0.95:
            trend = "falling"

    forecast = [
        {"date": t, "discharge_m3s": d, "mean_m3s": m}
        for t, d, m in zip(times, discharge, mean, strict=False)
    ]
    return {
        "discharge_m3s": latest,
        "mean_m3s": mean0,
        "trend": trend,
        "forecast": forecast,
        "lat": body.get("latitude"),
        "lng": body.get("longitude"),
        "source_label": "GloFAS Flood API",
    }


async def get_glofas(db: AsyncSession, ttl_minutes: int | None = None) -> dict:
    s = get_settings()
    return await cached_fetch(db, METRIC, _fetch, ttl_minutes or s.STATS_TTL_MINUTES)
