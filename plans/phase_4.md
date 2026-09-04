# Phase 4 — Backend Intelligence: Hazard APIs, AI Review, Alerts + FCM Push

> Read the master plan (`CLAUDE.md`) first — Sections 1–7 are your ground truth (especially Section 3.3 alerts, Section 7 external data sources + AI review), plus prior Status Log entries (Section 9). This file is your **only** scope. Do not read or touch other phase files.

This phase is **server- and notification-side only**. The React dashboard, seed data, and demo prep are Phase 5 — do not build them here.

## Scope

External hazard API integration, AI review endpoint, Sachet RSS polling, and FCM system-tray push notifications.

### Build

**External API service (`backend/services/external_apis.py`) + scheduler (`backend/jobs/`):**
- APScheduler inside FastAPI, polling every 10–15 min, results cached into `stats_cache` (Section 7 schema).
- Integrate the Section 7 data-source table exactly:
  - **Open-Meteo GloFAS** — river discharge + forecast risk (m³/s).
  - **Copernicus GFM** — satellite-observed flood extent; store and serve the observation time; never present as real-time. If the GFM product proves impractical to fetch live in hackathon time, cache a recent real observation for the demo region and log the deviation.
  - **Open-Meteo Forecast** — rainfall & wind gusts (cite IMD in UI copy only).
  - **NDMA Sachet CAP/RSS** — official Red/Orange alerts (`SACHET_RSS_URL`). Write the fetch/parse code once and reuse it for both `/alerts` and the FCM trigger.
  - **NASA EONET v3** — global cyclones/events.
  - **Dam fullness** — static/mock cached dataset (India-WRIS live scraping is deferred; note as roadmap).
  - **Open-Meteo Marine** — coastal swell/surge (cite INCOIS in UI copy only).

**Endpoints:**
- `GET /stats` — aggregated hazard metrics from cache.
- `GET /stats/ai-review` — cached AI risk summary.
- `GET /alerts` — cached Sachet alerts for a region.

**AI review (`backend/services/ai_review.py`):**
- Feed the 7 metrics as structured JSON to the LLM with the system prompt from Section 7 (disaster-risk analyst; 3–4 plain-language sentences; single Low/Moderate/High/Severe tag; concrete numbers; no hedging filler).
- GloFAS = forecast/risk evidence; GFM = observed flood extent with observation time.
- Cache into `ai_review_cache`; regenerate every 15–30 min.

**FCM push (Section 3.3):**
- On new Red/Orange Sachet alert, send FCM push with high-priority/heads-up Android channel.
- Notification payload includes region + alert id so tapping deep-links to that region's alert detail.
- Mobile side (`mobile/`): FCM + `flutter_local_notifications` wiring. Background handler must be a top-level/static function (common Flutter gotcha). Add an alerts screen that shows alert detail with NDMA text quoted verbatim (Section 2 copy rules).
- Must appear in the system notification tray with the app backgrounded **and killed** — not just an in-app banner.

## Do not touch

React dashboard, seed data, demo prep/rehearsal (all Phase 5). Mesh/crypto/screens from Phases 1–3 except bug fixes blocking this phase (log any). Social signal monitoring (optional Section 3.5) only if everything above is solid and verified.

## Definition of done

- `/stats`, `/stats/ai-review`, and `/alerts` serve cached live data for at least one region.
- AI risk summary renders for at least one region (correct risk tag + concrete numbers).
- A Red/Orange alert produces an actual notification-tray push on a genuinely backgrounded/killed app, and tapping it opens the alert detail.

## Before you finish

Update the Phase 4 entry in the master plan Status Log (`CLAUDE.md` Section 9): what you built, deviations and why (especially any GFM fallback), what's broken/incomplete.
