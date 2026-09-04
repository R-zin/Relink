# PHASE 1 — Foundation

> Backend skeleton + Postgres schema + core CRUD + DBSCAN clustering + Flutter project scaffold + sqflite outbox.
>
> **You are the Phase 1 agent.** Read the master plan (`CLAUDE.md`, auto-loaded) first — it is Core Context: locked decisions, data contracts, repo structure, status log rules. This file is your *only* implementation scope. Do **not** read `plans/phase_2.md` … `phase_4.md`, and do not build anything outside the scope below — later phases depend on this foundation exactly as specified here.
>
> **If you hit an ambiguity, a blocker, or a decision not covered here or in the master plan — STOP and ask the user, then continue with their answer.** Do not guess on contract-level details.

---

## 0. Scope & Definition of Done

**Build:** FastAPI backend (all core CRUD routers + clustering service + DB wiring), the full Postgres schema, seed script, and a Flutter project scaffold containing *only* the sqflite outbox layer (no screens, no networking UI).

**Explicitly out of scope (later phases):** any Flutter screen/UI beyond a throwaway `main.dart`, BLE/Nearby Connections, medical-card crypto, external hazard APIs, AI review, Sachet RSS, FCM push, `/alerts` `/stats` `/stats/ai-review` endpoints, React dashboard, auth/RBAC.

**Done when:**
1. `uvicorn app.main:app` starts clean; `GET /health` returns 200.
2. Every endpoint in §4 responds correctly against a live Postgres (local or Supabase), verified by `pytest` + `httpx` against a running test instance.
3. `GET /reports/clusters` returns DBSCAN-clustered groups for seeded data (one near-duplicate pair collapses into a single cluster).
4. Flutter app compiles (`flutter analyze` clean, `flutter test` passes) and the outbox round-trips: enqueue SOS + REPORT → priority-ordered read (SOS first) → mark sent → empty pending list.
5. Master plan Section 9 (Status Log) updated per §10.

---

## 1. Setup

```bash
cd backend
python -m venv .venv && .venv/Scripts/activate        # Windows; adjust on *nix
pip install fastapi "uvicorn[standard]" sqlalchemy alembic asyncpg psycopg2-binary \
            pydantic pydantic-settings scikit-learn numpy python-dotenv \
            pytest httpx apscheduler
pip freeze > requirements.txt
```

- **Python:** 3.11+.
- **Flutter:** latest stable; `flutter create --org in.relink --project-name relink_mobile .` inside `mobile/` (empty dir). Add deps in §5.
- **Postgres:** Supabase free tier if the user provides `SUPABASE_URL`/`SUPABASE_KEY`; otherwise local Postgres 15+. If neither is configured, **ask the user** which to target before writing DB code. Migrations must work on both (plain SQL, no Supabase-only extensions).
- Copy `backend/.env.example` → `backend/.env` and fill `DATABASE_URL`. Never commit `.env`.

## 2. Files You Own (do not create files outside this list)

```
backend/
├── requirements.txt
├── .env.example
├── pytest.ini
├── alembic.ini
├── alembic/env.py, alembic/versions/0001_initial_schema.py
├── scripts/seed.py
├── tests/{conftest.py, test_sos.py, test_reports.py, test_missing_persons.py,
│         test_shelters.py, test_clustering.py}
└── app/
    ├── main.py
    ├── config.py
    ├── db.py
    ├── models.py
    ├── schemas.py
    ├── services/{__init__.py, clustering.py}
    └── routers/{__init__.py, health.py, sos.py, reports.py, missing_persons.py, shelters.py}
mobile/
├── (standard `flutter create` output)
├── pubspec.yaml
└── lib/
    ├── main.dart                      # throwaway placeholder only
    ├── storage/{database.dart, outbox_dao.dart}
    └── models/mesh_message.dart
mobile/test/outbox_test.dart
```

`mobile/lib/mesh/`, `crypto/`, `screens/` are created in later phases — do **not** pre-create them (Phase 2/3 own them).

