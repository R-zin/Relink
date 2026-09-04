# PHASE 2 — Core App Flows (Internet Path)

> Flutter app: SOS screen (plaintext medical card form + GPS capture + HTTP send + outbox queue), Live Map with toggleable layers, submission flows for reports / shelters / missing persons, alerts & stats placeholder screens, home shell with calm-humanitarian styling.
>
> **You are the Phase 2 agent.** The master plan (`CLAUDE.md`, auto-loaded) is Core Context. Phase 1 is complete — before writing code, read its entry in `CLAUDE.md §9 Status Log` and skim `backend/app/routers/` + `backend/app/schemas.py` for the exact API contract Phase 1 shipped, plus `mobile/lib/storage/` + `mobile/lib/models/mesh_message.dart` for the outbox API you must reuse. **Do not modify backend files** except to report bugs to the user. Your scope is `mobile/` only.
>
> **If anything is ambiguous, an API doesn't match the master plan, or you hit a blocker — STOP and ask the user, then continue with their answer.**

---

## 0. Scope & Definition of Done

**Build:** every screen and service below, talking to a running Phase-1 backend over HTTP. Internet path only — no BLE, no crypto, no push, no external-data screens.

**Out of scope (later phases):** Nearby Connections mesh, flooding, AES-GCM encryption (the SOS form collects the sensitive fields and stores them in the local profile *plaintext for now* — Phase 3 wires encryption), Sachet alerts content, live stats content, FCM, dashboard.

**Done when:**
1. On a physical Android phone with internet: SOS submit appears in `GET /sos`; report/shelter/missing-person submissions appear in their endpoints; each submission is also enqueued to the sqflite outbox (verify via debug outbox viewer).
2. Map screen renders OSM tiles + all three layer types (shelters, hazard reports incl. DBSCAN cluster badges, missing persons), each with type-correct pin colors and "Confirmed by N · verified X ago" captions.
3. Airplane-mode SOS: falls back to outbox-only, shows "queued — will send when connected"; on reconnect the queue flushes automatically.
4. `flutter analyze` clean, `flutter test` green (widget tests for SOS form validation + outbox fallback logic).
5. Master plan §9 Status Log, Phase 2 entry updated.

---

## 1. Prereqs & Run Config

- Flutter stable (same as Phase 1), Android SDK, one physical Android device with USB debugging (maps + GPS are miserable on emulators).
- Backend: Phase 1 must be reachable from the phone. Dev machine + phone on same Wi-Fi → use machine LAN IP; else run against Supabase-hosted DB via the deployed/tunneled backend (`ngrok http 8000` is acceptable for the hackathon). If the backend isn't running or you can't find Phase 1's URL convention, **ask the user**.
- Backend base URL comes from `--dart-define=API_BASE_URL=http://192.168.x.x:8000`. Provide `lib/config.dart` reading `String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:8000')` (emulator default).

## 2. Dependencies (`pubspec.yaml` additions)

```yaml
dependencies:
  flutter_map: ^7.0.0            # verify latest v7-compatible at build time
  latlong2: ^0.9.0
  geolocator: ^13.0.0
  http: ^1.2.0
  connectivity_plus: ^6.0.0
  provider: ^6.1.0
  intl: ^0.19.0
  shared_preferences: ^2.2.0
  # already present from Phase 1: sqflite, path_provider, path, uuid
```

If a pinned major conflicts at resolve time, take the latest compatible and note it in the Status Log.

**AndroidManifest additions** (`mobile/android/app/src/main/AndroidManifest.xml`): `INTERNET`, `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`. Set `minSdkVersion 23` in `android/app/build.gradle` (geolocator + later Nearby Connections need it).

## 3. Architecture (create these files; keep it this simple — no clean-arch ceremony)

```
lib/
├── main.dart                 # ProviderScope wiring + app theme + home shell
├── config.dart               # API_BASE_URL
├── theme.dart                # calm-humanitarian ThemeData (see §4)
├── models/                   # sos_event.dart, report.dart, shelter.dart,
│                             # missing_person.dart, cluster.dart, medical_profile.dart
│                             # (+ mesh_message.dart from Phase 1 — reuse, don't duplicate)
├── services/
│   ├── api_client.dart       # thin http wrapper: base URL, JSON, timeouts, ApiException
│   ├── location_service.dart # geolocator wrapper (permission + one-shot fix)
│   ├── sync_service.dart     # outbox flush on connectivity regain (temporary; Phase 3 extends)
│   └── medical_profile_store.dart  # shared_preferences persistence of the medical card form
├── storage/                  # Phase 1 files — untouched
└── screens/
    ├── home_shell.dart       # bottom nav: SOS · Map · Submit · Alerts · Stats
    ├── sos/
    │   ├── sos_screen.dart           # big SOS button + confirmation state
    │   └── medical_card_form.dart    # plaintext + sensitive field groups
    ├── map/
    │   ├── map_screen.dart           # flutter_map + layer toggles + legend
    │   └── pin_editor.dart           # drag-to-nudge pin before submit
    ├── submit/
    │   ├── submit_hub.dart           # choose Report / Shelter / Missing person
    │   ├── report_form.dart          # type chips + description + GPS + pin nudge
    │   ├── shelter_form.dart         # name + contact + GPS + pin nudge
    │   └── missing_person_form.dart  # name + description + last-seen GPS + pin nudge
    ├── alerts/alerts_screen.dart     # placeholder list, Phase 4 fills
    ├── stats/stats_screen.dart       # placeholder, Phase 4 fills
    └── debug/outbox_viewer.dart      # dev-only: list pending/sent outbox rows
```

