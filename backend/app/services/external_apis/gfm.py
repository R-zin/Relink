"""Copernicus Global Flood Monitoring (GFM) — live WMS flood-extent adapter.

Switches GFM off the pre-baked GeoJSON fixture and onto the live EODC GFM
GeoServer WMS (`geoserver.gfm.eodc.eu`). The flood-extent layer is rendered by
the *clients* as WMS PNG tiles overlaid on the OpenStreetMap basemap — the
backend does NOT proxy tiles or download GeoJSON/COGs.

What this adapter returns is a small *descriptor* telling each client how to
build the overlay (which WMS endpoint + layer + region bbox). The GeoServer has
no `time` dimension — it always serves the current observed-flood composite —
so `observed_at` is the moment the descriptor was (re)generated, i.e. the age
of our view of the feed, not a pinned fixture timestamp.

Contract (unchanged from the fixture era): the UI must keep labelling this as a
satellite-observation layer ("latest satellite pass, not live").
"""

from datetime import UTC, datetime

from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.services.external_apis.cache import cached_fetch

METRIC = "gfm"

# Half-width (degrees) of the demo bbox around the seed centre — used only to
# hint clients at the region of interest; the WMS layer itself is global.
_BBOX_DELTA = 0.4


def _region_bbox() -> list[float]:
    s = get_settings()
    return [
        round(s.SEED_CENTER_LNG - _BBOX_DELTA, 4),  # west (min lng)
        round(s.SEED_CENTER_LAT - _BBOX_DELTA, 4),  # south (min lat)
        round(s.SEED_CENTER_LNG + _BBOX_DELTA, 4),  # east (max lng)
        round(s.SEED_CENTER_LAT + _BBOX_DELTA, 4),  # north (max lat)
    ]


def _descriptor() -> dict:
    """Static WMS connection info — no network needed to describe the layer."""
    s = get_settings()
    return {
        "mode": "wms",
        "wms_url": s.GFM_WMS_URL,
        "layer": s.GFM_WMS_LAYER,
        "crs": "EPSG:3857",
        "region_bbox": _region_bbox(),
        "source_label": "Copernicus GFM (Sentinel-1 SAR, live WMS)",
        "data_kind": "observation",
    }


async def _fetch() -> dict:
    """Return the live descriptor, stamped with the current time.

    The flood tiles themselves are fetched client-side straight from the
    GeoServer, so there is nothing to download here — we only record when we
    last (re)issued the descriptor so the UI can show how fresh its view is.
    """
    out = _descriptor()
    out["observed_at"] = datetime.now(UTC).isoformat()
    return out


def _fallback() -> dict:
    # Even fully offline we can still tell clients where the layer lives; the
    # tiles simply won't load until connectivity returns.
    out = _descriptor()
    out["observed_at"] = None
    return out


async def get_gfm(db: AsyncSession, ttl_minutes: int | None = None) -> dict:
    s = get_settings()
    return await cached_fetch(db, METRIC, _fetch, ttl_minutes or s.STATS_TTL_MINUTES, _fallback)
