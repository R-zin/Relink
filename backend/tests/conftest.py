"""Test harness: runs the app against a dedicated `relink_test` database.

- Session fixture: create relink_test (drop if exists), `alembic upgrade head`.
- Function fixture: truncate all tables for isolation.
- DATABASE_URL is overridden via env BEFORE any app module import, so
  app.db's engine binds to the test DB.
"""

import os
import subprocess
import sys
from pathlib import Path

import psycopg2
import pytest
from fastapi.testclient import TestClient

BACKEND_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BACKEND_DIR))

from dotenv import dotenv_values  # noqa: E402

_env = dotenv_values(BACKEND_DIR / ".env")
_dev_url = os.environ.get("DATABASE_URL") or _env.get("DATABASE_URL", "")
_test_url = os.environ.get("TEST_DATABASE_URL") or _env.get("TEST_DATABASE_URL")
if not _test_url:
    # Derive: same server/credentials, database relink_test.
    _test_url = _dev_url.rsplit("/", 1)[0] + "/relink_test"
os.environ["DATABASE_URL"] = _test_url  # must precede app imports

# TestClient runs each test on its own event loop; pooled asyncpg connections
# opened on a previous test's loop die with "Event loop is closed" when
# pool_pre_ping recycles them. NullPool: one connection per request, opened
# and closed on the current loop.
import app.db as app_db  # noqa: E402
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine  # noqa: E402
from sqlalchemy.pool import NullPool  # noqa: E402

app_db.engine = create_async_engine(_test_url, poolclass=NullPool)
app_db.SessionLocal = async_sessionmaker(app_db.engine, expire_on_commit=False)

from app.main import app  # noqa: E402

ALL_TABLES = (
    "sos_events",
    "reports",
    "missing_persons",
    "shelters",
    "devices",
    "stats_cache",
    "ai_review_cache",
)


def _sync_url(url: str) -> str:
    return url.replace("+asyncpg", "")


@pytest.fixture(scope="session", autouse=True)
def migrated_db():
    admin_url = _sync_url(_test_url).rsplit("/", 1)[0] + "/postgres"
    db_name = _test_url.rsplit("/", 1)[1].split("?")[0]
    conn = psycopg2.connect(admin_url)
    conn.autocommit = True
    with conn.cursor() as cur:
        cur.execute("SELECT 1 FROM pg_database WHERE datname = %s", (db_name,))
        if cur.fetchone():
            cur.execute(f'DROP DATABASE "{db_name}" WITH (FORCE)')
        cur.execute(f'CREATE DATABASE "{db_name}"')
    conn.close()

    env = {**os.environ, "DATABASE_URL": _test_url}
    subprocess.run(
        [sys.executable, "-m", "alembic", "upgrade", "head"],
        cwd=BACKEND_DIR,
        env=env,
        check=True,
        capture_output=True,
    )
    yield

    conn = psycopg2.connect(admin_url)
    conn.autocommit = True
    with conn.cursor() as cur:
        cur.execute(f'DROP DATABASE IF EXISTS "{db_name}" WITH (FORCE)')
    conn.close()


@pytest.fixture(autouse=True)
def truncate_tables(migrated_db):
    conn = psycopg2.connect(_sync_url(_test_url))
    conn.autocommit = True
    with conn.cursor() as cur:
        cur.execute("TRUNCATE " + ", ".join(ALL_TABLES) + " CASCADE")
    conn.close()
    yield


@pytest.fixture
def client():
    with TestClient(app) as c:
        yield c
