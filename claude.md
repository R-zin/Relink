# RELINK — Disaster Resilience Platform
### Project Spec / Build Guide (Hackathon Prototype — 1 Day)

> Theme: Living with Uncertainties, Building with Resilience
> Track: Advancing Disaster Management — Personnel Identification, Communication Systems, Disease Prevention

---

## 0. How To Use This Document (read this first, every session)

This file is split into **Core Context** (Sections 1–7) and a **4-Phase Build Plan** (Section 8). Each phase runs as its own agent session with no memory of prior sessions. To keep sessions fast and on-scope:

1. Read Section 1–7 once at the start of your phase — this is the shared ground truth, don't re-derive it.
2. Read **only your assigned phase** in Section 8. Do not read or "helpfully" touch other phases' scope — it wastes budget and risks conflicting decisions.
3. Before finishing, append a short entry to the **Status Log** (Section 9) — 5-10 lines: what you built, what deviated from spec and why, what's broken/incomplete. The next session reads this instead of re-scanning the codebase.
4. If you must deviate from something in Core Context, log it in the Status Log rather than silently diverging — later phases depend on Core Context being accurate.

---

## 1. Design Philosophy

Two distinct personas, two distinct device behaviors:

| | Trapped / isolated victim | Displaced / mobile survivor |
|---|---|---|
| Radio behavior | Triggered burst (SOS press), not continuous | Active mesh participation |
| Primary need | Get found, fast | Report, search, coordinate |
| Battery budget | Must last unknown duration | Rechargeable at camp |

Core architecture pattern: **Delay-Tolerant Networking (store → carry → forward)**. No device needs continuous internet. Any device that regains connectivity flushes its queue to the backend automatically.

**Platform decision (locked):** Native Flutter app with real Nearby Connections BLE mesh — not a web/PWA build. Browsers cannot act as BLE peripherals/advertisers, so a web app cannot replicate multi-hop flooding between offline phones; that capability requires native APIs. This is the highest-risk, highest-payoff piece of the whole build — see Phase 3 and the demo-day notes for how risk is contained.

---

## 2. UI/UX Design Direction — "Calm Humanitarian"

Chosen direction: warm, reassuring, plain-language — optimized for someone who may be frightened, not for looking like a tactical ops console.

- **Palette:** warm neutral base (off-white / warm gray), soft blue-teal as the primary accent for normal actions. One alarm-red is *reserved exclusively* for the SOS button and Severe/Red alert tags — nowhere else — so it keeps its urgency signal instead of becoming visual noise.
- **Typography:** rounded, friendly sans-serif (Inter/Nunito-style), generous line-height, no all-caps or aggressive weight in body copy.
- **Copy tone:** reassuring and plain-language everywhere except official NDMA alert text, which is quoted verbatim for accuracy.
- **Motion:** mostly gentle/minimal; the two exceptions that should feel urgent are the SOS confirmation state and an incoming Severe alert push.
- **Map pins:** soft, color-coded by type — shelter = teal, hazard/flooded road = amber, missing person = violet. Red stays reserved for SOS only.
- **Dashboard (React, responder-facing):** same palette and tone, but denser data tables are fine there — audience is responders, not survivors in crisis.

---

## 3. Finalized Feature Set

**Core**
1. **SOS button** — internet-first send; P2P mesh flooding fallback until any hop reaches internet. Carries the encrypted medical card (Section 5).
2. **Live Map & Crowdsourced Layers** *(replaces the old separate "clustering-based reporting" and "shelter mapping" features — merged into one map feature with per-type trust signals)*:
   - GPS auto-captures lat/lng on every submission (SOS, report, shelter, missing person) via the device's location services; user can nudge the pin manually before submitting.
   - One map view (`flutter_map` on mobile, Leaflet on dashboard) with toggleable layers: relief camps/shelters, flooded/blocked roads & other hazards, missing persons (last-seen), and satellite-observed flood extent from Copernicus Global Flood Monitoring (GFM), shown with its observation time.
   - Each layer type carries its **own independent** crowdsourced trust signal — confirm/upvote count + last-verified timestamp (e.g. "Confirmed by 12 · verified 20 min ago") — not just shelters as before.
   - DBSCAN clustering (server-side, unchanged) collapses near-duplicate hazard reports before they hit the map, so confirmations accumulate on one cluster instead of fragmenting.
   - Missing-person reports are last-seen location + description only (no face matching — stays deferred).
3. **Real-time regional alerts** — NDMA Sachet CAP/RSS feed, delivered as **true OS-level push notifications via FCM** — must appear in the system notification tray even when the app is backgrounded or killed, not just an in-app banner. High-priority/heads-up notification channel on Android for Red/Orange severity. Tapping the notification deep-links to that region's alert detail.
4. **Stats page** — live hazard dashboard + AI-generated plain-language risk review.

