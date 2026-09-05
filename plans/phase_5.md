# PHASE 5 — Interactive Live App Audit, Bug-Fixing & Feature Refactoring

> **You are the Phase 5 Audit & Refactor Agent.** Your job is to interactively drive the live app on physical phones, verify every feature end-to-end against the backend and dashboard, fix bugs you find, and refactor anything that doesn't meet the spec. You work **with the user**, not autonomously — they connect the phones and perform taps when UI automation hits a wall.
>
> **This phase is INTERACTIVE by design.** The user is your co-pilot. They will connect 1 or 2 phones as you request, answer questions, and perform manual taps when ADB can't reach something (permission dialogs, GPS pin nudges). **If you run into any issue, any ambiguity, or any contract-level decision — STOP and ask the user, then continue with their answer.** Never guess on schemas, API shapes, crypto formats, or the message protocol.

---

## 0. Read This First — Required Context (in order)

Before you write a single line of code or run a single test, read these files. They are your ground truth. **Do not skip any.**

| # | File | Why you need it |
|---|------|-----------------|
| 1 | `CLAUDE.md` (repo root, auto-loaded) | The master plan. §1 design philosophy, §2 UI/UX direction, §3 feature set, §4 architecture, §5 medical card & encryption, §6 tech stack, §7 **data contract (DO NOT redefine)**, §8 phase overview, §9 **Status Log (Phases 1–4 — read every entry)**, §10 demo-day notes. |
| 2 | `plans/phase_4_handoff.md` | The bridge from Phase 3 → 4. Repo/env ground truth (Postgres, venv, Flutter SDK, ADB reverse gotcha, env-var gotcha, stale-process gotcha), test baselines (43 backend / 37 Flutter), what exists, hard rules, backlog. **Still authoritative for environment setup.** |
| 3 | `plans/phase_4.md` | What Phase 4 actually built — dashboard, telemetry services, alerts, stats, AI review, notifications. You need to know what *should* exist to verify it *does* exist and works. |
| 4 | `CLAUDE.md` §9 Status Log — **Phase 4 entry** (the long one at the bottom) | What Phase 4 actually delivered, deviations (Tailwind v4, rule-based AI review, dashboard env-free defaults), and the **Incomplete** list (FCM background push, Phase 3 backup mesh video, offline tile pre-caching). |

**Then explore the actual code** to understand what you're auditing:

- `backend/app/routers/` — all endpoint handlers (`sos.py`, `reports.py`, `missing_persons.py`, `shelters.py`, `medical.py`, `stats.py`, `alerts.py`)
- `backend/app/services/` — `clustering.py`, `medical_crypto.py`, `stats_service.py`, `ai_review.py`, `alerts_service.py`, `external_apis/` (glofas, weather, dams, gfm, marine, eonet)
- `backend/app/jobs/` — APScheduler pollers
- `mobile/lib/` — `main.dart`, `mesh/` (nearby_transport, mesh_manager, mesh_message_codec, seen_store), `crypto/` (demo_key, medical_crypto), `screens/` (sos, map, submit, alerts, stats), `storage/` (outbox, community_store), `services/` (notification_service, alert_poller, sync_service)
- `dashboard/src/` — `App.jsx`, `api.js`, `components/` (Header, SosFeed, MapCanvas, DecryptModal, StatsGrid, ChartsPanel, AiReviewBanner, AlertsList)

---

## 1. Environment & Tooling Setup (verify before anything else)

You have full access to ADB, Bash, PowerShell, Flutter, and can take screenshots. Set this up and **verify each piece works** before starting the audit.

### 1.1 Paths & tools

```bash
# ADB — add to PATH per Bash call (not persistent)
export PATH="$PATH:/c/Users/lenovo/AppData/Local/Android/Sdk/platform-tools"

# Flutter — NOT on Git Bash PATH, use explicit path
/c/flutter/bin/flutter --version

# Backend venv (Windows)
cd backend && .venv/Scripts/activate

# Backend run
uvicorn app.main:app --host 0.0.0.0 --port 8000

# Dashboard dev server
cd dashboard && npm run dev   # → http://localhost:5173
```

### 1.2 Known devices (from prior sessions — re-verify with `adb devices`)

