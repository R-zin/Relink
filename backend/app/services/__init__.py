"""Shared service helpers: device upsert + geographic filtering.

(The Phase 1 file budget has no separate helpers module, so the small shared
bits every router needs live here.)
"""

import logging
import math
import uuid

from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Device

log = logging.getLogger(__name__)

KM_PER_DEG_LAT = 111.32


def parse_device_uuid(raw: str | None) -> uuid.UUID | None:
    """Client device ids arrive as strings (mesh payloads may carry arbitrary
    origin ids). Non-UUID strings are stored as NULL rather than failing the
    FK check — see plans/phase_1.md §4 device-upsert note."""
    if raw is None:
        return None
    try:
        return uuid.UUID(str(raw))
    except (ValueError, AttributeError, TypeError):
        log.warning("non-UUID device id %r received; storing NULL", raw)
        return None


async def upsert_device(session: AsyncSession, device_id: uuid.UUID | None) -> None:
    """INSERT ... ON CONFLICT (id) DO UPDATE SET last_seen = now()."""
    if device_id is None:
        return
    stmt = (
        pg_insert(Device)
        .values(id=device_id, platform="unknown")
        .on_conflict_do_update(index_elements=["id"], set_={"last_seen": func_now()})
    )
    await session.execute(stmt)


def func_now():
    from sqlalchemy import func

    return func.now()


def haversine_m(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """Great-circle distance in meters."""
    r = 6_371_000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlmb = math.radians(lng2 - lng1)
    a = math.sin(dphi / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dlmb / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


def bounding_box(lat: float, lng: float, radius_km: float) -> tuple[float, float, float, float]:
    """(min_lat, max_lat, min_lng, max_lng) cheap prefilter for haversine."""
    d_lat = radius_km / KM_PER_DEG_LAT
    cos_lat = max(math.cos(math.radians(lat)), 1e-6)  # guard near poles
    d_lng = radius_km / (KM_PER_DEG_LAT * cos_lat)
    return (lat - d_lat, lat + d_lat, lng - d_lng, lng + d_lng)


def within_radius(rows, lat: float, lng: float, radius_km: float, lat_attr: str = "lat", lng_attr: str = "lng"):
    """Python-side haversine filter over rows already bounding-box-prefiltered in SQL."""
    limit_m = radius_km * 1000.0
    return [
        row
        for row in rows
        if getattr(row, lat_attr) is not None
        and getattr(row, lng_attr) is not None
        and haversine_m(lat, lng, getattr(row, lat_attr), getattr(row, lng_attr)) <= limit_m
    ]
