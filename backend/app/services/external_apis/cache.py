"""`stats_cache`-backed fetch wrapper shared by every external adapter.

`cached_fetch(metric, fetch_fn, ttl_minutes, fallback_fn)`:
  1. If the newest cached row for `metric` is younger than `ttl_minutes`,
     return it as-is (`stale: false`).
  2. Otherwise call `fetch_fn()` (live). On success, INSERT a fresh row and
     return the payload.
  3. On any fetch/parse error: return the newest cached row with
     `stale: true` if one exists; else call `fallback_fn()` (local fixture)
     and return that payload with `fallback: true`. Never raises for
     external-network reasons.
"""

import logging
from collections.abc import Awaitable, Callable
from datetime import UTC, datetime
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import StatsCache

log = logging.getLogger(__name__)


async def _latest(db: AsyncSession, metric: str) -> StatsCache | None:
    stmt = (
        select(StatsCache)
        .where(StatsCache.metric == metric)
        .order_by(StatsCache.fetched_at.desc())
        .limit(1)
    )
    return (await db.execute(stmt)).scalar_one_or_none()


def _age_minutes(row: StatsCache) -> float:
    fetched = row.fetched_at
    if fetched.tzinfo is None:
        fetched = fetched.replace(tzinfo=UTC)
    return (datetime.now(UTC) - fetched).total_seconds() / 60.0


async def cached_fetch(
    db: AsyncSession,
    metric: str,
    fetch_fn: Callable[[], Awaitable[dict[str, Any]]],
    ttl_minutes: float,
    fallback_fn: Callable[[], dict[str, Any]] | None = None,
) -> dict[str, Any]:
    """See module docstring. `fetch_fn` returns the parsed metric payload
    (without cache bookkeeping keys); this wrapper adds stale/fallback flags
    and persists fresh values."""
    cached = await _latest(db, metric)

    if cached is not None and _age_minutes(cached) < ttl_minutes:
        payload = dict(cached.value_json or {})
        payload.setdefault("stale", False)
        return payload

    try:
        payload = await fetch_fn()
    except Exception as exc:  # noqa: BLE001 — degrade gracefully, never 500
        log.warning("external fetch failed for metric=%s: %s", metric, exc)
        if cached is not None:
            payload = dict(cached.value_json or {})
            payload["stale"] = True
            return payload
        if fallback_fn is not None:
            payload = fallback_fn()
            payload["fallback"] = True
            return payload
        raise  # no cache and no fixture — caller decides

    payload["stale"] = False
    row = StatsCache(metric=metric, value_json=payload)
    db.add(row)
    await db.commit()
    return payload