| Device | ADB Serial | Notes |
|--------|-----------|-------|
| OnePlus Nord CE4 | `fc76dcff` | Primary test device this session |
| Samsung Galaxy A35 | `RZCX60GQZEB` | Phase 2/3 verified |
| Samsung S23 | `RZCX50LS3AV` | Available for mesh tests |

**Package:** `in.relink.relink_mobile`
**APK:** `mobile/build/app/outputs/flutter-apk/app-debug.apk`

### 1.3 The ADB reverse gotcha (critical)

```
adb -s <serial> reverse tcp:8000 tcp:8000
```

- **This dies whenever USB drops, the app is uninstalled, or the phone reconnects.** Re-run it after ANY reconnect.
- The app is built with `--dart-define=API_BASE_URL=http://localhost:8000` — it reaches the backend **through the USB cable** via this tunnel. No cable = no backend (unless you use LAN-IP dart-define + open Windows Firewall TCP 8000, which needs admin).
- Verify the tunnel works: `adb -s <serial> shell "curl -s -m 5 http://localhost:8000/health"` → expect `{"status":"ok"}`.

### 1.4 Build defines (baked into the current APK)

The current debug APK was built with:

```
--dart-define=API_BASE_URL=http://localhost:8000
--dart-define=MEDICAL_CARD_DEMO_KEY=AvhVqE/lK/Jv/o5kalpkYjBKHJSxolRrw9j52m1qqCQ=
```

**If you rebuild the app, you MUST pass both defines** or the app will (a) not reach the backend and (b) fall back to plaintext medical cards (crypto disabled). The AES-GCM key must match `backend/.env`'s `MEDICAL_CARD_DEMO_KEY` exactly.

### 1.5 Backend `.env` (gitignored — do NOT commit)

Contains `DATABASE_URL`, `MEDICAL_CARD_DEMO_KEY`, `DECRYPT_DEMO_PASS=relink-demo`. `LLM_API_KEY` is **empty** — the rule-based AI review path is the ACTIVE one. This is intentional.

### 1.6 Screenshot pipeline (for visual verification)

```bash
adb -s <serial> exec-out screencap -p > /tmp/screen.png
cp /tmp/screen.png /c/Users/lenovo/relink_audit_screen.png
# then use the Read tool on the Windows path to view it
```

### 1.7 Logcat streaming (for watching app behavior)

```bash
# Stream app logs to a file you can tail
adb -s <serial> logcat -v time > /tmp/relink_logcat.txt &
# Filter for app-relevant lines
adb -s <serial> logcat -d -v time | grep -iE "flutter|ApiClient|AlertPoller|SyncService|MeshManager|notification"
```

### 1.8 OneDrive build gotcha (if you rebuild)

The project lives under `OneDrive\Desktop`. OneDrive Files On-Demand can dehydrate freshly-compiled `.class` files into cloud placeholders mid-build ("not a regular file"). If a build fails with snapshot/snapshotter errors:

```powershell
# Pin the build dir to keep it hydrated
attrib +P -U "C:\Users\lenovo\OneDrive\Desktop\Relink-2\Relink\mobile\build" /S /D
```

Then `cd mobile/android && ./gradlew --stop`, `rm -rf mobile/build`, and rebuild.

---

## 2. Audit Philosophy & Rules

### 2.1 Hard rules (do NOT violate)

1. **Never redefine the data contract** (CLAUDE.md §7) — mesh schema, endpoint shapes, models, env vars. If you think it's wrong, **ask the user**.
2. **Never block an emergency beacon** — crypto/notification/mesh failures must degrade gracefully. An SOS must ALWAYS send, even if encryption fails (falls back to plaintext) or mesh is down (queues in outbox).
3. **Stay in scope unless told otherwise** — Phase 5 is audit + bug-fix + refactor of the *existing* app. If you find a bug that requires changing another phase's core architecture, **report it to the user first**, don't silently rewrite.
4. **Ask the user on contract-level ambiguity** — schemas, API shapes, crypto, message protocol. Never guess.
5. **`backend/.env` is gitignored — NEVER commit it.** It contains the database password and the medical card demo key.
6. **Commit trailer:** end every commit message with `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`.
7. **Real-time values only, no demo data** — this was the user's explicit instruction for Phase 4 and it carries forward. Don't seed fake data to make something look working; if data is missing, fix the pipeline.

### 2.2 Interactive workflow

