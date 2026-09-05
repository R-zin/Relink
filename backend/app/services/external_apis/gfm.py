"""Copernicus Global Flood Monitoring (GFM) flood-extent — fixture adapter.

Live Copernicus CDSE raster processing is out of Phase-4 scope; we pin to a
pre-baked GeoJSON observation (`app/data/fixtures/gfm.geojson`) carrying its
own observation timestamp. The UI must always display `observed_at` and must
never present this as a real-time feed (master plan §7 / phase_4.md §2).
"""

import json
from pathlib import Path

from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.services.external_apis.cache import cached_fetch

METRIC = "gfm"
_FIXTURE = Path(__file__).resolve().parents[2] / "data" / "fixtures" / "gfm.geojson"


def _fallback() -> dict:
    with _FIXTURE.open(encoding="utf-8") as fh:
        fc = json.load(fh)
    return {
        "observed_at": fc.get("metadata", {}).get("observed_at"),
        "geojson": fc,
        "polygon_count": len(fc.get("features", [])),
        "source_label": "Copernicus GFM (Sentinel-1 SAR)",
        "data_kind": "observation",
    }


async def _fetch() -> dict:
    # "Fetch" = load the pinned observation; kept behind cached_fetch so the
    # endpoint contract matches every other metric.
    return _fallback()


async def get_gfm(db: AsyncSession, ttl_minutes: int | None = None) -> dict:
    s = get_settings()
    return await cached_fetch(db, METRIC, _fetch, ttl_minutes or s.STATS_TTL_MINUTES, _fallback)
