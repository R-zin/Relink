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


settings = get_settings()

app = FastAPI(title="RELINK API", version="0.1.0", lifespan=lifespan)


@app.middleware("http")
async def add_security_headers(request, call_next):
    response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
    response.headers["Permissions-Policy"] = "geolocation=(self), camera=(), microphone=()"
    response.headers["Content-Security-Policy"] = "default-src 'self'; frame-ancestors 'none'"
    if request.url.scheme == "https" or request.headers.get("x-forwarded-proto") == "https":
        response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
    return response


# CORS configuration: restrict origins and enforce credentials policy
allow_all = "*" in settings.CORS_ORIGINS
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,
    allow_credentials=not allow_all,  # Never allow credentials with wildcard '*' origin
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS", "HEAD"],
    allow_headers=["Content-Type", "Authorization", "Accept", "Origin", "X-Requested-With"],
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