## 3. Database Schema

Author `alembic/versions/0001_initial_schema.py` by hand (write the `upgrade()`/`downgrade()` explicitly — do not rely on autogenerate). Types are Postgres; `uuid` PKs default `gen_random_uuid()` (requires `CREATE EXTENSION IF NOT EXISTS pgcrypto;` — include it in the migration).

```sql
CREATE EXTENSION IF NOT EXISTS pgcrypto;

devices (
  id            uuid PK DEFAULT gen_random_uuid(),
  public_key    text,                      -- reserved for v2; nullable, unused now
  last_seen     timestamptz NOT NULL DEFAULT now(),
  platform      text                       -- 'android' | 'ios' | etc.
);

sos_events (
  id                 uuid PK DEFAULT gen_random_uuid(),
  device_id          uuid REFERENCES devices(id),
  lat                double precision NOT NULL,
  lng                double precision NOT NULL,
  plaintext_medical  jsonb,                -- {name, blood_group, allergies[], emergency_contact{name,phone}}
  encrypted_medical  text,                 -- base64 AES-GCM ciphertext (Phase 3 fills it; store opaque)
  status             text NOT NULL DEFAULT 'active',   -- 'active' | 'responding' | 'resolved'
  created_at         timestamptz NOT NULL DEFAULT now()
);

reports (
  id                 uuid PK DEFAULT gen_random_uuid(),
  type               text NOT NULL,        -- 'obstacle' | 'disease' | 'water'
  lat                double precision NOT NULL,
  lng                double precision NOT NULL,
  description        text,
  device_id          uuid REFERENCES devices(id),
  confirm_count      integer NOT NULL DEFAULT 0,
  last_confirmed_at  timestamptz,
  created_at         timestamptz NOT NULL DEFAULT now()
);

missing_persons (
  id                  uuid PK DEFAULT gen_random_uuid(),
  name                text NOT NULL,
  last_seen_lat       double precision,
  last_seen_lng       double precision,
  description         text,
  reporter_device_id  uuid REFERENCES devices(id),
  status              text NOT NULL DEFAULT 'missing',   -- 'missing' | 'found'
  created_at          timestamptz NOT NULL DEFAULT now()
);

shelters (
  id                 uuid PK DEFAULT gen_random_uuid(),
  name               text NOT NULL,
  lat                double precision NOT NULL,
  lng                double precision NOT NULL,
  contact_info       text,
  confirm_count      integer NOT NULL DEFAULT 0,
  last_confirmed_at  timestamptz,
  added_by           uuid REFERENCES devices(id)
);

stats_cache (
  id          uuid PK DEFAULT gen_random_uuid(),
  metric      text NOT NULL,
  value_json  jsonb,
  fetched_at  timestamptz NOT NULL DEFAULT now()
);

ai_review_cache (
  id            uuid PK DEFAULT gen_random_uuid(),
  region        text NOT NULL,
  summary_text  text,
  risk_tag      text,                      -- 'Low' | 'Moderate' | 'High' | 'Severe'
  generated_at  timestamptz NOT NULL DEFAULT now()
);
```

Indexes (include in the same migration): `reports(lat, lng)`, `shelters(lat, lng)`, `sos_events(status)`, `reports(type)`, `missing_persons(lower(name))` (expression index), `stats_cache(metric, fetched_at DESC)`.

Mirror these tables as SQLAlchemy models in `app/models.py` (used by routers; alembic migration remains the source of truth for DDL).

## 4. Endpoints to Implement

Request/response models go in `app/schemas.py` (Pydantic v2). All endpoints return `CamelCase`-free plain JSON (snake_case). All writes upsert-or-create the submitting device row (see `devices` note below). Standard errors: `422` on validation failure (FastAPI default), `404` unknown id, `409` duplicate confirm.

