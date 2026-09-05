"""NASA EONET v3 — severe storms/cyclones within ~1500 km of Kochi (no auth)."""

import httpx
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.services import haversine_m
from app.services.external_apis.cache import cached_fetch

METRIC = "eonet"
_TIMEOUT = 10.0
_RADIUS_KM = 1500.0
# Categories of interest for this region.
_CATS = {"Severe Storms", "Sea and Lake Ice"}


async def _fetch() -> dict:
    s = get_settings()
    async with httpx.AsyncClient(timeout=_TIMEOUT) as client:
        resp = await client.get(f"{s.NASA_EONET_URL}/events", params={"status": "open", "limit": 50})
        resp.raise_for_status()
        body = resp.json()

    events = []
    for ev in body.get("events", []):
        cats = {c.get("title") for c in ev.get("categories", [])}
        if "Severe Storms" not in cats:
            continue
        geo = ev.get("geometry") or []
        if not geo:
            continue
        latest = geo[-1]
        coords = latest.get("coordinates") or []
        if len(coords) < 2:
            continue
        lng, lat = coords[0], coords[1]
        dist_km = haversine_m(s.SEED_CENTER_LAT, s.SEED_CENTER_LNG, lat, lng) / 1000.0
        if dist_km > _RADIUS_KM:
            continue
        events.append({
            "id": ev.get("id"),
            "title": ev.get("title"),
            "lat": lat,
            "lng": lng,
            "distance_km": round(dist_km),
            "date": latest.get("date"),
        })

    return {
        "events": events,
        "count": len(events),
        "radius_km": _RADIUS_KM,
        "source_label": "NASA EONET v3",
    }


async def get_eonet(db: AsyncSession, ttl_minutes: int | None = None) -> dict:
    s = get_settings()
    return await cached_fetch(db, METRIC, _fetch, ttl_minutes or s.STATS_TTL_MINUTES)
