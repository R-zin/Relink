# Phase 2 — Core App Flows (internet path only)

> Read the master plan (`CLAUDE.md`) first — Sections 1–7 are your ground truth (especially Section 2 UI direction, Section 3 features, Section 7 data contract), plus the Phase 1 entry in the Status Log (Section 9). This file is your **only** scope. Do not read or touch other phase files.

## Scope

Flutter screens wired directly to the Phase 1 backend over HTTP. No mesh, no encryption yet — medical card fields exist in the UI but are sent as plain HTTP for now (they'll be encrypted in Phase 3).

### Build

**Flutter app (`mobile/`), per the "Calm Humanitarian" direction (Section 2):**
- **SOS button screen** — prominent SOS action (the only alarm-red element in the app), confirmation state, internet-first send to `POST /sos`. Medical card fields captured on this flow per Section 5: plaintext (name, blood group, allergies, emergency contact) + sensitive (conditions, medications, insurance) — send all as plain HTTP for now. GPS auto-capture via `geolocator` with manual pin nudge before submit.
- **Live Map screen** (Section 3.2) — `flutter_map` (OpenStreetMap) with toggleable layers and Section 2 pin colors:
  - shelters (teal), hazards/flooded roads (amber), missing persons / last-seen (violet).
  - Each pin shows its trust signal: confirm count + last-verified timestamp ("Confirmed by 12 · verified 20 min ago").
  - Tap-to-confirm action wired to `POST /reports/{id}/confirm` and `POST /shelters/{id}/confirm`.
  - Hazard layer reads from `GET /reports/clusters` (server-clustered), not raw reports.
  - The GFM satellite flood-extent layer is **not** in this phase — it arrives with the backend integration in Phase 4 and the dashboard in Phase 5; leave a layer-toggle slot for it if cheap, but do not build the data path.
- **Submission flows** — hazard report (`POST /reports`), shelter (`POST /shelters`), missing person (`POST /missing-persons`, last-seen location + description only). All get GPS auto-capture + pin nudge.
- All network access goes through a single API client module pointing at the Phase 1 backend base URL.

## Do not touch

Nearby Connections / mesh, crypto, dashboard, stats, alerts, FCM push, external hazard APIs.

## Definition of done

- A phone with internet can submit an SOS, a hazard report, and a shelter, and see them reflected via the backend.
- The map shows all three layer types with confirm counts, and confirming from the map updates the counts.

## Before you finish

Update the Phase 2 entry in the master plan Status Log (`CLAUDE.md` Section 9): what you built, deviations and why, what's broken/incomplete.