- **You drive, the user assists.** Use ADB to tap, swipe, type, and screenshot. When you hit something ADB can't do (a system permission dialog, a GPS pin drag that needs precision, confirming a notification appeared in the tray), **ask the user to do it on the phone while you watch logcat.**
- **Tell the user what you need.** "Please connect the second phone" / "Please tap 'Allow' on the location permission dialog" / "Please put Phone A in airplane mode with Bluetooth ON." Be specific about which device (by serial or name) and what you need.
- **Verify against the backend, not just the UI.** After the app does something, `curl` the backend to confirm the row actually landed. The UI lying is a bug; the backend is ground truth.
- **Watch logcat while you drive.** Many bugs (failed HTTP, crypto errors, mesh drops) only show in logs, not on screen.

### 2.3 Definition of "verified" for a feature

A feature is **verified** only when ALL of these are true:
1. The UI on the phone shows the expected result (screenshot).
2. The backend reflects the change (curl the relevant endpoint).
3. Logcat shows no errors for that flow.
4. If it's a cross-device feature (mesh, relay), the second device ALSO shows the expected result.

If any of these fail, it's a **bug** — log it, fix it, re-verify.

---

## 3. Feature Audit Checklist

Work through this checklist with the user. For each feature: drive it on-device, verify backend state, screenshot the result, and mark it **PASS / FAIL / NEEDS USER ACTION**. For every FAIL, file a bug (see §4) and fix it before moving on, unless the user says to defer.

### 3.1 Home shell & navigation

- [ ] App launches without crash; home screen renders (screenshot).
- [ ] SOS button is the center nav action and uses the reserved alarm-red (§2: red is ONLY for SOS + Severe alerts — verify no other element uses it).
- [ ] Bottom nav / app bar navigates to: SOS, Map, Submit, Alerts, Stats.
- [ ] Mesh radar pill in the AppBar shows current peer count (e.g. `🟢 N Peers Nearby`) — verify it updates when a second phone connects.

### 3.2 SOS flow (internet path)

- [ ] SOS button opens confirmation sheet.
- [ ] Medical card form collects: name, blood group, allergies, emergency contact (plaintext) + medical conditions, medications, insurance (to be encrypted).
- [ ] On send with internet: `curl http://localhost:8000/sos` shows a NEW row with correct `device_id`, `lat`/`lng`, `plaintext_medical`, and a non-null `encrypted_medical`.
- [ ] Logcat shows `[SyncService] Posting msg ... to /sos` then `Successfully sent`.
- [ ] The new SOS appears in the **dashboard** SOS feed within ~12s (dashboard polls every 12s).

### 3.3 SOS offline queue → reconnect auto-flush