| Method & path | Request body → Response | Notes |
|---|---|---|
| `GET /health` | → `{"status": "ok"}` | No DB touch needed beyond a trivial `SELECT 1`. |
| `POST /sos` | `{device_id?, lat, lng, plaintext_medical?, encrypted_medical?}` → `201 {id, status: "active", created_at}` | `device_id` is a client-generated UUID string; see device upsert note. `encrypted_medical` stored opaquely — never inspected server-side. |
| `GET /sos` | query: `status?=active`, `limit?=100` → `[sos_event…]` newest first | Needed by the dashboard later; harmless to expose now. |
| `POST /reports` | `{type, lat, lng, description?, device_id?}` → `201 report` | `type` must be one of `obstacle|disease|water`; 422 otherwise. |
| `POST /reports/{id}/confirm` | empty body → `200 {id, confirm_count, last_confirmed_at}` | Increment + set `last_confirmed_at=now()` in one `UPDATE … RETURNING`. |
| `GET /reports` | query: `type?`, `lat?`, `lng?`, `radius_km?=25`, `limit?=200` → `[report…]` | Bounding-box prefilter + haversine filter when lat/lng given; otherwise newest first. |
| `GET /reports/clusters` | query: `type?`, `eps_m?=500`, `min_samples?=2` → `{clusters: [{cluster_id, centroid_lat, centroid_lng, report_count, total_confirmations, last_confirmed_at, sample_description, report_ids: […]}], noise: [report_id…]}` | See §6. |
| `POST /missing-persons` | `{name, last_seen_lat?, last_seen_lng?, description?, reporter_device_id?}` → `201 record` | Name stored as given; search normalizes case. |
| `GET /missing-persons/search` | query: `name?`, `lat?`, `lng?`, `radius_km?=50` → `[record…]` | Case-insensitive substring match on name (`ILIKE`), ANDed with radius filter when coords given. Empty query → newest 50. |
| `POST /shelters` | `{name, lat, lng, contact_info?, added_by?}` → `201 shelter` | Crowdsourced — no auth in Phase 1. |
| `POST /shelters/{id}/confirm` | empty body → `200 {id, confirm_count, last_confirmed_at}` | Same semantics as reports confirm. |
| `GET /shelters` | query: `lat?`, `lng?`, `radius_km?=50` → `[shelter…]` sorted by `confirm_count DESC, last_confirmed_at DESC NULLS LAST` | Radius filter when coords given. |

**Device upsert (all POST endpoints):** if the body carries `device_id`/`reporter_device_id`/`added_by`, run `INSERT INTO devices (id, platform, last_seen) VALUES (:id, 'unknown', now()) ON CONFLICT (id) DO UPDATE SET last_seen = now()` in the same transaction before the main insert. If absent, the FK column stays NULL. This keeps mesh-relayed payloads (which carry an arbitrary `origin_device_id` string) from failing FK checks — if the client sends a non-UUID string, store NULL instead of erroring (log a warning).

