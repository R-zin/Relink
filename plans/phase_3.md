# PHASE 3 — Offline Mesh + Medical-Card Crypto

> The differentiator phase. Real Nearby Connections BLE mesh with store-carry-forward flooding, and AES-256-GCM encryption of the SOS medical card's sensitive fields. Highest risk in the project — the backup demo video is a required deliverable, not optional.
>
> **You are the Phase 3 agent.** The master plan (`CLAUDE.md`, auto-loaded) is Core Context — §1 (personas), §4 (architecture), §5 (medical card crypto, *locked*), and the mesh message schema + flooding algorithm in §7 are your contract. Read the Phase 1 & 2 entries in `CLAUDE.md §9 Status Log` first, then skim `mobile/lib/services/sync_service.dart` (you are replacing its transport half), `mobile/lib/storage/`, `mobile/lib/screens/sos/`, and `mobile/lib/models/mesh_message.dart`. Scope is `mobile/` + one small backend endpoint + a throwaway decrypt web page.
>
> **If anything is ambiguous or you hit a blocker (device discovery failures, permission hell, API drift) — STOP and ask the user, then continue with their answer. Do not silently redesign the flooding protocol or the crypto.**

---

## 0. Scope & Definition of Done

**Build:**
1. Nearby Connections wrapper (discovery/advertising, `P2P_CLUSTER`, payload exchange) with lifecycle management.
2. The flooding algorithm from master plan §7, exactly as specified (seen-ids dedupe, TTL, SOS-first ordering, rebroadcast-except-sender).
3. Mesh-aware sync engine replacing Phase 2's internet-only `SyncService`.
4. AES-256-GCM medical-card encryption (Dart `cryptography`), wired into the SOS send path.
5. Backend `POST /medical/decrypt` (break-glass demo endpoint).
6. Standalone decrypt demo page (`dashboard/decrypt.html` — no framework).
7. **Backup demo video recorded** (§8).

**Out of scope:** external APIs, alerts, stats, FCM, the React dashboard proper, any UI redesign of Phase 2 screens (you may add small mesh-status UI affordances only).

**Done when (the Phase 3 demo):** two phones in airplane mode (Bluetooth on) relay an SOS from phone A through phone B; phone C with internet receives it via mesh and flushes it to the backend; the SOS row (with `encrypted_medical`) appears via `GET /sos`; the decrypt page shows the sensitive fields from that ciphertext; and a recording of all of it is saved to `demo/phase3_mesh_demo.mp4`.

---

## 1. Hardware & Environment Prereqs (verify BEFORE writing code)

