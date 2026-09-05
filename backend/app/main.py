"""RELINK backend — FastAPI entrypoint.

DDL is owned by alembic migrations; nothing here creates tables at startup.
"""

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import get_settings
from app.jobs import scheduler as jobs
from app.routers import (
    alerts,
    health,
    medical,
    missing_persons,
    ml_risk,
    reports,
    shelters,
    sos,
    stats,
)

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("relink")


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings = get_settings()
    log.info("RELINK backend starting — db host: %s", settings.masked_db_host())
    jobs.start_scheduler()
    yield
    jobs.shutdown_scheduler()


app = FastAPI(title="RELINK API", version="0.1.0", lifespan=lifespan)

# Hackathon scope: phone + dashboard hit the API from unknown origins.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

for r in (
    health.router,
    sos.router,
    reports.router,
    missing_persons.router,
    shelters.router,
    medical.router,
    stats.router,
    alerts.router,
    ml_risk.router,
):
    app.include_router(r)
