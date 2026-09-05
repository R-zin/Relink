# PHASE 4 — Hazard Intelligence + Emergency Alerting + Command Dashboard + Demo Polish

> Final phase: external hazard telemetry + AI operational review + NDMA Sachet RSS alert ingestion + local emergency heads-up notifications, and the React Incident Command Dashboard with live map and inline 1-click SOS medical decryption. Everything the judges see on the presentation screen and disaster command center comes from this phase.
>
> **You are the Phase 4 agent.** The master plan (`CLAUDE.md`, auto-loaded) is Core Context — §7's external-data-source table + AI-review prompt are your contract, §2 governs dashboard styling, §10 is your demo checklist. Read the Phase 1–3 entries in `CLAUDE.md §9 Status Log` first; skim `backend/app/` structure, `mobile/lib/screens/alerts/` + `stats/` (you're filling those placeholders), and Phase 3's `/medical/decrypt` endpoint. Scope: `backend/` services/jobs/routers additions, `mobile/` alerts+stats screens + local notification wiring, and all of `dashboard/`.
>
> **If anything is ambiguous or you hit a blocker (an external API is down/changed, feed format drift) — STOP and ask the user, then continue with their answer.**

---

## 0. Scope & Definition of Done

**Build:**
1. **Backend Hazard Fetch Services:** Open-Meteo GloFAS river discharge forecast, Open-Meteo Forecast/Weather precipitation curves, and realistic static Kerala dam capacities dataset (`dams_mock.json`), all cached in `stats_cache` with graceful fallback fixtures.
2. **Backend AI Risk Review (`/stats/ai-review`):** Synthesizes multi-hazard metrics into an executive plain-language assessment with a parsed risk tag (`Low | Moderate | High | Severe`), cached with 20-minute TTL.
3. **NDMA Sachet RSS Poller & Emergency Alerting:** Periodic RSS poller (`rss_kerala.xml`) $\rightarrow$ stored in `alerts_cache` $\rightarrow$ triggers local high-priority heads-up notifications (`flutter_local_notifications`) and mesh dissemination.
4. **Mobile Screens:** Real Alerts screen (severity chips + official NDMA copy), real Stats screen (river forecast curves, rainfall bars, dam levels, AI risk assessment card).
5. **React Incident Command Dashboard (`dashboard/`):** React 18 + Vite + Leaflet + Recharts. Real-time incident map (SOS markers, hazard clusters, shelters, Copernicus GFM flood extent polygon), live SOS feed, and **inline 1-click medical record decryption** directly in the dashboard UI.
6. **Demo Polish & Seed Data Refresh:** Seed database populated with realistic Kochi disaster scenario, demo checklist executed.

**Out of scope:**
- External FCM Cloud Messaging setup (replaced with reliable local high-priority notification channels triggered via backend or mesh).
- Live raster satellite processing from Copernicus CDSE (pinned to pre-baked GeoJSON fixture with observation timestamp).
- Standalone `decrypt.html` (decryption is embedded directly inside the Command Dashboard).

**Done when:**
1. `GET /stats`, `GET /stats/ai-review?region=…`, and `GET /alerts?state=…` serve cached telemetry sourced from live APIs or verified local fixtures.
2. An official alert (or test trigger via `POST /alerts/test-alert`) produces an immediate heads-up OS notification on the phone.
3. React Command Dashboard renders on the presentation screen: populated Leaflet map with GFM flood extent, live hazard charts, AI summary card, and incoming SOS feed.
4. Clicking an SOS card in the dashboard cleanly decrypts and displays the sensitive medical profile inline.
5. Master plan §9 Status Log, Phase 4 entry updated; demo checklist (§11) executed.

---

## 1. Prereqs

- Phase 1–3 Status Log entries read; backend + mobile app running end-to-end.
- Environment variables needed: `LLM_API_KEY` (Claude, Gemini, or hackathon-provided LLM API) and `MEDICAL_CARD_DEMO_KEY` (shared 64-hex key).
- Target state for Sachet alerts: Kerala (`rss_kerala.xml`). Open-Meteo and NASA require no authentication.

---

## 2. Backend: External Hazard Telemetry (`backend/app/services/external_apis/`)

Create modular fetch adapters with a common `cached_fetch(metric_name, fetch_fn, ttl_minutes)` wrapper backed by `stats_cache`. Use `httpx.AsyncClient` with 10 s timeouts. Every fetcher must degrade gracefully: if an external network call fails, serve the cached value with `stale: true`, or the local fixture with `fallback: true`.