**Optional (build last, only if time remains)**
5. **Social signal monitoring** — X/Twitter hashtag search or user-forwarded posts for regional alert triggers. *(Not Instagram Reels — no viable public API for location/keyword video search; contradicts offline-first premise anyway.)*

**Explicitly deferred (mention in pitch as roadmap, do not build)**
- Live on-device face matching
- Mortal remains forensic registry
- Direct India-WRIS live scraping (fragile HTML scrape — use cached/mock data instead)
- Per-org asymmetric key rotation for medical card encryption (see Section 5 — symmetric demo key is intentional hackathon scope)

---

## 4. System Architecture

```
┌─────────────────┐   BLE/Nearby Connections   ┌─────────────────┐
│  Victim/Survivor │ ◄───────flooding mesh────► │  Nearby Devices  │
│   Mobile App     │                             │   (relay hops)  │
└────────┬─────────┘                             └────────┬────────┘
         │  (once any hop has internet)                   │
         ▼                                                 ▼
                    ┌───────────────────────┐
                    │   FastAPI Backend      │
                    │  - ingest SOS/reports  │
                    │  - DBSCAN clustering   │
                    │  - external API fetch  │
                    │    (GloFAS forecast +  │
                    │     GFM flood extent)  │
                    │  - AI stats review     │
                    │  - FCM alert push      │
                    └──────────┬─────────────┘
                               │
                    ┌──────────▼─────────────┐
                    │ Postgres (Supabase)     │
                    │  + realtime subscribe   │
                    └──────────┬─────────────┘
                               │
                    ┌──────────▼─────────────┐
                    │  Command Dashboard      │
                    │  (React + Leaflet)      │
                    └─────────────────────────┘
```

---

## 5. Medical Card & Encryption (simplified)

**Card fields:**
- **Plaintext / broadcast openly** (responders need this instantly, no decrypt step): name, blood group, known allergies, emergency contact (name + phone).
- **Encrypted** (full context, gated to responders): medical conditions/notes, current medications, insurance provider + policy number.

**Mechanism — symmetric AES-256-GCM (not asymmetric NaCl box):**
- A single pre-shared demo key (`MEDICAL_CARD_DEMO_KEY`) is baked into the app build config and into the responder/dashboard demo environment.
- Sensitive fields are encrypted client-side before being placed into the SOS message's `encrypted_payload` field (same message schema as before) — travels through BLE mesh flooding exactly as originally designed.
- Decryption happens only in the responder dashboard demo environment, decrypt-on-view, never persisted decrypted.
- Flutter library: use `cryptography` (or `encrypt`) for AES-GCM — drop `sodium_libs` from the stack, it was only needed for the asymmetric box approach.
- Why this over the original design: this still gives you a real, working, offline, over-BLE encryption demo — which is what you asked to show live — with roughly a third of the integration surface of keypair-based asymmetric crypto. Per-responder-org key rotation is a legitimate v2 feature, noted as roadmap only.

---

## 6. Tech Stack

| Layer | Choice | Why |
|---|---|---|
| Mobile app | Flutter (Dart) | Fast cross-platform UI; good chart/map plugin ecosystem |
| Mesh layer | Google Nearby Connections API (`nearby_connections` plugin, `P2P_CLUSTER` strategy), Android only | Handles discovery + transport switching (BLE/Wi-Fi Direct) — do NOT hand-roll raw GATT mesh routing in hackathon time |
| Local offline storage | `sqflite` | Outbox queue for unsent SOS/reports |
| Location | `geolocator` | GPS capture for map submissions |
| Maps (mobile) | `flutter_map` (OpenStreetMap) | No API key required; supports offline tile caching |
| Charts (stats page) | `fl_chart` | Native Flutter charting |
| Push notifications | Firebase Cloud Messaging + `flutter_local_notifications` | System-tray push even when backgrounded; note: background handler must be a top-level/static function — common Flutter gotcha |
| Crypto | `cryptography` (Dart) — AES-256-GCM, symmetric | Real encryption, low integration risk (see Section 5) |
| Backend | Python + FastAPI | Async fan-out to multiple hazard APIs; easy LLM + scikit-learn integration |
| Clustering | scikit-learn DBSCAN | Simple, no GIS extension needed |
| Database | Postgres via Supabase | Free managed Postgres + realtime subscriptions + auth, near-zero ops |
| Command dashboard | React + Vite, Leaflet, Recharts | Fast to build, live map + charts |
| AI stats review | LLM API (Claude or hackathon-sponsored model) | Synthesizes 6 metrics into plain-language risk summary |
| Scheduler | APScheduler (in FastAPI) | Polls Sachet RSS + weather APIs every 10-15 min, caches results |

---

