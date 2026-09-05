"""Kerala reservoir levels — static cached dataset (Phase 4 scope).

India-WRIS has no reliable bulk/live public API (master plan §7: explicitly
deferred as a fragile scrape). We therefore serve a realistic static dataset
of the 5 key reservoirs (`app/data/dams_kerala.json`, real FRL/MWC parameters
from CWC bulletins) stamped with the time it is served, clearly labelled so
the UI presents it as a cached/static source, not live telemetry.
"""

import json
import logging
from datetime import UTC, datetime
from pathlib import Path

from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.services.external_apis.cache import cached_fetch

log = logging.getLogger(__name__)

METRIC = "dams"
_DATA = Path(__file__).resolve().parents[2] / "data" / "dams_kerala.json"
_TIMEOUT = 10.0


def _load_static() -> list[dict]:
    with _DATA.open(encoding="utf-8") as fh:
        return json.load(fh)


def _shape(dams: list[dict]) -> dict:
    return {
        "dams": [
            {
                "name": d["name"],
                "district": d["district"],
                "river": d["river"],
                "lat": d["lat"],
                "lng": d["lng"],
                "storage_pct": d["storage_pct"],
                "danger_level_pct": d["danger_level_pct"],
                "frl_m": d["frl_m"],
                "live_capacity_mcm": d["live_capacity_mcm"],
            }
            for d in dams
        ],
        "count": len(dams),
        "source_label": "CWC Dams (static dataset)",
        "data_kind": "static",
    }


def _fallback() -> dict:
    payload = _shape(_load_static())
    payload["fetched_at"] = datetime.now(UTC).isoformat()
    return payload


async def _fetch() -> dict:
    # No live WRIS bulk endpoint exists. "Fetch" = load the curated static
    # dataset and stamp it; kept behind the same cached_fetch contract so the
    # rest of the system treats dams like every other metric.
    return _fallback()


async def get_dams(db: AsyncSession, ttl_minutes: int | None = None) -> dict:
    s = get_settings()
    return await cached_fetch(db, METRIC, _fetch, ttl_minutes or s.STATS_TTL_MINUTES, _fallback)
