# Phase 5 — Dashboard + Demo Prep

> Read the master plan (`CLAUDE.md`) first — Sections 1–7 are your ground truth (especially Section 2 UI direction, Section 7 endpoints + data sources, Section 10 demo-day notes), plus **all** prior Status Log entries (Section 9) — earlier phases recorded what's broken/incomplete for you. This file is your **only** scope. Do not read or touch other phase files.

## Scope

React command dashboard (responder-facing), seeded demo data, and demo-day preparation.

### Build

**Dashboard (`dashboard/`, React + Vite + Leaflet + Recharts):**
- Same "Calm Humanitarian" palette/tone as the app (Section 2), but denser data tables are fine — audience is responders.
- **Live map (Leaflet):** toggleable layers mirroring the mobile app — shelters (teal), hazards (amber, from `GET /reports/clusters`), missing persons (violet), SOS events — plus the **GFM satellite-observed flood-extent layer** from Phase 4, labeled with its observation time ("latest available observation", never real-time).
- **Trust signals:** every layer shows confirm count + last-verified timestamp; confirm actions hit the confirm endpoints.
- **Charts (Recharts):** stats dashboard fed by `GET /stats` — river discharge (GloFAS), rainfall/wind, marine swell, dam levels (mock), EONET events.
- **AI review panel:** `GET /stats/ai-review` — plain-language summary + risk tag per region.
- **Alerts panel:** `GET /alerts` — Red/Orange NDMA alerts quoted verbatim.
- **Decrypt view:** responder break-glass view calling `POST /medical/decrypt` (demo auth) — decrypt-on-view, never persisted decrypted. Polish the Phase 3 minimal decrypt path into this view; the endpoint contract stays unchanged.
- **Live updates:** Supabase realtime subscriptions so new SOS/reports appear without refresh.

**Seed data:**
- Seed mock historical reports/shelters/missing persons so the dashboard heatmap looks populated on demo day.
- Rehearse triggering one **live** new report during the demo to show real-time propagation.

**Demo prep (Section 10 checklist — execute, don't just read):**
- Confirm 2–3 physical Android phones with the app installed and mesh verified working **before** demo day.
- Pre-cache offline map tiles for the venue/demo region.
- Verify the Phase 3 backup mesh video is recorded and easy to reach.
- Re-test FCM push on a genuinely backgrounded/killed app.
- For the flood demo: GloFAS forecast/risk alongside the GFM observed-extent layer, with the observation time clearly labeled.
- Social signal monitoring (Section 3, optional) only if everything above is solid and verified.

## Do not touch

Anything in Phases 1–4 unless fixing a bug blocking this phase (log any such fix in the Status Log).

## Definition of done

- Dashboard shows seeded historical data + live updates, including the GFM observed-flood layer, confirm counts, charts, alerts panel, AI risk summary for at least one region, and the responder decrypt view.
- A live report submitted from the app appears on the dashboard without refresh.
- Every Section 10 demo-prep checklist item above is executed and its result recorded in the Status Log.

## Before you finish

Update the Phase 5 entry in the master plan Status Log (`CLAUDE.md` Section 9): what you built, deviations and why, what's broken/incomplete, and the state of every demo-prep checklist item.
