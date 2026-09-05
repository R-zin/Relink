"""NDMA Sachet CAP/RSS ingestion (Phase 4).

Polls the Sachet RSS feed for the configured state, follows each item's link
to the full CAP XML, extracts severity/districts/instructions, and upserts
into `alerts_cache` (idempotent on the CAP identifier). A demo "test alert"
path synthesises a Red flood warning for judge presentations.
"""

import asyncio
import logging
from datetime import UTC, datetime
from email.utils import parsedate_to_datetime

import httpx
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession
from xml.etree import ElementTree as ET

from app.config import get_settings
from app.models import AlertCache

log = logging.getLogger(__name__)

_TIMEOUT = 10.0
_CAP = "{urn:oasis:names:tc:emergency:cap:1.2}"
_MAX_ITEMS = 15


def _parse_dt(raw: str | None) -> datetime | None:
    if not raw:
        return None
    raw = raw.strip()
    if not raw:
        return None
    try:
        dt = datetime.fromisoformat(raw)
        return dt if dt.tzinfo else dt.replace(tzinfo=UTC)
    except ValueError:
        pass
    try:
        dt = parsedate_to_datetime(raw)
        return dt if dt.tzinfo else dt.replace(tzinfo=UTC)
    except (TypeError, ValueError):
        return None


def _text(el: ET.Element | None, tag: str) -> str | None:
    if el is None:
        return None
    child = el.find(f"{_CAP}{tag}")
    if child is None or child.text is None:
        return None
    return child.text.strip() or None


def parse_cap_xml(xml_text: str, *, state: str) -> dict | None:
    """Parse a CAP 1.2 alert into an alerts_cache row dict. English info block
    preferred; falls back to the first info block."""
    try:
        root = ET.fromstring(xml_text)
    except ET.ParseError:
        log.warning("unparseable CAP XML")
        return None
    if not root.tag.endswith("alert"):
        return None

    identifier = _text(root, "identifier")
    if not identifier:
        return None

    infos = root.findall(f"{_CAP}info")
    info = next((i for i in infos if (_text(i, "language") or "").startswith("en")), None)
    if info is None and infos:
        info = infos[0]

    area = info.find(f"{_CAP}area") if info is not None else None
    return {
        "cap_identifier": identifier,
        "source": "sachet",
        "state": state,
        "event": _text(info, "event"),
        "headline": _text(info, "headline"),
        "description": _text(info, "description"),
        "instruction": _text(info, "instruction"),
        "severity": _text(info, "severity"),
        "urgency": _text(info, "urgency"),
        "certainty": _text(info, "certainty"),
        "area_desc": _text(area, "areaDesc"),
        "sender": _text(root, "sender"),
        "effective": _parse_dt(_text(info, "effective")),
        "onset": _parse_dt(_text(info, "onset")),
        "expires": _parse_dt(_text(info, "expires")),
        "issued_at": _parse_dt(_text(root, "sent")),
        "is_test": 0,
    }


def parse_rss_items(rss_text: str) -> list[dict]:
    """Extract {guid, link, title, pubDate} for each RSS item."""
    try:
        root = ET.fromstring(rss_text)
    except ET.ParseError:
        log.warning("unparseable Sachet RSS")
        return []
    items = []
    for item in root.iter("item"):
        guid = item.findtext("guid")
        link = item.findtext("link")
        if not guid or not link:
            continue
        items.append({
            "guid": guid.strip(),
            "link": link.strip(),
            "title": (item.findtext("title") or "").strip(),
            "pubDate": _parse_dt(item.findtext("pubDate")),
        })
    return items[:_MAX_ITEMS]


async def _upsert(db: AsyncSession, row: dict) -> None:
    stmt = (
        pg_insert(AlertCache)
        .values(**row)
        .on_conflict_do_update(
            index_elements=["cap_identifier"],
            set_={k: v for k, v in row.items() if k != "cap_identifier"},
        )
    )
    await db.execute(stmt)


async def poll_sachet(db: AsyncSession) -> int:
    """One poll cycle. Returns the number of alerts upserted."""
    s = get_settings()
    if not s.SACHET_RSS_URL:
        log.warning("SACHET_RSS_URL not configured; skipping poll")
        return 0
    state = s.ALERTS_STATE

    async with httpx.AsyncClient(timeout=_TIMEOUT, follow_redirects=True, verify=False) as client:
        rss = await client.get(s.SACHET_RSS_URL)
        rss.raise_for_status()
        items = parse_rss_items(rss.text)

        async def _fetch_and_parse(item: dict) -> dict | None:
            try:
                cap = await client.get(item["link"])
                cap.raise_for_status()
                return parse_cap_xml(cap.text, state=state)
            except Exception as exc:  # noqa: BLE001 — one bad item must not kill the poll
                log.warning("failed to fetch/parse CAP %s: %s", item.get("guid"), exc)
                return None

        parsed_rows = await asyncio.gather(*[_fetch_and_parse(it) for it in items])
        count = 0
        for row in parsed_rows:
            if row is not None:
                await _upsert(db, row)
                count += 1

    await db.commit()
    log.info("sachet poll: %d alerts upserted (state=%s)", count, state)
    return count


def build_test_alert(*, state: str) -> dict:
    """Synthesised Red flood warning for demo presentations."""
    now = datetime.now(UTC)
    return {
        "cap_identifier": f"RELINK-TEST-{int(now.timestamp())}",
        "source": "sachet",
        "state": state,
        "event": "Flash Flood",
        "headline": (
            "Severe Flooding Alert: Aluva & Paravur taluks. Periyar river "
            "level rising rapidly after Idamalayar spillway release. Move to "
            "higher ground immediately."
        ),
        "description": (
            "Heavy rainfall combined with dam discharge has caused rapid "
            "inundation of low-lying areas along the Periyar. Avoid travel "
            "through Aluva, Paravur and Kalamassery until further notice."
        ),
        "instruction": "Move to the nearest relief camp. Follow KSDMA guidelines. Do not cross flooded roads.",
        "severity": "Red",
        "urgency": "Immediate",
        "certainty": "Observed",
        "area_desc": "Aluva, Paravur and Kalamassery taluks, Ernakulam",
        "sender": "RELINK demo trigger",
        "effective": now,
        "onset": now,
        "expires": None,
        "issued_at": now,
        "is_test": 1,
    }


async def create_test_alert(db: AsyncSession) -> AlertCache:
    s = get_settings()
    target_state = "kerala" if s.ALERTS_STATE.lower() == "all" else s.ALERTS_STATE
    row = build_test_alert(state=target_state)
    alert = AlertCache(**row)
    db.add(alert)
    await db.commit()
    await db.refresh(alert)
    return alert
