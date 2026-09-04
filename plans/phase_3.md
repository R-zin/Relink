# Phase 3 — Offline Path: Mesh + Medical Card Crypto

> Read the master plan (`CLAUDE.md`) first — Sections 1–7 are your ground truth (especially Section 5 crypto, Section 7 message schema + flooding algorithm), plus Phase 1–2 entries in the Status Log (Section 9). This file is your **only** scope. Do not read or touch other phase files.

**This is the highest-risk phase — isolate it, don't split focus.**

**Requires:** 2+ physical Android devices — cannot be meaningfully tested on emulators.

## Scope

Nearby Connections integration, the flooding algorithm, sync-on-reconnect, and AES-GCM medical-card encryption with the dashboard decrypt path.

### Build

**Mesh layer (`mobile/lib/mesh/`):**
- Google Nearby Connections via the `nearby_connections` plugin, `P2P_CLUSTER` strategy, Android only. Do NOT hand-roll raw GATT mesh routing.
- Implement the flooding algorithm from master plan Section 7 exactly:
  1. On receive: check local `seen_ids` set (persisted via Phase 1's sqflite table, TTL-expired after 24h).
  2. If new: store locally, surface to UI / queue for backend sync.
  3. If internet available: POST to backend immediately, mark delivered.
  4. If no internet and `ttl > 0`: decrement TTL, rebroadcast to all connected peers except sender.
  5. SOS messages queue and send ahead of REPORT/SHELTER types.
- Persona behavior (Section 1): victim profile = triggered burst on SOS press; survivor profile = active mesh participation.
- Messages use the Section 7 mesh message schema verbatim (uuid v4 id, ttl starting at 6, priority field).

**Sync-on-reconnect (`mobile/lib/storage/` + mesh):**
- Connectivity listener: when internet returns, flush the outbox in priority order (SOS first), mark delivered on success. Backend already de-dupes by message id (Phase 1), so re-sends are safe.

**Crypto (`mobile/lib/crypto/`):**
- AES-256-GCM via the Dart `cryptography` (or `encrypt`) package — symmetric, per Section 5. Do not use `sodium_libs`.
- Sensitive medical card fields (conditions, medications, insurance) are encrypted client-side with the pre-shared `MEDICAL_CARD_DEMO_KEY` and placed in the SOS message's `encrypted_payload` (base64) **before** it enters the mesh. Plaintext fields stay plaintext.
- Key comes from app build config, never hardcoded in source.

**Decrypt path (dashboard side, minimal):**
- A small decrypt utility/route backing `POST /medical/decrypt` (responder-only, demo auth) that decrypts `encrypted_payload` with the same demo key, decrypt-on-view, never persisted decrypted. A minimal standalone page/script is acceptable for this phase; the polished dashboard view comes in Phase 5 — coordinate only through the endpoint contract, don't build the Phase 5 UI.

## Do not touch

Stats, alerts, AI review, external hazard APIs, dashboard polish, FCM push. Don't modify Phase 1/2 code except to fix bugs blocking this phase (log any such fix).

## Definition of done

Two phones in airplane mode: one presses SOS, the other relays it; a third device (or the same one) with internet flushes it to the backend; the responder decrypt path reveals the sensitive fields.

**Record this working end-to-end at least once as a backup video** — live BLE demos are inherently flaky and you will not get a second take in front of judges. State in the Status Log where the recording is stored.

## Before you finish

Update the Phase 3 entry in the master plan Status Log (`CLAUDE.md` Section 9): what you built, deviations and why, what's broken/incomplete, and the backup-video location.