| Module | Source | Target & Output Shape |
|---|---|---|
| `glofas.py` | Open-Meteo GloFAS (`https://flood-api.open-meteo.com/v1/flood`) | Periyar river basin (`10.02°N, 76.32°E`): latest discharge ($m^3/s$), 7-day forecast array, trend vs mean. |
| `weather.py` | Open-Meteo Forecast | 24 h rainfall total, hourly rain forecast, wind gusts (cited as IMD in UI copy). |
| `dams.py` | Static dataset (`backend/app/data/dams_mock.json`) | 5 key Kerala reservoirs (Idukki, Mullaperiyar, Idamalayar, Banasura Sagar, Kakki) with capacity percentage, danger level, and last updated time. |
| `gfm.py` | Copernicus GFM Fixture (`backend/app/data/fixtures/gfm.geojson`) | Sentinel-1 SAR observed flood inundation polygons for the demo region + **observation timestamp** (`2026-09-04T18:00:00Z`). Never presented as real-time. |
| `marine.py` *(Optional)* | Open-Meteo Marine | Coastal swell wave height for Cochin port (cited as INCOIS in UI copy). |
| `eonet.py` *(Optional)* | NASA EONET v3 | Severe storm/cyclone events within 1,500 km radius. |

**`GET /stats` (`routers/stats.py`):**
Returns consolidated metrics:
```json
{
  "region": "Kochi, Kerala",
  "fetched_at": "2026-09-05T08:30:00Z",
  "metrics": {
    "glofas": { "discharge_m3s": 1420.5, "trend": "rising", "forecast": [...], "source_label": "GloFAS Flood API" },
    "weather": { "rainfall_24h_mm": 184.2, "max_gust_kmh": 68.0, "source_label": "IMD (Open-Meteo)" },
    "dams": [ { "name": "Mullaperiyar", "storage_pct": 94.2, "danger_level_pct": 95.0 } ],
    "gfm": { "observed_at": "2026-09-04T18:00:00Z", "source_label": "Copernicus GFM (Sentinel-1 SAR)", "polygon_count": 4 }
  }
}
```

---

## 3. Backend: AI Risk Review Service (`services/ai_review.py`)

- **`GET /stats/ai-review?region=…`:** Reads `ai_review_cache`; if older than 20 minutes (or missing), generates a fresh synthesis.
- **Generation:** Consolidates `/stats` metrics JSON and feeds it to the LLM with the master plan §7 prompt:
  > *"You are a disaster-risk analyst. Given these live hazard metrics for [Kochi, Kerala], produce a 3-4 sentence plain-language summary and a single risk tag (Low/Moderate/High/Severe). Be concrete, cite the specific numbers driving your assessment (discharge rate, rainfall mm, dam percentage), no hedging filler. Conclude with RISK TAG: <Tag>."*
- **Risk Tag Parser:** Regex-extract `RISK TAG: (Low|Moderate|High|Severe)` from model response.
- **Deterministic Rule Fallback:** If the LLM API call times out or fails, evaluate metric thresholds in Python (e.g. `rainfall > 150mm || dam > 90%` $\rightarrow$ `Severe`) and return an instant operational summary.

---

## 4. Backend: Sachet RSS Poller & Alerts Service (`services/alerts_service.py`, `jobs/scheduler.py`)

1. **APScheduler Background Jobs:**
   - `poll_sachet` (every 10 min): Ingests `SACHET_RSS_URL` (`rss_kerala.xml`), parses XML/CAP fields, extracts severity (Red/Orange/Yellow/Green), affected districts, and description.
   - Upserts into `alerts_cache` table (migration `0003_alerts_cache.py`).
   - `refresh_stats` (every 15 min): Warms `stats_cache`.
2. **Endpoints (`routers/alerts.py`):**
   - `GET /alerts?state=kerala`: Returns active alerts ordered by issued date.
   - `POST /alerts/test-alert`: Demo trigger that synthesizes a Red warning ("Severe Flooding Alert: Aluva & Paravur taluks") for immediate testing during presentations.

---

## 5. Mobile: Local Emergency Notifications & Screens

1. **Local High-Priority Heads-Up Notifications (`lib/services/notification_service.dart`):**
   - Add `flutter_local_notifications`.
   - Setup channel: `AndroidNotificationChannel('relink_alerts_high', 'Severe Alerts', importance: Importance.max, playSound: true, enableVibration: true)`.
   - When an incoming Severe/Red alert is received (either via cloud polling or via BLE mesh hopping), immediately trigger a heads-up banner in the system notification tray.
2. **Alerts Screen (`screens/alerts/alerts_screen.dart`):**
   - Renders list of official alerts from backend or local cache.
   - Red/Orange alerts utilize the reserved Alarm Red badge styling.
   - Quoting official NDMA alert text verbatim.