## 7. Data Contract (shared across all phases — do not redefine)

**Mesh message schema:**
```json
{
  "id": "uuid-v4",
  "type": "SOS | REPORT | MISSING_PERSON | SHELTER",
  "origin_device_id": "string",
  "ttl": 6,
  "priority": "high | normal",
  "timestamp": "ISO8601",
  "payload": { "...type-specific fields..." },
  "encrypted_payload": "base64 AES-GCM ciphertext (medical card sensitive fields, SOS only)"
}
```

**Flooding algorithm (per device):**
1. On receive: check local `seen_ids` set (persisted, TTL-expired after 24h).
2. If new: store locally, surface to UI/queue for backend sync.
3. If internet available: POST to backend immediately, mark delivered.
4. If no internet and `ttl > 0`: decrement TTL, rebroadcast to all connected peers except sender.
5. `SOS` type messages are queued and sent ahead of `REPORT`/`SHELTER` types in the outbound send order.

**Backend API endpoints:**
```
POST   /sos                     — ingest SOS (direct or mesh-relayed)
POST   /reports                 — create obstacle/disease/water report
POST   /reports/{id}/confirm    — crowdsourced confirm/upvote (mirrors shelters)
GET    /reports/clusters        — DBSCAN-clustered report groups
POST   /missing-persons         — submit missing-person report
GET    /missing-persons/search  — search/match by name+location
POST   /shelters                — add shelter (crowdsourced)
POST   /shelters/{id}/confirm   — bump trust/last-verified signal
GET    /shelters                — list nearby shelters
GET    /alerts                  — cached Sachet alerts for a region
GET    /stats                   — aggregated hazard metrics
GET    /stats/ai-review         — cached AI-generated risk summary
POST   /medical/decrypt         — responder-only, break-glass decrypt (demo auth)
```

**Data models (Postgres, simplified):**
```
devices(id, public_key, last_seen, platform)
sos_events(id, device_id, lat, lng, plaintext_medical, encrypted_medical, status, created_at)
reports(id, type, lat, lng, description, device_id, confirm_count, last_confirmed_at, created_at)
missing_persons(id, name, last_seen_lat, last_seen_lng, description, reporter_device_id, status, created_at)
shelters(id, name, lat, lng, contact_info, confirm_count, last_confirmed_at, added_by)
stats_cache(id, metric, value_json, fetched_at)
ai_review_cache(id, region, summary_text, risk_tag, generated_at)
```

**External data sources (Stats page):**

| Metric | Primary Source | Format | Auth | Notes |
|---|---|---|---|---|
| River discharge & forecast risk (m³/s) | Open-Meteo GloFAS API | JSON | None | Verified free public access; use for river-discharge forecasts and forward-looking flood risk |
| Satellite-observed flood extent | Copernicus Global Flood Monitoring (GFM) | Geospatial flood-extent product | Not specified here | Use as an additional observed-flood layer; display the latest available observation time and do not present it as real-time |
| Rainfall & wind gusts | Open-Meteo Forecast API | JSON | None | Use as live source; cite IMD as the "official" name in UI copy only |
| Official alerts (Red/Orange) | NDMA Sachet CAP/RSS feed (`sachet.ndma.gov.in/cap_public_website/rss/rss_<state>.xml`) | RSS/XML | None | Shared with the Real-Time Alerts feature — reuse same fetch/parse code |
| Global cyclones/events | NASA EONET v3 | GeoJSON | None | Verified free public access |
| Dam fullness & levels | **Static/mock cached dataset** | JSON | — | India-WRIS has no reliable bulk/live API — build UI against seeded mock data, note as roadmap |
| Coastal swell/surge | Open-Meteo Marine API | JSON | None | Use as live source; cite INCOIS as the "official" name in UI copy only |

**AI Review generation:** feed the 7 fetched metrics as structured JSON to the LLM with a system prompt like: *"You are a disaster-risk analyst. Given these live hazard metrics for [region], produce a 3-4 sentence plain-language summary and a single risk tag (Low/Moderate/High/Severe). Be concrete, cite the specific numbers driving your assessment, no hedging filler."* Use GloFAS for river-discharge forecast/risk and GFM only as evidence of satellite-observed flood extent, including the observation time. Cache result, regenerate every 15-30 min.

**Environment variables:**
```
SUPABASE_URL=
SUPABASE_KEY=
FCM_SERVER_KEY=
LLM_API_KEY=
OPEN_METEO_BASE_URL=https://api.open-meteo.com
NASA_EONET_URL=https://eonet.gsfc.nasa.gov/api/v3
SACHET_RSS_URL=https://sachet.ndma.gov.in/cap_public_website/rss/rss_<state>.xml
MEDICAL_CARD_DEMO_KEY=   # AES-256-GCM pre-shared key, app build + responder demo env only
```

