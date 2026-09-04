# Phase 1 — Foundation

> Read the master plan (`CLAUDE.md`) first — Sections 1–7 are your ground truth, especially Section 7 (Data Contract). This file is your **only** scope. Do not read or touch other phase files.

## Scope

Backend skeleton, Postgres schema (master plan Section 7), core CRUD endpoints, and the client-side `sqflite` outbox scaffold (schema only, no UI yet).

### Build

**Backend (`backend/`, FastAPI):**
- Project skeleton: `main.py`, `routers/`, `services/`, `jobs/` directories per the repo structure in master plan Section 7.
- Postgres schema (Supabase or local Postgres) implementing **all** data models from Section 7: `devices`, `sos_events`, `reports`, `missing_persons`, `shelters`, `stats_cache`, `ai_review_cache` — create all tables now even though later phases populate some of them, so no phase has to migrate the schema later.
- Endpoints (implement exactly these, from Section 7):
  ```
  POST   /sos                     — ingest SOS (direct or mesh-relayed)
  POST   /reports                 — create obstacle/disease/water report
  POST   /reports/{id}/confirm    — crowdsourced confirm/upvote
  GET    /reports/clusters        — DBSCAN-clustered report groups (scikit-learn DBSCAN; stub with trivial params is fine, real tuning comes later)
  POST   /missing-persons         — submit missing-person report
  GET    /missing-persons/search  — search/match by name+location
  POST   /shelters                — add shelter (crowdsourced)
  POST   /shelters/{id}/confirm   — bump trust/last-verified signal
  GET    /shelters                — list nearby shelters
  ```
- Confirm endpoints increment `confirm_count` and set `last_confirmed_at`.
- Accept and store the mesh message envelope fields (`id`, `type`, `origin_device_id`, `timestamp`, `payload`, `encrypted_payload`) so Phase 3 mesh-relayed messages ingest unchanged. De-duplicate by message `id` (a relayed message may arrive multiple times).

**Mobile outbox scaffold (`mobile/lib/storage/`, Flutter):**
- `sqflite` outbox table for unsent messages: message id, type, payload JSON, encrypted_payload, priority, created_at, delivery status.
- Minimal store/retrieve/mark-delivered API (Dart class, no UI). SOS rows must be returned ahead of other types in the pending-send query (priority ordering per Section 7 flooding rules).
- A persisted `seen_ids` table (id + received_at) for the flooding dedup logic in Phase 3 — schema only.

## Do not touch

Mesh / Nearby Connections, crypto, external APIs, alerts, stats/AI review, dashboard, UI screens.

## Definition of done

- Every endpoint listed above responds correctly against a local Postgres instance (verified with real HTTP calls, not just imports).
- Outbox table exists and can store/retrieve/mark-delivered queued messages, with SOS priority ordering.

## Before you finish

Update the Phase 1 entry in the master plan Status Log (`CLAUDE.md` Section 9): what you built, deviations and why, what's broken/incomplete.