**Config (`app/config.py`):** `pydantic-settings` `BaseSettings` reading env: `DATABASE_URL` (required), plus pass-throughs for later phases (`SUPABASE_URL`, `SUPABASE_KEY`, `FCM_SERVER_KEY`, `LLM_API_KEY`, `MEDICAL_CARD_DEMO_KEY`, `OPEN_METEO_BASE_URL`, `NASA_EONET_URL`, `SACHET_RSS_URL` — all optional now, so Phase 4 doesn't touch config plumbing). `.env.example` lists every key with a one-line comment.

**`app/main.py`:** create app, `include_router` all five routers, add CORS `allow_origins=["*"]` (hackathon scope — phone + dashboard on unknown origins), and a startup log line with the masked DB host. Do **not** create tables at startup — alembic owns DDL.

## 5. Flutter Scaffold + Outbox (the only mobile work in this phase)

`pubspec.yaml` additions (pin major versions compatible at build time):
```yaml
dependencies:
  sqflite: ^2.3.0
  path_provider: ^2.1.0
  path: ^1.8.0
  uuid: ^4.3.0
dev_dependencies:
  sqflite_common_ffi: ^2.3.0   # enables unit-testing sqflite on the host VM
  flutter_test:
    sdk: flutter
```

**`lib/models/mesh_message.dart`** — the master-plan mesh message schema as a Dart class, because the outbox stores it verbatim:
```dart
// Fields: id (uuid v4 string), type (enum: sos, report, missingPerson, shelter),
// originDeviceId, ttl (int, default 6), priority (enum: high, normal),
// timestamp (ISO8601 string), payload (Map<String, dynamic>),
// encryptedPayload (String? base64).
// Methods: fromJson/toJson, copyWith({ttl}). Enum <-> wire string mapping:
// sos<->'SOS', report<->'REPORT', missingPerson<->'MISSING_PERSON', shelter<->'SHELTER'.
```

**`lib/storage/database.dart`** — sqflite open/create:
```sql
CREATE TABLE outbox (
  id TEXT PRIMARY KEY,
  type TEXT NOT NULL,
  priority TEXT NOT NULL,
  ttl INTEGER NOT NULL,
  payload TEXT NOT NULL,          -- full mesh-message JSON (encrypted_payload included)
  status TEXT NOT NULL DEFAULT 'pending',   -- 'pending' | 'sending' | 'sent' | 'failed'
  retry_count INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,       -- ISO8601
  last_attempt_at TEXT
);
CREATE TABLE seen_ids (
  id TEXT PRIMARY KEY,
  seen_at TEXT NOT NULL
);
```
(`seen_ids` is consumed by Phase 3's flooding algorithm — the 24 h expiry sweep also ships there. Creating the table now avoids a DB-migration story inside a hackathon app.)

**`lib/storage/outbox_dao.dart`** — the API Phase 2/3 will call:
```dart
class OutboxDao {
  Future<void> enqueue(MeshMessage msg);          // INSERT OR REPLACE, status 'pending'
  Future<List<MeshMessage>> pending({int limit = 50});
      // WHERE status IN ('pending','failed') ORDER BY priority='high' DESC, created_at ASC
      // (SOS outranks REPORT/SHELTER — this ordering is a master-plan requirement)
  Future<void> markSending(String id);
  Future<void> markSent(String id);
  Future<void> markFailed(String id);             // retry_count++, last_attempt_at=now
  Future<int> pendingCount();
}
```

**`test/outbox_test.dart`** — using `sqflite_common_ffi` (`sqfliteFfiInit(); databaseFactory = databaseFactoryFfi;`): enqueue SOS(normal? no — SOS is `high`) + two REPORTs → `pending()` returns SOS first, then REPORTs in creation order → `markSent` on SOS → pending returns only REPORTs → `markFailed` keeps it in pending with retry_count=1.

`lib/main.dart`: `MaterialApp(home: Scaffold(body: Center(child: Text('RELINK'))))` — deliberately empty. Real screens are Phase 2.

## 6. DBSCAN Clustering Service (`app/services/clustering.py`)

```python
def cluster_reports(reports: list[Report], eps_m: float = 500, min_samples: int = 2) -> ClusterResult:
```
- Extract `[[lat, lng], …]`, convert to **radians**, run `sklearn.cluster.DBSCAN(eps=eps_m / 6_371_000, min_samples=min_samples, metric='haversine')`.
- Return for each cluster: stable `cluster_id` (f"cluster-{label}" is fine — recomputed per call, not persisted), centroid (mean lat/lng), `report_count`, `total_confirmations` (sum of `confirm_count`), `last_confirmed_at` (max, nullable), `sample_description` (description of the highest-confirmation report), and the full `report_ids` list. Label `-1` points go in `noise` (id list only).
- Guard: fewer than `min_samples` total reports → everything is noise, no sklearn call. Empty input → empty result.
- The router fetches reports (optionally type-filtered) and delegates — no SQL inside the service. Keep it pure for easy unit testing.

## 7. Seed Script (`backend/scripts/seed.py`)

Standalone: `python -m scripts.seed` (uses the same `DATABASE_URL`). Idempotent via a `seed_tag` convention: delete rows where `description LIKE '[seed]%'` before inserting, and prefix every seeded description with `[seed]`.

Seed ~40 reports around one coherent demo region (default: Kochi, Kerala — center ≈ 9.98 N, 76.28 E; overridable via `SEED_CENTER_LAT`/`SEED_CENTER_LNG` env):
- 3 tight clusters (8–10 reports each, within ~300 m of a cluster center, same `type`): one `water` (flooded road), one `obstacle` (fallen trees/blocked road), one `disease` (fever cases).
- Remaining reports scattered randomly within 15 km, mixed types, random `confirm_count` 0–15, `last_confirmed_at` within the last 48 h, `created_at` spread over the past 5 days.
- 6 shelters spread across the region (realistic names, e.g. "Govt. HSS Relief Camp — Edappally"), varying confirm counts.
- 4 missing persons, 2 active `sos_events` with sample `plaintext_medical` (leave `encrypted_medical` NULL — Phase 3 owns ciphertext).
- Log a summary of inserted counts on completion.

## 8. Testing & Verification

- `pytest.ini`: `asyncio_mode` not needed (use httpx sync `Client` against a live server or `fastapi.testclient.TestClient`). Prefer `TestClient` + a test DB: `conftest.py` points the app's `DATABASE_URL` override at a `relink_test` database, runs `alembic upgrade head` in a session fixture, and truncates all tables between tests.
- Cover: health; SOS create + list + invalid body 422; reports create/confirm (count increments, `last_confirmed_at` set), confirm on unknown id 404, invalid type 422, radius filter; missing-persons create + case-insensitive search + radius filter; shelters create/confirm/list ordering (highest confirmations first); clustering — two reports 100 m apart + one 5 km away → one cluster of 2 + one noise id.
- Flutter: `flutter analyze` must be clean; `flutter test` green; `flutter build apk --debug` must succeed (proves the scaffold compiles for Android).

**Manual smoke (after migrations + seed):**
```bash
uvicorn app.main:app --reload
curl -X POST localhost:8000/reports -H 'Content-Type: application/json' \
     -d '{"type":"water","lat":9.98,"lng":76.28,"description":"knee-deep water"}'
curl localhost:8000/reports/clusters
```

## 9. Known Gotchas

- **Supabase** requires SSL on the direct connection (`?sslmode=require`) and its pooler is transaction-mode — if alembic hangs, use the session-mode pooler URL (port 5432 vs 6543). Ask the user for the exact connection string rather than guessing.
- `gen_random_uuid()` needs `pgcrypto` — included in the migration; on Supabase it already exists (harmless re-CREATE).
- Don't let FastAPI create tables (`Base.metadata.create_all`) — alembic only, or the two DDL sources will drift.
- Haversine SQL: prefer the bounding-box prefilter + Python-side haversine over raw great-circle SQL per row — simpler and fast enough at this scale.
- sqflite unit tests fail with "MissingPluginException" without `sqflite_common_ffi` setup — see §5 test snippet.
- Windows: activate venv via `.venv\Scripts\Activate.ps1`; if PowerShell blocks scripts, run `Set-ExecutionPolicy -Scope Process Bypass` first or use CMD.
- `uuid` Dart package v4: `const Uuid().v4()`.

## 10. Finish Checklist

- [ ] Migrations apply cleanly from empty DB (`alembic upgrade head`) and roll back (`alembic downgrade base`).
- [ ] `pytest` green; `flutter analyze` + `flutter test` green; debug APK builds.
- [ ] Seed script runs idempotently twice in a row without duplicate rows.
- [ ] `git status` clean except intended files; `.env` untracked.
- [ ] **Update `CLAUDE.md` §9 Status Log, Phase 1 entry** — 5–10 lines: what was built, any deviation from this file or the master plan (and why), what is broken/incomplete, anything Phase 2 must know (e.g. exact response shapes you settled on, seeded demo region, how to run the stack).
- [ ] Commit with message `phase 1: backend foundation + flutter outbox scaffold`.
