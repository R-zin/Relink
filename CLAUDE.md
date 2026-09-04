# RELINK — Disaster Resilience Platform
### Project Spec / Build Guide (Hackathon Prototype)

> Theme: Living with Uncertainties, Building with Resilience
> Track: Advancing Disaster Management — Personnel Identification, Communication Systems, Disease Prevention

---

## 1. Design Philosophy

Two distinct personas, two distinct device behaviors:

| | Trapped / isolated victim | Displaced / mobile survivor |
|---|---|---|
| Radio behavior | Triggered burst (SOS press), not continuous | Active mesh participation |
| Primary need | Get found, fast | Report, search, coordinate |
| Battery budget | Must last unknown duration | Rechargeable at camp |

Core architecture pattern: **Delay-Tolerant Networking (store → carry → forward)**. No device needs continuous internet. Any device that regains connectivity flushes its queue to the backend automatically.

---

## 2. Finalized Feature Set

**Core**
1. **SOS button** — internet-first send; P2P mesh flooding fallback until any hop reaches internet. Carries cryptographically protected medical info.
2. **Clustering-based reporting** — obstacles, disease symptoms, waterlogged roads; DBSCAN clustering server-side. Includes missing-person reports via last-seen location + description (no face matching in scope).
3. **Shelter mapping** — crowdsourced, with a confirm/last-verified trust signal.
4. **Real-time regional alerts** — NDMA Sachet CAP/RSS feed, pushed via FCM to users in the affected region.
5. **Stats page** — live hazard dashboard + AI-generated plain-language risk review.

**Optional (build last, only if time remains)**
6. **Social signal monitoring** — X/Twitter hashtag search or user-forwarded posts for regional alert triggers. *(Not Instagram Reels — no viable public API for location/keyword video search; contradicts offline-first premise anyway.)*

**Explicitly deferred (mention in pitch as roadmap, do not build)**
- Live on-device face matching
- Mortal remains forensic registry
- Direct India-WRIS live scraping (fragile HTML scrape — use cached/mock data instead)

---

## 3. System Architecture

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

## 4. Tech Stack

| Layer | Choice | Why |
|---|---|---|
| Mobile app | Flutter (Dart) | Fast cross-platform UI; good chart/map plugin ecosystem |
| Mesh layer | Google Nearby Connections API (`nearby_connections` plugin, `P2P_CLUSTER` strategy), Android only | Handles discovery + transport switching (BLE/Wi-Fi Direct) — do NOT hand-roll raw GATT mesh routing in hackathon time |
| Local offline storage | `sqflite` | Outbox queue for unsent SOS/reports |
| Maps (mobile) | `flutter_map` (OpenStreetMap) | No API key required; supports offline tile caching |
| Charts (stats page) | `fl_chart` | Native Flutter charting |
| Push notifications | Firebase Cloud Messaging | Standard, well-documented Flutter support |
| Crypto | `sodium_libs` (libsodium/NaCl) | X25519 box encryption for medical break-glass payload |
| Backend | Python + FastAPI | Async fan-out to multiple hazard APIs; easy LLM + scikit-learn integration |
| Clustering | scikit-learn DBSCAN | Simple, no GIS extension needed |
| Database | Postgres via Supabase | Free managed Postgres + realtime subscriptions + auth, near-zero ops |
| Command dashboard | React + Vite, Leaflet, Recharts | Fast to build, live map + charts |
| AI stats review | LLM API (Claude or hackathon-sponsored model) | Synthesizes 6 metrics into plain-language risk summary |
| Scheduler | APScheduler (in FastAPI) | Polls Sachet RSS + weather APIs every 10-15 min, caches results |

---

## 5. Mesh / DTN Protocol

**Message schema:**
```json
{
  "id": "uuid-v4",
  "type": "SOS | REPORT | MISSING_PERSON | SHELTER",
  "origin_device_id": "string",
  "ttl": 6,
  "priority": "high | normal",
  "timestamp": "ISO8601",
  "payload": { "...type-specific fields..." },
  "encrypted_payload": "base64 (medical card, SOS only)"
}
```

**Flooding algorithm (per device):**
1. On receive: check local `seen_ids` set (persisted, TTL-expired after 24h).
2. If new: store locally, surface to UI/queue for backend sync.
3. If internet available: POST to backend immediately, mark delivered.
4. If no internet and `ttl > 0`: decrement TTL, rebroadcast to all connected peers except sender.
5. `SOS` type messages are queued and sent ahead of `REPORT`/`SHELTER` types in the outbound send order.

---

## 6. Cryptography (Medical Break-Glass)

