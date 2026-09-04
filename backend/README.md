# RELINK Backend

FastAPI + Postgres (Supabase-compatible) backend for the RELINK disaster-resilience platform.

## Setup

```bash
cd backend
python -m venv .venv
.venv\Scripts\activate          # Windows PowerShell/CMD
pip install -r requirements.txt
copy .env.example .env          # then set DATABASE_URL
```

## Database

```bash
# create the database once (or use Supabase)
createdb relink                 # or: psql -c "CREATE DATABASE relink"

# apply migrations (alembic owns all DDL — never Base.metadata.create_all)
alembic upgrade head
```

## Run

```bash
uvicorn app.main:app --reload
# health check
curl http://127.0.0.1:8000/health
```

## Seed demo data (Kochi, Kerala by default)

```bash
python -m scripts.seed          # idempotent — safe to re-run
```

## Tests

```bash
pytest                          # uses the relink_test database, created/dropped automatically
```

## Endpoints (Phase 1)

| Method | Path | Purpose |
|---|---|---|
| GET | `/health` | liveness |
| POST | `/sos` | ingest SOS (direct or mesh-relayed) |
| GET | `/sos` | list SOS events (`?status=&limit=`) |
| POST | `/reports` | create obstacle/disease/water report |
| POST | `/reports/{id}/confirm` | crowdsourced upvote |
| GET | `/reports` | list (`?type=&lat=&lng=&radius_km=&limit=`) |
| GET | `/reports/clusters` | DBSCAN-clustered groups (`?type=&eps_m=&min_samples=`) |
| POST | `/missing-persons` | submit missing-person report |
| GET | `/missing-persons/search` | search (`?name=&lat=&lng=&radius_km=`) |
| POST | `/shelters` | add shelter |
| POST | `/shelters/{id}/confirm` | bump trust signal |
| GET | `/shelters` | list by trust (`?lat=&lng=&radius_km=`) |