- 2–3 physical Android phones (BLE mesh is untestable on emulators — master plan §10). One must stay online-capable, two will run airplane mode.
- Bluetooth + Location permissions grantable on all of them; "Nearby devices" permission exists on Android 12+.
- If you have fewer than 2 physical devices available in this session, **ask the user how to proceed** — do not build the mesh blind and hope.
- Backend running and reachable from the online phone (Phase 2's config mechanism).

## 2. Dependencies & Android Manifest

`pubspec.yaml` additions:
```yaml
dependencies:
  nearby_connections: ^4.0.0     # verify latest at build time
  permission_handler: ^11.3.0
  cryptography: ^2.7.0
```

`AndroidManifest.xml` — add alongside Phase 2's permissions, and mind the Android 12/13 split (this is the #1 integration snag):
```xml
<!-- Legacy (API ≤ 30) -->
<uses-permission android:name="android.permission.BLUETOOTH"/>
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN"/>
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE"/>
<uses-permission android:name="android.permission.CHANGE_WIFI_STATE"/>
<!-- Android 12+ (API 31+) -->
<uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE"/>
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>
<uses-permission android:name="android.permission.BLUETOOTH_SCAN"
                 android:usesPermissionFlags="neverForLocation"/>
<!-- Nearby Connections needs location on many versions -->
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
<uses-permission android:name="android.permission.NEARBY_WIFI_DEVICES"
                 android:usesPermissionFlags="neverForLocation"/>
```
Runtime requests via `permission_handler`: request `bluetoothAdvertise`, `bluetoothConnect`, `bluetoothScan`, `locationWhenInUse` together on mesh start; if any is permanently denied, show a plain-language dialog with an "Open settings" button.

## 3. Mesh Layer (`lib/mesh/`)

```
lib/mesh/
├── nearby_transport.dart    # Nearby Connections wrapper (discovery, advertising, connect, send)
├── mesh_manager.dart        # flooding protocol per master plan §7 — the brain
├── seen_store.dart          # seen_ids table access + 24h TTL sweep
└── mesh_message_codec.dart  # MeshMessage <-> bytes (UTF-8 JSON), size guard
```

**`nearby_transport.dart`** — keep it a thin, boring wrapper:
- Constants: `serviceId = "in.relink.mesh"`, `strategy = Strategy.P2P_CLUSTER`, endpoint nickname = device UUID (reuse Phase 2's persisted install UUID).
- API: `Future<void> start()`, `Future<void> stop()`, `Stream<PeerEvent> peers`, `Future<void> sendToAll(String jsonPayload, {String? exceptEndpoint})`, `Stream<ReceivedPayload> incoming`.
- `start()`: request permissions → `startAdvertising` + `startDiscovery` concurrently. Auto-accept all connections (`onConnectionInitiated` → accept, no auth prompt — hackathon scope).
- Reconnection: when `onDisconnected` fires, immediately resume discovery (advertising persists). Log all lifecycle events to a ring buffer the debug screen can show.

**`mesh_manager.dart`** — implement master plan §7 verbatim:
1. **On receive** (from transport): parse `MeshMessage`; if `seenStore.contains(id)` → drop. Else `seenStore.add(id, now)`.
2. **Surface**: if `type == SOS` → enqueue to outbox *and* raise an in-app "SOS relayed via you" banner (calm copy: "You just relayed someone's SOS — thank you"); other types enqueue silently.
3. **Internet check** (cheap: connectivity_plus + a HEAD to API `/health` with 3 s timeout, cached 30 s): if online → `SyncEngine.flush()` (outbox already has it; ordering handled there).
4. **If offline and `ttl > 0`**: `copyWith(ttl: ttl - 1)` → `transport.sendToAll(json, exceptEndpoint: senderEndpoint)`.
5. **Local originate** (user pressed SOS / submitted a report): mark seen, enqueue, then broadcast with original TTL *and* attempt flush — originating devices rebroadcast too, so a single online hop anywhere in the mesh eventually carries it out.
6. SOS-first ordering is already guaranteed by `OutboxDao.pending()` ordering from Phase 1 — preserve it; do not add a second queue.

**`seen_store.dart`**: `add(id, seenAt)`, `contains(id)`, `sweep()` — delete rows older than 24 h, called on app start and on each mesh `start()` (the master plan's TTL-expiry requirement).

**`mesh_message_codec.dart`**: `jsonEncode(msg.toJson())` → UTF-8 bytes; hard-fail logging if > 32 KB (Nearby Connections byte payloads are effectively unbounded but BLE-advertised discovery is not; SOS payloads with medical cards run ~1–2 KB, so just guard).

## 4. Sync Engine v2 (replace Phase 2's `services/sync_service.dart`)

Keep the class name/file (Phase 2 callers stay put) but make it mesh-aware:
- `flush()` unchanged in spirit: drain outbox in priority order → POST per type → markSent/markFailed (keep 4xx skip-after-5-retries).
- Trigger points now: connectivity regained (existing), **mesh message received while online** (new — this is the store-carry-forward exit ramp), app foreground, and a 60 s periodic timer while the app is running.
- Mesh lifecycle: start the mesh automatically when connectivity is lost; keep it running when online *if battery isn't a concern for the demo* — default: always-on mesh while app is foregrounded (simplest correct demo behavior). Persist a `mesh_enabled` setting (default true) so a judge can toggle it.
- Idempotency note: the same message may arrive both via mesh and later via its originator's own flush — backend inserts are plain INSERTs, so duplicates are possible. Add `client_msg_id` (= mesh message UUID) to the POST bodies and a matching unique-tolerant insert: **backend change allowed in this phase** — add nullable `client_msg_id uuid UNIQUE` column to `sos_events`/`reports` via a new alembic migration `0002_client_msg_id.py`, and make POST handlers catch `UniqueViolation` → return `200` (not 201) with the existing row. Keep it minimal; mention it in the Status Log.

## 5. Medical Card Crypto (`lib/crypto/`) — master plan §5 is the locked spec

```
lib/crypto/
├── medical_crypto.dart      # encrypt/decrypt API
└── demo_key.dart            # loads MEDICAL_CARD_DEMO_KEY via --dart-define
```

- Key: `MEDICAL_CARD_DEMO_KEY` passed as `--dart-define=MEDICAL_CARD_DEMO_KEY=<64 hex chars = 32 bytes>`. `demo_key.dart` reads `String.fromEnvironment`, hex-decodes to bytes; throws a clear error at startup if missing/≠32 bytes (better than encrypting with garbage). Generate a demo key: `openssl rand -hex 32` — record it in `backend/.env` + your run script, **never commit it**.
- `medical_crypto.dart`:
  ```dart
  Future<String> encryptMedicalCard(Map<String, dynamic> sensitiveFields); // -> base64(nonce‖ciphertext‖tag)
  Future<Map<String, dynamic>> decryptMedicalCard(String b64);
  ```
  AES-256-GCM via `cryptography`: 12-byte random nonce, no AAD; output format `base64(nonce | ciphertext | 16-byte tag)` — document this byte layout in a comment; **the backend endpoint and decrypt page must reproduce it exactly** (nonce prefix, GCM tag appended at end — `cryptography` already concatenates cipher+tag in `SecretBox.concatenation()`).
- **SOS send path integration** (`screens/sos/sos_screen.dart`, replace Phase 2's TODO): on send, build `sensitive = {medical_conditions, medications, insurance_provider, insurance_policy}` from the stored profile → `encryptMedicalCard` → set `MeshMessage.encrypted_payload`. Plaintext half rides in `payload.plaintext_medical` as before. If no sensitive fields are filled, leave `encrypted_payload` null — never encrypt empty junk.
- If the profile has sensitive data but the key is missing, **queue the SOS with `encrypted_payload: null` and warn the user** ("Medical details couldn't be secured — sending without them") rather than blocking the SOS. Safety beats crypto at demo time.

## 6. Backend: `POST /medical/decrypt` (small, demo-auth)

- `backend/app/routers/medical.py` (new router, register in `main.py`; new service file `backend/app/services/medical_crypto.py` with a Python AES-256-GCM decrypt mirroring the byte layout above — use `cryptography` PyPI package).
- Body: `{ "ciphertext": "<base64>", "demo_pass": "<pass>" }` → `200 { "fields": {…} }` | `401` bad pass | `422` undecryptable.
- Auth: `demo_pass` must equal env `DECRYPT_DEMO_PASS` (any shared string; default `"relink-demo"`). This is intentionally break-glass demo auth — comment that production would gate per-responder-org keys (master plan §5 roadmap).
- `MEDICAL_CARD_DEMO_KEY` (same 64-hex) goes in `backend/.env`.
- Test: pytest round-trip — encrypt a vector in Python, decrypt via endpoint; plus one **cross-language golden vector** generated from Dart (hardcode expected output) to prove Dart↔Python byte-layout compatibility. This golden test is the thing that catches demo-day decrypt failures — do not skip it.

## 7. Decrypt Demo Page (`dashboard/decrypt.html`)

Single self-contained HTML file (no build step — Phase 4 builds the real dashboard around it):
- Web Crypto API (`crypto.subtle.decrypt({name:'AES-GCM', iv: nonce}, key, cipherAndTag)`) — same byte layout: split base64 → nonce[0:12] | ciphertext+tag.
- Key input: paste the 64-hex demo key (or read `?key=` query param for demo convenience).
- Ciphertext input: paste from `GET /sos` response, or a "Fetch latest SOS" button that calls `GET /sos?limit=1` and auto-decrypts `encrypted_medical` via `POST /medical/decrypt` (both paths shown — direct Web Crypto proves client-side decrypt works; backend endpoint proves the break-glass path).
- Renders plaintext fields (name/blood group/allergies/emergency contact — from `plaintext_medical`) beside decrypted sensitive fields, styled in the calm palette, with a visible "Decrypted on view — never stored" caption.
- Title it clearly: this page becomes a component in the Phase 4 dashboard; keep the JS modular enough to lift.

## 8. Demo Script & Backup Video (required deliverable)

Rehearse this exact sequence, then record it (screen-record phone A + narrate; save as `demo/phase3_mesh_demo.mp4`):

1. Phone B (relay) and phone A (victim): airplane mode ON → Bluetooth ON. Open RELINK on both; debug screen shows mesh started, peers discovered.
2. Phone A: SOS flow → send. UI: "No signal — SOS saved & shared with nearby phones."
3. Phone B: banner "You just relayed someone's SOS"; debug screen shows the message id + TTL decremented on rebroadcast.
4. Phone C (online): open RELINK → within seconds `GET /sos` shows the event with `encrypted_medical` populated.
5. Open `dashboard/decrypt.html`, paste key, fetch latest SOS → sensitive medical fields render.
6. Show `ttl` reaching 0 stops rebroadcast (optional, debug log evidence).

If live recording keeps failing after honest effort (BLE flakiness is real), record the closest working variant (e.g. 2 phones instead of 3) and **tell the user** — a real 2-hop video beats a faked 3-hop one. Note the video's coverage gaps in the Status Log.

## 9. Testing

- Unit: codec round-trip; seen-store TTL sweep; flooding logic with a fake transport (new id → stored + rebroadcast with ttl-1; seen id → dropped; ttl=0 → stored, not rebroadcast; SOS → high-priority enqueue).
- Unit: `medical_crypto` round-trip; wrong key → exception; golden cross-language vector vs Python output.
- Backend pytest: decrypt endpoint 200/401/422 paths + golden vector.
- Widget: SOS screen with mocked crypto → `encrypted_payload` set on the enqueued message when sensitive fields exist.
- Physical-device soak: mesh running 10 min on two phones, no crash, discovery survives a Bluetooth toggle.

## 10. Known Gotchas

- **Nearby Connections + Android 12/13/14 permission dialogs are the classic day-1 killer**: request at runtime, in one batch, before `startAdvertising`. `neverForLocation` flag matters or Play complains.
- Discovery silently fails if Location services (the system toggle, not just the permission) are off on some OEM builds — detect and deep-link to settings.
- `P2P_CLUSTER` is many-to-many but **payloads don't auto-forward** — your flooding code does the forwarding; that separation is intentional, don't look for a library flood mode.
- Payload received callbacks deliver `Payload` objects — read bytes payloads fully before the callback returns (stream/bytes lifecycle).
- Keep a human-readable mesh debug log surface (extend Phase 2's debug screen): discovery/connection/send/receive events with timestamps. You will need it when the demo misbehaves, and judges love seeing the mesh think.
- BLE range is ~10–30 m indoors through bodies/walls — stage the demo with phones within a room, not across a building.
- Battery: mesh always-on drains; for the soak test, note drain rate in the Status Log.
- Don't over-engineer: no GATT hand-rolling, no mesh routing tables, no ACK protocol — flooding + dedupe + TTL is the spec (master plan §6 forbids raw GATT).

## 11. Finish Checklist

- [ ] 3-phone demo executed live end-to-end (§8 steps 1–5) and video saved to `demo/phase3_mesh_demo.mp4`.
- [ ] Backend migration `0002_client_msg_id` applies; duplicate-message delivery returns 200 without dupes.
- [ ] Golden Dart↔Python crypto vector passes both sides.
- [ ] `flutter analyze` + `flutter test` + backend `pytest` all green.
- [ ] **Update `CLAUDE.md` §9 Status Log, Phase 3 entry** — mesh transport behavior observed on real devices (range, reconnect quirks), crypto byte layout confirmation, video filename + any coverage gaps, deviations, what Phase 4 must know (decrypt page location, env keys now required).
- [ ] Commit: `phase 3: BLE mesh flooding + AES-GCM medical card`.