3. **Stats Screen (`screens/stats/stats_screen.dart`):**
   - AI Review Summary Card with risk tag badge (`Severe` = alarm red, `High` = amber, `Moderate` = teal).
   - Metric cards: River discharge gauge + GloFAS 7-day forecast chart (`fl_chart`), 24h rainfall bar chart, Dam fullness progress bars with danger thresholds.
   - Clear data attribution pills on every card ("IMD", "GloFAS", "CWC Dams").

---

## 6. React Incident Command Dashboard (`dashboard/`)

Vite + React 18 + TypeScript + Leaflet (`react-leaflet`) + Recharts. Dense, authoritative humanitarian console for incident commanders.

```
dashboard/src/
├── main.tsx, App.tsx, index.css
├── api.ts                  # Fetch client (VITE_API_BASE_URL)
├── components/
│   ├── Navbar.tsx          # "RELINK — Incident Command Center", live clock, active alert ticker
│   ├── CommandMap.tsx      # Leaflet map with toggleable layers:
│   │                       #   - SOS Beacons (pulsing Red markers)
│   │                       #   - Hazard Clusters (Amber badges with count)
│   │                       #   - Safe Shelters (Teal markers)
│   │                       #   - Missing Persons (Violet pins)
│   │                       #   - GFM Satellite Inundation (Semi-transparent blue polygon + observation timestamp)
│   ├── SosFeed.tsx         # Live-updating emergency SOS card stream
│   ├── DecryptModal.tsx    # INLINE Decrypt Panel: 1-click decrypt of sensitive medical cards
│   ├── StatsGrid.tsx       # Key telemetry (Discharge, Rainfall, Dam storage)
│   ├── ChartsPanel.tsx     # Recharts: River discharge forecast curve, rainfall histogram
│   ├── AiReviewBanner.tsx  # Plain-language risk analysis + Risk Tag badge + refresh trigger
│   └── AlertsList.tsx      # Official NDMA warnings + "Trigger Demo Red Alert" button
```

### Inline SOS Medical Record Decryption:
- When an incident commander clicks an SOS card in `SosFeed.tsx`:
  - Public fields (`name`, `blood_group`, `allergies`, `emergency_contact`) display immediately.
  - Sensitive encrypted payload (`encrypted_medical`) has a clean **"Decrypt Medical Record"** action.
  - Calls `POST /medical/decrypt` (or executes client-side Web Crypto with the demo key) $\rightarrow$ instantly renders medical conditions, current medications, and insurance policy side-by-side.
  - Includes clear disclaimer: *"Decrypted on view for responder authorization — never persisted in plaintext"*.

---

## 7. Demo Checklist & Rehearsal (Judge Presentation)

1. **The Big Screen (Dashboard):**
   - Open Command Dashboard on the projector/laptop.
   - Show populated Kochi map with hazard clusters, shelters, and Copernicus GFM flood extent.
   - Point out AI Risk Review banner citing specific discharge and rainfall metrics.
2. **The Offline Mesh Proof (2 Android Phones):**
   - Both phones in Airplane Mode with Bluetooth ON.
   - Show `🟢 1 Peer Nearby` on both phone headers.
   - Phone A submits a road hazard $\rightarrow$ Phone B's map updates via BLE mesh with `📡 Via Mesh` badge.
3. **Emergency SOS & Decrypt:**
   - Phone A presses SOS in airplane mode $\rightarrow$ Phone B relays it.
   - Phone C (or laptop) receives the flushed SOS.
   - On the Command Dashboard, the new SOS appears at the top of the feed within seconds.
   - Click "Decrypt Medical Record" $\rightarrow$ judge sees medical conditions and medications appear live.
4. **Emergency Alert:**
   - Trigger demo Red Alert $\rightarrow$ phone buzzes with a high-priority heads-up system tray notification.

---

## 8. Finish Checklist

- [ ] `/stats`, `/stats/ai-review`, and `/alerts` endpoints verified with live data & fallbacks.
- [ ] React Command Dashboard builds cleanly (`npm run build`) and connects to the backend.
- [ ] Inline Decrypt Panel in the dashboard decrypts Phase 3 SOS payloads successfully.
- [ ] Local emergency notifications verified on physical hardware.
- [ ] Demo checklist executed; backup recording verified accessible.
- [ ] Update `CLAUDE.md` §9 Status Log with Phase 4 completion.
- [ ] Commit: `phase 4: hazard intelligence, emergency alerting, command dashboard, demo polish`.