**Repo structure:**
```
relink/
├── mobile/               # Flutter app
│   ├── lib/
│   │   ├── mesh/         # Nearby Connections wrapper, flooding protocol
│   │   ├── crypto/       # AES-GCM encrypt/decrypt
│   │   ├── screens/      # SOS, live map, stats, alerts
│   │   └── storage/      # sqflite offline outbox
├── backend/              # FastAPI
│   ├── routers/
│   ├── services/         # clustering, external_apis, ai_review
│   └── jobs/             # scheduler for alert/stats polling
├── dashboard/            # React + Vite
│   ├── src/components/   # map, charts, review panel
└── CLAUDE.md             # this file
```

---

## 8. Build Plan — 4 Phases, One Session Each

### Phase 1 — Foundation
**Scope:** Backend skeleton, Postgres schema (Section 7), core CRUD endpoints (`/sos`, `/reports`, `/reports/{id}/confirm`, `/shelters`, `/shelters/{id}/confirm`, `/missing-persons`). Client-side `sqflite` outbox scaffold (schema only, no UI yet).
**Do not touch:** mesh, crypto, external APIs, dashboard, UI screens.
**Definition of done:** every endpoint in Section 7 responds correctly against a local Postgres instance; outbox table exists and can store/retrieve queued messages.

### Phase 2 — Core App Flows (internet path only)
**Scope:** Flutter screens — SOS button, Live Map (Section 3.2) with GPS capture via `geolocator`, report/shelter/missing-person submission, all wired directly to the Phase 1 backend over HTTP. No mesh, no encryption yet — medical card fields exist in the UI but are sent as plain HTTP for now.
**Do not touch:** Nearby Connections, crypto, dashboard, stats/alerts.
**Definition of done:** a phone with internet can submit an SOS, a hazard report, and a shelter, and see them reflected via the backend; map shows all three layer types with confirm counts.

### Phase 3 — Offline Path: Mesh + Medical Card Crypto
**Scope:** This is the highest-risk phase — isolate it, don't split focus. Nearby Connections integration (`P2P_CLUSTER` strategy), the flooding algorithm from Section 7, sync-on-reconnect logic for the outbox. AES-GCM encryption (Section 5) applied to sensitive medical card fields before they enter the mesh payload; decrypt path wired into the dashboard demo environment.
**Requires:** 2+ physical Android devices — cannot be meaningfully tested on emulators.
**Do not touch:** stats/alerts/AI review, dashboard polish.
**Definition of done:** two phones in airplane mode, one presses SOS, the other relays it, a third device (or the same one) with internet flushes it to the backend, and the responder dashboard can decrypt the sensitive fields. **Record this working end-to-end at least once as a backup video** — live BLE demos are inherently flaky and you will not get a second take in front of judges.

### Phase 4 — Alerts, Stats, Dashboard, Demo Prep
**Scope:** External hazard API integration (Section 7 table), including Open-Meteo GloFAS for river discharge/forecast risk and Copernicus GFM for satellite-observed flood extent, + AI review endpoint, Sachet RSS polling + FCM push as true system-tray notifications (Section 3.3) with high-priority channel, React dashboard (map + charts + observed-flood extent layer + confirm counts + decrypt view), seed mock historical data so the dashboard doesn't look empty, rehearse triggering one live report during the demo. Social signal monitoring (Section 3, optional) only if time remains after everything else here is solid.
**Do not touch:** anything in Phases 1-3 unless fixing a bug blocking this phase.
**Definition of done:** dashboard shows seeded historical data + live updates; a Red/Orange alert produces an actual notification-tray push on a backgrounded/killed app; AI risk summary renders for at least one region.

---

## 9. Status Log

*(Append one entry per phase/session — keep each to ~5-10 lines: what was built, deviations from Core Context and why, what's broken or incomplete for the next phase.)*

- Phase 1: —
- Phase 2: —
- Phase 3: —
- Phase 4: —

---

## 10. Demo-Day Notes

- BLE mesh cannot be tested on emulators — need 2-3 physical Android phones, confirmed working well before demo day, not day-of.
- Pre-cache offline map tiles for the venue/demo region in advance.
- Seed the backend with mock historical reports/shelters so the dashboard heatmap looks populated, then trigger one *live* new report during the demo to show real-time propagation.
- For the flood demonstration, show GloFAS river-discharge forecast/risk alongside the GFM satellite-observed flood-extent layer, clearly labeling the GFM observation time as the latest available observation rather than a real-time feed.
- **Have the Phase 3 backup recording ready and easy to reach** in case live Bluetooth flakes during judging — treat this as required, not optional, given the platform decision to go real BLE.
- Test the FCM background push on a genuinely backgrounded/killed app state before demo day — this is a common last-minute surprise.