- Plaintext fields (broadcast openly, always): blood group, known allergies, emergency contact.
- Sensitive fields (full medical history) encrypted client-side via NaCl `box` (X25519-XSalsa20-Poly1305) to a **static demo "responder org" public key**.
- Private key held only by the dashboard/responder-side demo environment — decrypt-on-view, never stored decrypted.
- No per-user signing needed for hackathon scope — encryption only, not authentication.

---

## 7. External Data Sources (Stats Page)

| Metric | Primary Source | Format | Auth | Notes |
|---|---|---|---|---|
| River floods (m³/s) | Open-Meteo GloFAS API | JSON | None | Verified free public access |
| Rainfall & wind gusts | Open-Meteo Forecast API | JSON | None | Use as live source; cite IMD as the "official" name in UI copy only — IMD has no easy public dev API |
| Official alerts (Red/Orange) | NDMA Sachet CAP/RSS feed (`sachet.ndma.gov.in/cap_public_website/rss/rss_<state>.xml`) | RSS/XML | None | Confirmed public; shared with the Real-Time Alerts feature — reuse same fetch/parse code |
| Global cyclones/events | NASA EONET v3 | GeoJSON | None | Verified free public access |
| Dam fullness & levels | **Static/mock cached dataset** | JSON | — | India-WRIS has no reliable bulk/live API (confirmed) — live scraping is fragile and demo-risky. Build the UI against seeded mock data; note "WRIS integration" as a roadmap item in the pitch |
| Coastal swell/surge | Open-Meteo Marine API | JSON | None | Use as live source; cite INCOIS as the "official" name in UI copy only |

**AI Review generation:** feed the 6 fetched metrics as structured JSON to the LLM with a system prompt like: *"You are a disaster-risk analyst. Given these live hazard metrics for [region], produce a 3-4 sentence plain-language summary and a single risk tag (Low/Moderate/High/Severe). Be concrete, cite the specific numbers driving your assessment, no hedging filler."* Cache result, regenerate every 15-30 min.

---

## 8. Backend API Endpoints

```
POST   /sos                     — ingest SOS (direct or mesh-relayed)
POST   /reports                 — create obstacle/disease/water report
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

---

## 9. Data Models (Postgres, simplified)

```
devices(id, public_key, last_seen, platform)
sos_events(id, device_id, lat, lng, plaintext_medical, encrypted_medical, status, created_at)
reports(id, type, lat, lng, description, device_id, created_at)
missing_persons(id, name, last_seen_lat, last_seen_lng, description, reporter_device_id, status, created_at)
shelters(id, name, lat, lng, contact_info, confirm_count, last_confirmed_at, added_by)
stats_cache(id, metric, value_json, fetched_at)
ai_review_cache(id, region, summary_text, risk_tag, generated_at)
```

---

## 10. Environment Variables

```
SUPABASE_URL=
SUPABASE_KEY=
FCM_SERVER_KEY=
LLM_API_KEY=
OPEN_METEO_BASE_URL=https://api.open-meteo.com
NASA_EONET_URL=https://eonet.gsfc.nasa.gov/api/v3
SACHET_RSS_URL=https://sachet.ndma.gov.in/cap_public_website/rss/rss_<state>.xml
RESPONDER_ORG_PUBLIC_KEY=
RESPONDER_ORG_PRIVATE_KEY=   # dashboard/demo env only, never on mobile
```

---

## 11. Suggested Repo Structure

```
relink/
├── mobile/               # Flutter app
│   ├── lib/
│   │   ├── mesh/         # Nearby Connections wrapper, flooding protocol
│   │   ├── crypto/       # NaCl box encrypt/decrypt
│   │   ├── screens/      # SOS, reports, shelters, stats, alerts
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

## 12. Hackathon Build Order (priority-ordered)

1. Backend skeleton + Postgres schema + `/reports`, `/shelters`, `/sos` endpoints
2. Mobile app shell — SOS button, feature panel, screens wired to backend (internet path first)
3. Stats page — external API integration + AI review call (independent, parallelizable work)
4. Dashboard — map + live report/shelter view
5. Mesh layer — Nearby Connections integration + flooding protocol (highest risk, start early, needs 2+ physical Android devices to test)
6. Crypto — medical break-glass encryption
7. Alerts — Sachet RSS polling + FCM push
8. *(If time remains)* Social signal monitoring (optional)

## 13. Demo-Day Notes

- BLE mesh cannot be tested on emulators — need 2-3 physical Android phones.
- Pre-cache offline map tiles for the venue/demo region in advance.
- Seed the backend with mock historical reports/shelters so the dashboard heatmap looks populated, then trigger one *live* new report during the demo to show real-time propagation.
- Have a backup recording of the mesh hop demo in case live Bluetooth flakes during judging.