State management: `provider` with `ChangeNotifier`s colocated in `screens/` (e.g. `MapController` extends ChangeNotifier). No BLoC, no code generation.

## 4. Theme (`lib/theme.dart`) — Calm Humanitarian, enforced in code

- Base: warm off-white scaffold `#FAF8F5`, warm gray text `#3A3632`.
- Primary accent: soft blue-teal `#2E7E7B` (buttons, active nav, normal CTAs).
- Alarm red `#D64545` used **only** for the SOS button and Severe/Red alert tags — define `alarmRed` in the theme extension and add a `// RESERVED: SOS + severe alerts only` comment; do not use it anywhere else.
- Pins: shelter = teal `#2E7E7B`, hazard = amber `#E8A13A`, missing person = violet `#8B6FC7`, SOS = alarm red.
- Typography: default `TextTheme` with larger body (16 sp), `height: 1.5`; headings weight 600, no all-caps. (Bundling Inter/Nunito fonts is optional; system rounded sans is fine — don't burn time on font files.)
- Copy tone: plain, reassuring ("You're not alone — help gets this message as soon as any nearby phone has signal", not "TRANSMISSION QUEUED").

## 5. SOS Flow (`screens/sos/`)

1. **Medical card form** (`medical_card_form.dart`) — two sections, matching master plan §5:
   - *"Shared openly with responders"*: name, blood group (dropdown: A+/A-/B+/B-/AB+/AB-/O+/O-), allergies (free text, comma-split), emergency contact name + phone.
   - *"Encrypted — only responders can read"*: medical conditions/notes, current medications, insurance provider + policy number.
   - Persist locally via `medical_profile_store.dart` (shared_preferences, JSON blob). Pre-populate on every open. The sensitive half is stored plaintext **for now** — add a `// TODO(phase3): encrypt with AES-GCM before it leaves the device` marker.
2. **SOS screen** (`sos_screen.dart`):
   - One large alarm-red SOS button (min 160×160, circular, gentle pulse animation at ~1 Hz — the one place motion is allowed to feel urgent).
   - Tap → confirmation sheet: shows captured GPS (or "locating…"), medical-card completeness indicator ("Medical card ✓ attached" / "Add medical info" link), and **"Send SOS"** / cancel. This confirm step is intentional — accidental presses are the top false-SOS source.
   - On send: build the mesh message envelope (`type: SOS, priority: high, ttl: 6, id: uuid v4, timestamp: now`) with `payload` = `{lat, lng, plaintext_medical}` and `encrypted_payload: null` for now; `origin_device_id` from a persisted per-install UUID (create in `config.dart`-adjacent util: generate once into shared_preferences).
   - **Always** `OutboxDao.enqueue(...)` first (the outbox is the source of truth — Phase 3's sync engine will own flushing). Then attempt immediate send via `SyncService.flushOnce()` if connectivity is up.
   - Confirmation state: banner "SOS sent to responders" on HTTP 2xx; "No signal — your SOS is saved and will send automatically when any connection returns" when queued offline. No red-on-red panic styling; keep it calm.

## 6. Submission Flows (`screens/submit/`)

Shared pattern for all three forms:
1. On open, `LocationService.getCurrent()` → one-shot GPS fix (timeout 8 s, `LocationAccuracy.high`); show "Locating…" state; on failure allow manual pin placement.
2. Show a small `flutter_map` preview with a draggable marker (**pin_editor.dart**) — the user nudges the pin before submit (master-plan requirement: auto-capture + manual nudge).
3. Submit → mesh message envelope of the matching `type` (`REPORT`/`SHELTER`/`MISSING_PERSON`, priority normal) → enqueue → attempt immediate flush → toast/snackbar "Submitted ✓" or "Saved — will send when connected".
4. Report form: type selector chips = Flooded/blocked road (`obstacle`), Disease outbreak (`disease`), Water contamination (`water`) — map labels to API `type` values; free-text description (max 500 chars).
5. Shelter form: name, contact info (optional), GPS.
6. Missing-person form: name, description (clothing/age/identifying marks), last-seen GPS.
7. Client-side validation: required fields non-empty, lat/lng present before enabling submit.

## 7. Map Screen (`screens/map/map_screen.dart`)

- `flutter_map` + OSM tile layer (`https://tile.openstreetmap.org/{z}/{x}/{y}.png`, `userAgentPackageName: 'in.relink.mobile'`). Center on device location, fallback to seeded demo region (Phase 1 Status Log names it; default Kochi 9.98, 76.28).
- **Layer toggles** (top-right filter chips, all on by default): Shelters · Hazards · Missing persons · *(Flood extent — Phase 4 adds the layer; leave the chip stubbed out and disabled with a TODO)*.
- **Hazards layer** consumes `GET /reports/clusters`: each cluster = one marker at its centroid with a **count badge** (report_count) and type-colored pin; tapping opens a bottom sheet listing sample description, "Confirmed by {total_confirmations} · verified {relative(last_confirmed_at)}", and a **"Confirm — I see this too"** button → `POST /reports/{id}/confirm` on the cluster's highest-confirmation member, then refresh. Noise points render as individual small markers.
- **Shelters layer** consumes `GET /shelters?lat&lng`: teal pins, bottom sheet with name, contact, "Confirmed by N · verified X ago", same confirm button → `POST /shelters/{id}/confirm`.
- **Missing-persons layer** consumes `GET /missing-persons/search?lat&lng&radius_km=50`: violet pins at last-seen, bottom sheet with name + description + reported time.
- Relative time helper ("20 min ago", "3 h ago") — small util, used everywhere.
- Pull-to-refresh refetches all enabled layers. Loading + error states must be plain-language ("Couldn't reach the server — showing what we have").

## 8. Sync Service (`services/sync_service.dart`) — temporary internet-only version

- Listens to `connectivity_plus` stream; on transition to online → `flush()`.
- `flush()`: `OutboxDao.pending()` (already SOS-first per Phase 1) → for each: `markSending` → POST to the endpoint for its type (`/sos`, `/reports`, `/shelters`, `/missing-persons` — map `MeshMessage.type` → endpoint; payload = merge of envelope fields + `payload` map, e.g. SOS body = `{device_id: origin_device_id, lat, lng, plaintext_medical, encrypted_medical: encrypted_payload}`) → 2xx: `markSent`; network error: `markFailed` and stop (avoid hot-looping); 4xx: log + `markFailed` (skip permanently after 5 retries — Phase 3 may refine).
- Debounce: at most one flush in flight; 2 s trailing debounce on connectivity events.
- **Phase 3 replaces the transport half of this with mesh-aware logic — keep the class small and replaceable.** Comment that at the top of the file.

## 9. Placeholders & Debug

- `alerts_screen.dart`: app bar "Alerts", body = empty-state copy ("Official alerts for your region will appear here") + `// TODO(phase4): Sachet RSS feed`.
- `stats_screen.dart`: same pattern + `// TODO(phase4): live hazard metrics + AI review`.
- Debug outbox viewer (`screens/debug/outbox_viewer.dart`): reachable via long-press on the home-shell app bar title; lists outbox rows (type, status, retry_count, created_at) with a "Flush now" button calling `SyncService.flush()`. Essential for demo debugging — keep it.

## 10. Testing

- Widget test: SOS screen — tap SOS → confirmation sheet appears; with empty required medical fields the "Add medical info" link shows; send calls the expected API path (mock `ApiClient`).
- Unit test: `SyncService` — given outbox with SOS + REPORT and a mock HTTP layer: SOS posts first; HTTP failure leaves both pending with incremented retry counts; success marks sent.
- Unit test: envelope mapping — each `MeshMessage.type` maps to the correct endpoint + body shape (golden-map assertions).
- `flutter analyze` clean; run on a physical device at least once (map + GPS on emulator don't count).

## 11. Known Gotchas

- **Android 12+ location**: request `ACCESS_FINE_LOCATION` at runtime via geolocator's `requestPermission()`; handle "denied forever" with a link to app settings, not a dead end.
- `flutter_map` v7 API changed (e.g. `MapOptions(initialCenter:…)`, `Marker(rotate:…)`) — follow the installed version's README, don't copy v6 snippets from memory. If the API differs from what you expect, check the package's example dir.
- OSM tiles **require** a `userAgentPackageName` or tile requests get throttled/blocked.
- GPS indoors often times out — the manual pin fallback in §6 is mandatory, not nice-to-have.
- `10.0.2.2` reaches the host from the emulator only; physical devices need the LAN IP or tunnel — get the phone onto the same network early in the session.
- Don't request background location — not needed, and Play policy review isn't a hackathon problem worth inviting.
- Keep the SOS button reachable: it must be the center item of the bottom nav, visually dominant, one tap from anywhere.

## 12. Finish Checklist

- [ ] All four flows verified end-to-end on a physical device against the running backend (curl the GET endpoints to confirm rows landed).
- [ ] Airplane-mode queue → reconnect → auto-flush verified on device.
- [ ] Map shows all three layers with confirm counts + relative verification times; confirm buttons round-trip.
- [ ] `flutter analyze` + `flutter test` green.
- [ ] **Update `CLAUDE.md` §9 Status Log, Phase 2 entry** — 5–10 lines: screens/services built, exact `--dart-define` run command, any API-shape mismatches found in Phase 1 (and how resolved), deviations, what's left for Phase 3 (mesh + crypto integration points: `SyncService` seam, medical form sensitive fields, `MeshMessage.encrypted_payload`).
- [ ] Commit: `phase 2: core app flows over internet path`.