- [ ] Put phone in airplane mode (ask user, or `adb shell cmd connectivity airplane-mode enable` — verify it doesn't kill ADB; if it does, ask user to toggle manually).
- [ ] Send SOS → confirm it lands in the outbox (debug outbox viewer: long-press app-bar title) and does NOT error.
- [ ] Re-enable connectivity → logcat shows SyncService flushing the queue; `curl /sos` shows the row.
- [ ] SOS is sent **ahead of** any queued reports (priority ordering).

### 3.4 Live map

- [ ] Map renders OSM tiles (needs internet for tiles unless pre-cached).
- [ ] Layers present and toggleable: shelters (teal), hazard clusters (amber), missing persons (violet).
- [ ] Each marker shows trust signal (confirm count + last-verified).
- [ ] Tapping a hazard cluster's confirm button → `curl /reports/clusters` shows `total_confirmations` incremented.
- [ ] GPS auto-captures on the device (verify a real lat/lng, not 0,0 or null).

### 3.5 Submit flows (report / shelter / missing person)

- [ ] Submit hub offers all three types.
- [ ] Each form captures GPS + allows pin nudge (pin nudge may need user manual drag).
- [ ] Hazard report → `curl /reports` (or `/reports/clusters` after DBSCAN) shows it.
- [ ] Shelter → `curl /shelters` shows it.
- [ ] Missing person → `curl /missing-persons/search?q=<name>` finds it.
- [ ] **Clean up test rows after verification** (don't leave junk in the DB — prior sessions did this).

### 3.6 Alerts screen

- [ ] Alerts screen renders official NDMA Sachet alerts from `GET /alerts?state=kerala`.
- [ ] Alert text is verbatim official copy (not paraphrased).
- [ ] Severity tags render correctly; Red/Orange use the reserved alarm-red badge.
- [ ] If no live alert, verify the screen shows a sensible empty state (not a crash).

### 3.7 Stats screen

- [ ] AI review card renders with risk tag badge (Low=teal, Moderate, High=amber, Severe=red) + `source: rule-based` indicator.
- [ ] River discharge chart renders from GloFAS 7-day forecast (`fl_chart`).
- [ ] Rainfall card shows 24h total.
- [ ] Dams list shows fullness bars; a dam above danger level is flagged red (e.g. Mullaperiyar).
- [ ] Data attribution pills present ("GloFAS", "IMD", "CWC Dams").
- [ ] `curl http://localhost:8000/stats?region=Kochi` returns `metrics.glofas.stale:false` and real numbers.

### 3.8 Emergency notification channel (HIGH PRIORITY — needs 2 steps)

- [ ] **Trigger a test Red alert:** `POST /alerts/test-alert` (or insert a Red alert into `alerts_cache`).
- [ ] Within the AlertPoller's poll interval, the phone should show a **heads-up high-priority OS notification** (system tray banner with sound/vibration).
- [ ] **This requires user confirmation** — ADB can't confirm a heads-up banner appeared visually. Ask the user: "Did you see and hear a notification?" Screenshot the notification tray: `adb -s <serial> exec-out screencap -p` after pulling down the shade (or ask user to).
- [ ] Verify the notification channel exists: `adb -s <serial> shell dumpsys notification | grep -i relink`.

### 3.9 Medical card encryption (SOS + dashboard decrypt)

- [ ] Send an SOS with full medical card from the phone.
- [ ] `curl /sos` → the row's `encrypted_medical` is non-null base64.
- [ ] In the **dashboard**, click the new SOS card → "Decrypt Medical Record" → sensitive fields (conditions, medications, insurance) render inline.
- [ ] "Decrypted on view — never stored" indicator shows.
- [ ] If decrypt fails with wrong-key error, the phone build is missing the `MEDICAL_CARD_DEMO_KEY` dart-define — rebuild with it (§1.4).

### 3.10 BLE mesh (requires 2 phones — ask user to connect both)

**Ask the user to connect the second phone before starting this section.**

- [ ] Both phones: `adb reverse tcp:8000 tcp:8000` set on BOTH serials.
- [ ] Both phones show `🟢 1 Peer Nearby` in the mesh radar pill.
- [ ] **Gossip test:** Phone A submits a hazard report (offline, airplane mode + BT ON) → within seconds, Phone B's map/community feed shows it with a `📡 via Mesh (N hops)` badge.
- [ ] **SOS relay test:** Phone A (airplane mode + BT ON) sends SOS → Phone B receives it over mesh → Phone B (online) flushes to backend → `curl /sos` shows the row with Phone A's `origin_device_id`.
- [ ] **Dedup test:** same message isn't processed twice (SeenStore).
- [ ] Verify `in.relink.mesh` appears in Nearby Connections scanning clients: `adb -s <serial> shell dumpsys activity service com.google.android.gms.nearby | grep -i relink` (or watch logcat for NearbyMediums).

### 3.11 Dashboard (verify live render + all panels)

- [ ] Dashboard loads at `http://localhost:5173`, no console errors.
- [ ] Header: UTC clock ticks, `BACKEND: LIVE` (not DOWN), active SOS count > 0.
- [ ] Center map: all layers render (SOS pulsing red, clusters amber, shelters teal, missing violet, GFM flood polygon with observation timestamp labeled "not live").
- [ ] Left rail: SOS feed populated, each card shows plaintext medical + decrypt button.
- [ ] Right rail: AI review card, river/rainfall/dams telemetry, NDMA alerts verbatim.
- [ ] 1-click decrypt works (§3.9).
- [ ] Screenshot the full console for the record.

---

## 4. Bug & Refactor Workflow

When you find a bug:

1. **Reproduce it** reliably and capture evidence (screenshot + logcat snippet + curl output).
2. **Diagnose the root cause** — read the relevant code, don't guess.
3. **Report to the user** before fixing IF: it touches the data contract, it's a large refactor, or the fix has trade-offs. For small, obvious bug fixes (a null check, a wrong endpoint path, a missing await), fix directly and report what you did.
4. **Fix it** following existing code style (match comment density, naming, idiom).
5. **Re-verify** the feature end-to-end (UI + backend + logcat).
6. **Run the test suites** to make sure you didn't regress:
   - Backend: `cd backend && .venv/Scripts/python -m pytest tests -q` → baseline **43 passed**
   - Flutter: `cd mobile && /c/flutter/bin/flutter test` → baseline **37 passed**
   - Flutter analyze: `/c/flutter/bin/flutter analyze` → baseline **0 issues**
   - Dashboard: `cd dashboard && npm run build` → clean (chunk-size advisory is OK)
7. **If you touch crypto layout**, regenerate the golden vector: `mobile/tool/gen_golden_vector.dart` → `backend/tests/golden_vector.json`.

### Refactor candidates (known from prior sessions — verify and address)

- **`medical_crypto._load_key()`** reads `os.environ` directly, not pydantic settings — if `/medical/decrypt` returns "server is not configured with MEDICAL_CARD_DEMO_KEY", this is why (see `phase_4_handoff.md` §1 ⚠️). Consider switching to `get_settings()`.
- **FCM background push** is NOT wired (foreground poll + local notification only). If the user wants background push, that's a scoped addition — ask first.
- **Rule-based AI review** is the active path (`LLM_API_KEY` empty). If the user provides an LLM key, the LLM branch exists but is **untested** — test it before enabling.
- Any UI that doesn't match the "Calm Humanitarian" direction (§2) — e.g. alarm-red used anywhere except SOS + Severe alerts.

---

## 5. Known Environment Traps (from prior sessions — don't get bitten)

1. **ADB reverse dies on reconnect/uninstall** — re-run per device after any reconnect (§1.3).
2. **OneDrive dehydrates build files** — pin `mobile/build` with `attrib +P -U` before rebuilding (§1.8).
3. **Stale uvicorn orphans** — only ONE uvicorn should serve port 8000; kill orphans from old repo paths (`...\Desktop\Relink`, not `Relink-2`) before testing.
4. **Windows Firewall blocks phone-over-Wi-Fi** — use `adb reverse` (USB) or open TCP 8000 (admin) + LAN-IP dart-define for untethered.
5. **`flutter` not on Git Bash PATH** — use `/c/flutter/bin/flutter`.
6. **`flutter install` doesn't take `--dart-define`** — build the APK with defines, then `adb install`.
7. **`INSTALL_FAILED_UPDATE_INCOMPATIBLE`** — old debug signature; `adb uninstall` first, then install.
8. **sqflite_ffi test DBs persist across runs** — `freshDb`/`freshDao` already `deleteDatabase` first; if you add tests, do the same.

---

## 6. Demo-Day Backlog (user action — remind, don't do silently)

From CLAUDE.md §10 + Phase 4 Status Log "Incomplete" list:

- [ ] **Record the Phase 3 backup mesh video** (`demo/phase3_mesh_demo.mp4`) — needs 2 physical phones; REQUIRED for demo day in case live Bluetooth flakes.
- [ ] **Pre-cache offline map tiles** for the venue/demo region.
- [ ] **Test FCM background push on a killed app** IF FCM ever gets wired.
- [ ] Seed the backend with mock historical data so the dashboard looks populated, then trigger one live report during the demo.

---

## 7. Finish Checklist

- [ ] Every feature in §3 marked PASS (or explicitly deferred by user with reason logged).
- [ ] All found bugs fixed and re-verified, OR logged as known issues with user sign-off.
- [ ] All test suites green (backend 43+, Flutter 37+, analyze clean, dashboard build clean).
- [ ] Test rows cleaned out of the database.
- [ ] **`CLAUDE.md` §9 Status Log updated with a Phase 5 entry**: what you audited, bugs found + fixed, refactors done, deviations, what's still broken/incomplete.
- [ ] Any uncommitted fixes (e.g. the `build.gradle.kts` desugaring fix from the prior session) committed.
- [ ] Commit(s) with clear messages + the required trailer.

---

## 8. How To Start (your first moves)

1. Read the required context (§0) — master plan, handoff, phase 4, Status Log Phase 4 entry.
2. Verify the environment (§1): backend running + healthy, dashboard running, ADB sees the phone(s), tunnel set, app installed.
3. Ask the user: **"How many phones do you have connected right now, and which features do you want to prioritize?"** Then work the checklist (§3) in that priority order, interactively.
4. Keep the user informed as you go — what you're testing, what passed, what failed, what you need them to do.
