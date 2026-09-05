"""AI operational risk review (Phase 4).

Feeds the consolidated /stats metrics to an LLM (master plan §7 prompt),
parses the `RISK TAG: <Tag>` line, and caches the result in `ai_review_cache`
for `AI_REVIEW_TTL_MINUTES`. If the LLM is unreachable or no key is
configured, a deterministic threshold rule produces an instant operational
summary instead — the endpoint must never fail because the LLM is down.
"""

import json
import logging
import re
from datetime import UTC, datetime

import httpx
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.models import AiReviewCache

log = logging.getLogger(__name__)

RISK_TAGS = ("Low", "Moderate", "High", "Severe")
_TAG_RE = re.compile(r"RISK\s*TAG\s*:\s*(Low|Moderate|High|Severe)", re.IGNORECASE)
_TIMEOUT = 25.0

_SYSTEM = (
    "You are a disaster-risk analyst. Given these live hazard metrics for {region}, "
    "produce a 3-4 sentence plain-language summary and a single risk tag "
    "(Low/Moderate/High/Severe). Be concrete, cite the specific numbers driving your "
    "assessment (discharge rate, rainfall mm, dam percentage), no hedging filler. "
    "Conclude with RISK TAG: <Tag>."
)


def parse_risk_tag(text: str) -> str | None:
    m = _TAG_RE.search(text)
    return m.group(1).capitalize() if m else None


async def _latest_review(db: AsyncSession, region: str) -> AiReviewCache | None:
    stmt = (
        select(AiReviewCache)
        .where(AiReviewCache.region == region)
        .order_by(AiReviewCache.generated_at.desc())
        .limit(1)
    )
    return (await db.execute(stmt)).scalar_one_or_none()


def _age_minutes(row: AiReviewCache) -> float:
    gen = row.generated_at
    if gen.tzinfo is None:
        gen = gen.replace(tzinfo=UTC)
    return (datetime.now(UTC) - gen).total_seconds() / 60.0


def _rule_based(metrics: dict) -> tuple[str, str]:
    """Deterministic fallback: thresholds -> (summary, risk_tag)."""
    glofas = metrics.get("glofas") or {}
    weather = metrics.get("weather") or {}
    dams = (metrics.get("dams") or {}).get("dams") or []

    rain = weather.get("rainfall_24h_mm") or 0.0
    discharge = glofas.get("discharge_m3s") or 0.0
    mean = glofas.get("mean_m3s") or discharge or 1.0
    max_dam = max((d.get("storage_pct") or 0.0 for d in dams), default=0.0)
    fullest = max(dams, key=lambda d: d.get("storage_pct") or 0.0, default=None)

    severe = rain > 150 or max_dam > 90 or discharge > mean * 2
    high = rain > 100 or max_dam > 85 or discharge > mean * 1.5
    moderate = rain > 50 or max_dam > 75 or discharge > mean * 1.2

    if severe:
        tag = "Severe"
    elif high:
        tag = "High"
    elif moderate:
        tag = "Moderate"
    else:
        tag = "Low"

    dam_txt = f"{fullest['name']} reservoir is at {fullest['storage_pct']}% storage" if fullest else "reservoir data unavailable"
    summary = (
        f"Periyar discharge is {discharge:.0f} m³/s ({glofas.get('trend', 'steady')} against a "
        f"{mean:.0f} m³/s mean) and {rain:.0f} mm of rain fell in the last 24 hours. "
        f"{dam_txt}. Operational posture is assessed as {tag} based on current river, "
        f"rainfall and storage thresholds. RISK TAG: {tag}"
    )
    return summary, tag


async def _call_llm(metrics: dict, region: str) -> tuple[str, str]:
    """Returns (summary_text, risk_tag). Raises on transport/API failure."""
    s = get_settings()
    if not s.LLM_API_KEY:
        raise RuntimeError("LLM_API_KEY not configured")

    payload = {
        "model": s.LLM_MODEL,
        "max_tokens": 350,
        "system": _SYSTEM.format(region=region),
        "messages": [
            {
                "role": "user",
                "content": (
                    "Live hazard metrics JSON:\n"
                    + json.dumps(metrics, indent=2, default=str)
                    + "\n\nProduce the assessment now."
                ),
            }
        ],
    }
    headers = {
        "x-api-key": s.LLM_API_KEY,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
    }
    async with httpx.AsyncClient(timeout=_TIMEOUT) as client:
        resp = await client.post(s.LLM_API_URL, json=payload, headers=headers)
        resp.raise_for_status()
        body = resp.json()

    text = "".join(block.get("text", "") for block in body.get("content", []) if block.get("type") == "text")
    if not text.strip():
        raise RuntimeError("LLM returned empty content")
    tag = parse_risk_tag(text) or "Moderate"
    return text.strip(), tag


async def get_ai_review(db: AsyncSession, region: str) -> dict:
    """Cached AI review for `region`; regenerates when stale. Falls back to
    the deterministic rule (and finally to the last cached row) on LLM failure."""
    s = get_settings()
    cached = await _latest_review(db, region)
    if cached is not None and _age_minutes(cached) < s.AI_REVIEW_TTL_MINUTES:
        return _shape(cached, source="llm" if not _is_rule(cached) else "rule", stale=False)

    # Import here to avoid a circular import at module load (stats -> ai_review).
    from app.services.stats_service import get_stats_metrics

    # get_stats_metrics returns {region, fetched_at, metrics: {...}}; both the
    # LLM prompt and the rule fallback consume the inner metrics dict.
    metrics = (await get_stats_metrics(region=region))["metrics"]

    try:
        summary, tag = await _call_llm(metrics, region)
        source = "llm"
    except Exception as exc:  # noqa: BLE001 — degrade gracefully
        log.warning("LLM review failed (%s); using deterministic rule", exc)
        summary, tag = _rule_based(metrics)
        source = "rule"

    row = AiReviewCache(region=region, summary_text=summary, risk_tag=tag)
    db.add(row)
    await db.commit()
    await db.refresh(row)
    return _shape(row, source=source, stale=False)


def _is_rule(row: AiReviewCache) -> bool:
    return bool(row.summary_text and "operational posture is assessed" in row.summary_text.lower())


def _shape(row: AiReviewCache, *, source: str, stale: bool) -> dict:
    gen = row.generated_at
    if gen.tzinfo is None:
        gen = gen.replace(tzinfo=UTC)
    return {
        "region": row.region,
        "summary_text": row.summary_text,
        "risk_tag": row.risk_tag,
        "generated_at": gen.isoformat(),
        "source": source,
        "stale": stale,
    }
