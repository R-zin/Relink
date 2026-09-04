"""Seed the database with a coherent demo dataset (default region: Kochi, Kerala).

Usage: python -m scripts.seed   (from backend/, uses DATABASE_URL / .env)

Idempotent: rows whose description/name carries the [seed] tag are deleted
before re-inserting, so running it twice never duplicates data.
"""

import asyncio
import logging
import math
import random
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))  # allow `python -m scripts.seed`

from sqlalchemy import delete  # noqa: E402
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine  # noqa: E402

from app.config import get_settings  # noqa: E402
from app.models import MissingPerson, Report, Shelter, SosEvent  # noqa: E402

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
log = logging.getLogger("seed")

SEED_TAG = "[seed]"
random.seed(42)  # deterministic dataset for repeatable demos


def _jitter(center: float, spread: float) -> float:
    return center + random.uniform(-spread, spread)


def _scatter(center_lat: float, center_lng: float, radius_km: float) -> tuple[float, float]:
    # ~111.32 km per degree latitude; longitude scaled by cos(lat)
    d_lat = radius_km / 111.32
    d_lng = radius_km / (111.32 * math.cos(math.radians(center_lat)))
    return _jitter(center_lat, d_lat), _jitter(center_lng, d_lng)


def _recent(hours: float) -> datetime:
    return datetime.now(timezone.utc) - timedelta(hours=hours)


CLUSTER_SPECS = [
    # (type, center offset km, description pool)
    ("water", (0.8, 1.2), ["flooded road, knee-deep", "water entering homes", "street under water"]),
    ("obstacle", (-1.5, 0.6), ["fallen tree blocking road", "live wire down", "debris pile, road impassable"]),
    ("disease", (0.3, -1.8), ["fever cases reported in camp", "diarrhea cluster, 4 families", "skin infections spreading"]),
]

SCATTER_DESCRIPTIONS = {
    "water": ["waterlogging near bus stand", "canal overflowing", "paddy field submerged", "low-lying lane flooded"],
    "obstacle": ["tree branch on power line", "wall collapse, partial block", "landslip debris on shoulder"],
    "disease": ["two fever cases in lane", "child with rash, clinic closed", "stagnant water, mosquito breeding"],
}

SHELTER_NAMES = [
    "Govt. HSS Relief Camp — Edappally",
    "St. Teresa's College Shelter — Marine Drive",
    "Kalamassery Municipal Town Hall Camp",
    "Rajagiri School Relief Centre — Kakkanad",
    "Fort Kochi Community Hall Shelter",
    "Vyttila Mobility Hub Relief Camp",
]

MISSING_PERSONS = [
    ("Anil Kumar", 62, "last seen near Edappally bus stand wearing blue shirt"),
    ("Meena Pillai", 48, "diabetic, needs insulin; last seen at Vyttila junction"),
    ("Fathima Beevi", 71, "hard of hearing; last seen near Fort Kochi beach"),
    ("Rohan Mathew", 9, "school uniform; separated from family at Kaloor stadium"),
]

PLAINTEXT_MEDICAL_SAMPLES = [
    {
        "name": "Suresh Nair",
        "blood_group": "B+",
        "allergies": ["penicillin"],
        "emergency_contact": {"name": "Latha Nair", "phone": "+91-9846000001"},
    },
    {
        "name": "Amina Yusuf",
        "blood_group": "O-",
        "allergies": [],
        "emergency_contact": {"name": "Yusuf Ali", "phone": "+91-9846000002"},
    },
]


async def seed() -> None:
    settings = get_settings()
    center_lat, center_lng = settings.SEED_CENTER_LAT, settings.SEED_CENTER_LNG
    engine = create_async_engine(settings.DATABASE_URL)
    session_factory = async_sessionmaker(engine, expire_on_commit=False)

    async with session_factory() as session:
        # Idempotency: wipe previously-seeded rows only.
        for model, col in (
            (Report, Report.description),
            (Shelter, Shelter.name),
            (MissingPerson, MissingPerson.description),
        ):
            await session.execute(delete(model).where(col.like(f"{SEED_TAG}%")))
        await session.execute(delete(SosEvent).where(SosEvent.encrypted_medical.is_(None)))
        await session.commit()

        now = datetime.now(timezone.utc)
        reports: list[Report] = []

        # 3 tight clusters (8-10 reports within ~300 m of each cluster center)
        for rtype, (off_lat_km, off_lng_km), descriptions in CLUSTER_SPECS:
            c_lat = center_lat + off_lat_km / 111.32
            c_lng = center_lng + off_lng_km / (111.32 * math.cos(math.radians(center_lat)))
            for i in range(random.randint(8, 10)):
                lat = c_lat + random.uniform(-0.0015, 0.0015)   # ~170 m
                lng = c_lng + random.uniform(-0.0015, 0.0015)
                confirms = random.randint(0, 15)
                reports.append(
                    Report(
                        type=rtype,
                        lat=lat,
                        lng=lng,
                        description=f"{SEED_TAG} {random.choice(descriptions)}",
                        confirm_count=confirms,
                        last_confirmed_at=(_recent(random.uniform(1, 48)) if confirms else None),
                        created_at=now - timedelta(days=random.uniform(0, 5)),
                    )
                )

        # Scattered reports within 15 km
        cluster_count = len(reports)
        for _ in range(40 - cluster_count):
            rtype = random.choice(list(SCATTER_DESCRIPTIONS))
            lat, lng = _scatter(center_lat, center_lng, 15)
            confirms = random.randint(0, 15)
            reports.append(
                Report(
                    type=rtype,
                    lat=lat,
                    lng=lng,
                    description=f"{SEED_TAG} {random.choice(SCATTER_DESCRIPTIONS[rtype])}",
                    confirm_count=confirms,
                    last_confirmed_at=(_recent(random.uniform(1, 48)) if confirms else None),
                    created_at=now - timedelta(days=random.uniform(0, 5)),
                )
            )
        session.add_all(reports)

        # 6 shelters
        shelters = []
        for name in SHELTER_NAMES:
            lat, lng = _scatter(center_lat, center_lng, 8)
            confirms = random.randint(0, 30)
            shelters.append(
                Shelter(
                    name=f"{SEED_TAG} {name}",
                    lat=lat,
                    lng=lng,
                    contact_info="camp coordinator: +91-9846XXXXXX",
                    confirm_count=confirms,
                    last_confirmed_at=(_recent(random.uniform(1, 24)) if confirms else None),
                )
            )
        session.add_all(shelters)

        # 4 missing persons
        persons = []
        for name, age, note in MISSING_PERSONS:
            lat, lng = _scatter(center_lat, center_lng, 10)
            persons.append(
                MissingPerson(
                    name=name,
                    last_seen_lat=lat,
                    last_seen_lng=lng,
                    description=f"{SEED_TAG} age {age}; {note}",
                )
            )
        session.add_all(persons)

        # 2 active SOS events with sample plaintext medical cards
        for medical in PLAINTEXT_MEDICAL_SAMPLES:
            lat, lng = _scatter(center_lat, center_lng, 5)
            session.add(
                SosEvent(
                    lat=lat,
                    lng=lng,
                    plaintext_medical=medical,
                    encrypted_medical=None,  # Phase 3 owns ciphertext
                    status="active",
                )
            )

        await session.commit()
        log.info(
            "seed complete around (%.3f, %.3f): %d reports (3 clusters + scattered), "
            "%d shelters, %d missing persons, 2 SOS events",
            center_lat, center_lng, len(reports), len(shelters), len(persons),
        )

    await engine.dispose()


if __name__ == "__main__":
    asyncio.run(seed())
