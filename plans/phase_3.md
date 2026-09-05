# PHASE 3 — Offline Mesh + Community Forum + Medical-Card Crypto

> The differentiator phase. Real Nearby Connections BLE mesh with two-way store-carry-forward gossip (hazards, missing persons, shelters, alerts) + emergency SOS relay, local SQLite community forum backing, and embedded AES-256-GCM encryption of the SOS medical card's sensitive fields. Highest impact in the project — the backup demo video is a required deliverable, not optional.
>
> **You are the Phase 3 agent.** The master plan (`CLAUDE.md`, auto-loaded) is Core Context — §1 (personas), §3 (feature set), §4 (architecture), §5 (medical card crypto), and the mesh message schema + flooding algorithm in §7 are your contract. Read the Phase 1 & 2 entries in `CLAUDE.md §9 Status Log` first, then skim `mobile/lib/services/sync_service.dart` (you are replacing its transport half), `mobile/lib/storage/`, `mobile/lib/screens/sos/`, and `mobile/lib/models/mesh_message.dart`. Scope is `mobile/` + one small backend endpoint & migration.
>
> **If anything is ambiguous or you hit a blocker (device discovery failures, permission hell, API drift) — STOP and ask the user, then continue with their answer. Do not silently redesign the flooding protocol or the crypto.

---

## 0. Scope & Definition of Done

> [!NOTE]
> ### PROVED IMPLEMENTATION & TESTED ACHIEVEMENTS (COMPLETED):
> - **Milestone 0 Hardware Smoke Test (PASSED):** Verified on physical hardware (OnePlus Nord CE4 Android 14 & Samsung Galaxy A35 Android 16). Auto-discovery, auto-handshake, and bidirectional Ping/Pong packets over Google Nearby Connections (`P2P_CLUSTER`).
> - **Milestone 1 Physical Blackout Store-Carry-Forward SOS Relay (PASSED):**
>   - Phone 1 placed in **strict Airplane Mode (`✈️`)** with Bluetooth ON. Triggered emergency SOS with a full medical card.
>   - Phone 1 broadcasted 566-byte UTF-8 JSON wire packet over Nearby Connections BLE mesh.
>   - Phone 2 received the 566-byte packet over the air, deduplicated via `SeenStore`, stored it in SQLite `outbox`, and flushed it over HTTP via ADB reverse proxy to the laptop ingestion console on `localhost:8000`.
>   - Laptop console ingested the beacon showing Phone 1's origin device ID (`fd362824...`), GPS coordinates, and patient medical profile.
> - **Permanent Core Architecture Built & Tested:**
>   - `mobile/lib/mesh/nearby_transport.dart`: `P2P_CLUSTER` wrapper with tie-breaker and auto-accept.
>   - `mobile/lib/mesh/mesh_manager.dart`: Deduplication, store-carry-forward, outbox queuing, and TTL flooding.
>   - `mobile/lib/mesh/mesh_message_codec.dart`: Strict UTF-8 JSON codec with 32 KB guard.
>   - `mobile/lib/mesh/seen_store.dart`: SQLite `seen_ids` deduplication table.
>   - `mobile/android/app/src/main/AndroidManifest.xml`: Configured with `usesCleartextTraffic="true"` and Bluetooth/Nearby permissions.
>   - `mobile/lib/screens/debug/outbox_viewer.dart`: Outbox viewer and live mesh diagnostic probe.

**Remaining Scope to Build in Phase 3:**
1. **Embedded AES-256-GCM Medical Card Encryption:**
   - Dart `cryptography` package encryption on device before the SOS message leaves the phone.
   - Sensitive fields (`conditions`, `medications`, `insurance`) encrypted into `encrypted_payload`. Public fields (`name`, `blood_group`, `allergies`, `emergency_contact`) remain plaintext.
2. **Backend Break-Glass Decrypt Endpoint & Migration:**
   - Migration `0002_client_msg_id.py` adding `client_msg_id uuid UNIQUE` to `sos_events` and `reports` for idempotent multi-relay flushing.
   - `POST /medical/decrypt` in `backend/app/routers/medical.py` (AES-256-GCM break-glass demo decryption).
3. **Two-Way Community Forum Gossip Integration:**
   - Wire `MeshManager.broadcastMessage` into `ReportController` / `submit_hub.dart` so `REPORT`, `MISSING_PERSON`, and `SHELTER` gossip across offline peers.
   - Wire incoming community messages into local SQLite tables so the Map and Community Feed update offline.
4. **Visual Trust Signals & Affordances:**
   - App Bar "Live Mesh Radar" (`🟢 N Peers Nearby` / `🟡 Searching for Mesh...`).
   - Card origin tags: `📡 Received via Mesh (N hops)` vs `🌐 Cloud Verified`.
   - Emergency relay banner: *"Relayed an emergency beacon for [Name] — will upload when signal returns"*.
5. **Backup Demo Video Recorded** (§9).

**Out of scope:**
- Standalone `decrypt.html` website (dropped — Phase 4 builds the decrypt panel directly into the Command Dashboard).
- External hazard APIs, Sachet RSS polling, React dashboard proper (Phase 4).

---

## 1. Hardware & Environment Prereqs (Verified)

- **2–3 physical Android phones** (BLE mesh is untestable on emulators — master plan §10).
- **Physical Device Setup (The "Airplane Mode" Setup):**
  1. Airplane Mode: **ON** (simulates total cellular/Wi-Fi blackout).
  2. Bluetooth: **ON** (must manually toggle back on after activating Airplane Mode).
  3. Location / GPS system toggle: **ON** (mandatory; Android OS silently blocks BLE scanning if system location is off).
  4. Wi-Fi toggle: **ON** (recommended; does not need network connection, enables Wi-Fi Direct if negotiated).
- Backend running and reachable from the online phone (`adb reverse tcp:8000 tcp:8000` or local LAN IP).

---

## 2. Dependencies & Android Manifest (Implemented)

`pubspec.yaml` additions (Already added & verified):
```yaml
dependencies:
  nearby_connections: ^4.0.0
  permission_handler: ^11.3.0
  cryptography: ^2.7.0
```

`AndroidManifest.xml` (`mobile/android/app/src/main/AndroidManifest.xml`) (Already configured):
- `android:usesCleartextTraffic="true"` inside `<application>` (critical for HTTP communication to dev server on port 8000).
- Runtime permissions for Android 12+ (API 31+) & 13+ (API 33+):
  - `BLUETOOTH_SCAN`, `BLUETOOTH_ADVERTISE`, `BLUETOOTH_CONNECT`, `NEARBY_WIFI_DEVICES`.
  - `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`.

---

## 3. Milestones 0 & 1: Verification Results (PASSED ON HARDWARE)

> [!IMPORTANT]
> **Milestone 0 and Milestone 1 are COMPLETE and physically verified on physical hardware.**
> 
> - **Smoke Test (Milestone 0):** OnePlus Nord CE4 (`fd362824...`) and Samsung Galaxy A35 (`dacac6d6...`) connected via `P2P_CLUSTER` and exchanged bidirectional Ping/Pong packets.
> - **Relay Test (Milestone 1):** OnePlus in Airplane Mode (`✈️`) triggered medical SOS. Samsung received 566-byte packet over BLE mesh, saved it in SQLite `outbox`, and flushed it over HTTP to laptop server on port 8000. Verified with origin device ID, GPS coordinates, and patient medical profile.

---

## 3.1 Specific Instructions & Contracts for the Implementation Agent

The core mesh transport and manager are already in place. The implementation agent MUST follow these exact rules when wiring remaining features:

1. **Use the Single Shared `MeshManager`:**
   - `MeshManager` is provided at the root widget tree in `mobile/lib/main.dart` via `Provider<MeshManager>`.
   - Do NOT instantiate a second `MeshManager` or `NearbyTransport`. Access it via `context.read<MeshManager>()` or `context.watch<MeshManager>()`.
2. **Broadcasting Community Posts:**
   - When a user submits a hazard report, missing person, or shelter in `submit_hub.dart`, create a `MeshMessage` and call `meshManager.broadcastMessage(msg)`.
   - `MeshManager` will handle self-deduplication, outbox queuing, and radio broadcasting to all connected peers.
3. **Handling Incoming Community Messages:**
   - In `MeshManager._handleMessage`, when receiving `MessageType.report`, `missingPerson`, `shelter`, save to the respective SQLite tables so the offline Map Screen (`map_screen.dart`) displays them immediately without internet.
4. **Implementing Medical Crypto (`mobile/lib/crypto/`):**
   - Implement `MedicalCrypto` using `cryptography` package `AesGcm.with256bits()`.
   - Envelope format: Base64 string of `[12-byte Nonce] + [Ciphertext] + [16-byte GCM Tag]`.
   - SOS send path in `SosController`: encrypt `sensitive_medical` fields, set `MeshMessage.encryptedPayload`, and retain public fields in `payload['plaintext_medical']`.
   - If key missing: fall back to unencrypted and send. Never block an emergency beacon.
5. **Connecting UI Mesh Radar:**
   - In `home_shell.dart` AppBar, listen to `context.watch<MeshManager>().connectedPeers.length`.
   - Display a pill: `🟢 $count Peers Nearby` when $> 0$, or `🟡 Searching for mesh...` when 0.

---

## 3.2 Common Pitfalls for the Implementation Agent (CRITICAL WATCHLIST)

| Pitfall | Cause | Required Solution |
| :--- | :--- | :--- |
| **Cleartext HTTP Blocked** | Android 9+ (API 28+) blocks `http://127.0.0.1:8000` by default. | Ensure `android:usesCleartextTraffic="true"` remains in `<application>` in `AndroidManifest.xml`. |
| **Physical Phone Networking** | `10.0.2.2` only works in Android emulators; physical devices cannot reach it. | Run `adb reverse tcp:8000 tcp:8000` so physical phones route `127.0.0.1:8000` straight into the dev laptop via USB, or configure dev machine LAN IP. |
| **ADB Daemon Restarts** | When ADB daemon restarts (`* daemon not running; starting now...`), all active reverse bindings are wiped. | Always re-check `adb reverse --list` or re-execute `adb reverse tcp:8000 tcp:8000` if connection refused occurs. |
| **Missing System Location Toggle** | BLE scanning silently returns 0 peers on Android OS if system GPS / Location is switched OFF in phone quick settings. | Ensure physical phone has system Location toggle **turned ON**, even when in Airplane Mode. |
| **Simultaneous P2P Connection Collision** | When two phones discover each other at the same instant, both calling `requestConnection` causes `STATUS_ALREADY_CONNECTED` or link drop. | Maintain the deterministic tie-breaker in `nearby_transport.dart`: only the device with `localDeviceId < peerDeviceId` initiates; the other awaits connection. |
| **Large Message Sizes** | Nearby Connections byte payloads must stay compact (BLE/Wi-Fi Direct). | Strictly enforce 32 KB payload guard via `MeshMessageCodec`. Never send large raw camera images through mesh byte packets; only send text metadata or low-res thumbnails. |
| **Missing HTTP Content-Length** | Python dev servers omitting `Content-Length` on HTTP responses cause Dart's `http` client to throw `Connection closed before full header was received`. | Ensure HTTP servers return explicit `Content-Length` and `Connection: close` headers. |
| **Self-Reflection & Broadcast Loops** | Re-broadcasting received mesh messages can cause infinite ping-pong storms. | Always check `msg.originDeviceId != localDeviceId`, check `seenStore.contains(msg.id)`, and decrement TTL (`ttl - 1`). If `ttl <= 0`, do NOT rebroadcast. |

---

## 4. Mesh Layer Architecture (`lib/mesh/`)

```
lib/mesh/
├── nearby_transport.dart    # Nearby Connections wrapper (discovery, advertising, auto-accept, connection tie-breaker)
├── mesh_manager.dart        # Two-way gossip & flooding protocol — the brain
├── seen_store.dart          # seen_ids table access + 24h TTL sweep
└── mesh_message_codec.dart  # MeshMessage <-> bytes (UTF-8 JSON), 32 KB payload guard
```

### `nearby_transport.dart` — Boring, Resilient Wrapper:
- **Constants:** `serviceId = "in.relink.mesh"`, `strategy = Strategy.P2P_CLUSTER`.
- **Endpoint Nickname:** Persistent local device UUID (from Phase 2).
- **Auto-Accept:** On `onConnectionInitiated(endpointId, connectionInfo)` $\rightarrow$ call `Nearby().acceptConnection(...)` immediately. Do not prompt the user.
- **Connection Collision Tie-Breaker:** When Phone A discovers Phone B and both attempt connection simultaneously, only initiate `requestConnection` if `localDeviceId.compareTo(remoteEndpointName) < 0`, or catch `STATUS_ALREADY_CONNECTED` without dropping the link.
- **Reconnection Resilience:** When `onDisconnected` fires, clean up endpoint state and ensure discovery/advertising remain active.

### `mesh_manager.dart` — Two-Way Community Gossip & Flooding:
1. **On Receive (from transport):**
   - Decode byte payload via `mesh_message_codec.dart`.
   - Deduplication check: if `seenStore.contains(msg.id)` $\rightarrow$ drop silently.
   - Record in `seenStore.add(msg.id, now)`.
   - If self-originated reflection (`msg.originDeviceId == localDeviceId`) $\rightarrow$ drop.
2. **Handling by Type:**
   - **`SOS`:**
     - Enqueue into local SQLite outbox for store-carry-forward.
     - Surface calm in-app banner: *"Relayed an emergency beacon for [Name] — will upload when signal returns"*.
     - If device has internet $\rightarrow$ immediately trigger `SyncService.flush()`.
     - If device is offline and `ttl > 0`: decrement TTL (`ttl - 1`), rebroadcast to all connected peers except sender endpoint.
   - **`REPORT` / `MISSING_PERSON` / `SHELTER` / `ALERT` (Community Gossip):**
     - Save to local SQLite database so the offline Map and Community Feed update immediately.
     - Decrement TTL (`ttl - 1`). If `ttl > 0`, rebroadcast to other connected peers.
     - If device has internet and message was not yet marked synced, enqueue to outbox for cloud sync.
3. **Peer Greeting / Burst Sync:**
   - When a new peer successfully connects (`onEndpointConnected`), send a compact burst of recent local reports and notices (last 10 items) so the newly arrived offline phone receives recent disaster updates without manual user intervention.

### `seen_store.dart`:
- Backed by local SQLite table `seen_ids (id TEXT PRIMARY KEY, seen_at TEXT)`.
- Methods: `add(id, seenAt)`, `contains(id)`, `sweep()` (purges entries older than 24 hours).

---

## 5. Local Community Cache & Offline UI Integration

Phase 2 screens must be connected to local SQLite data so the app feels 100% functional offline:

1. **Local Forum / Map Storage:**
   - Store received community messages (`reports`, `missing_persons`, `shelters`) directly in SQLite.
   - Map Screen (`map_screen.dart`): reads active reports and shelters from local SQLite store first, refetching from backend over HTTP when online.
2. **Visual Trust Signals:**
   - **App Bar Mesh Radar:** Add a compact widget to `home_shell.dart` or the screen header:
     - `🟢 N Peers Nearby` (green pulsing dot) when connected to $\ge 1$ peers.
     - `🟡 Searching...` when active with 0 peers.
   - **Card Origin Tag:** Add a subtle pill badge on hazard and missing person cards:
     - `📡 Via Mesh (${initialTtl - currentTtl} hops)` for peer-delivered data.
     - `🌐 Cloud Verified` for server-fetched data.

---

## 6. Sync Engine v2 & Backend Idempotency

### Sync Service (`services/sync_service.dart`):
- Maintain Phase 2's priority ordering: **SOS events are dequeued and sent first**.
- Multiple triggers:
  1. Connectivity regained (`connectivity_plus`).
  2. Incoming mesh message received while device is online.
  3. App foregrounded.
  4. Periodic 60-second timer.

### Backend Migration & Ingestion (`backend/`):
- Create alembic migration `0002_client_msg_id.py`:
  - Add nullable `client_msg_id uuid UNIQUE` to `sos_events` and `reports`.
- In `routers/sos.py` and `routers/reports.py`:
  - Accept `client_msg_id` in request body.
  - On `UniqueViolationError` (or existing record lookup) $\rightarrow$ return `200 OK` with the existing row instead of failing with 500/409. This handles multiple relays flushing the same message.

---

## 7. Medical Card Cryptography (`lib/crypto/`)

Master plan §5 locked specification:
```
lib/crypto/
├── medical_crypto.dart      # AES-256-GCM encrypt/decrypt
└── demo_key.dart            # Loads MEDICAL_CARD_DEMO_KEY via --dart-define
```

1. **Envelope Byte Layout:**
   Strict cross-platform format:
   $$\text{Base64}\big(\, [12\text{-byte Nonce}] \,\|\, [\text{Ciphertext}] \,\|\, [16\text{-byte GCM Tag}] \,\big)$$
   - In Dart: use `cryptography` package with `AesGcm.with256bits()` and `SecretBox.concatenation()`.
2. **SOS Send Path:**
   - On SOS trigger: pull sensitive fields (`medical_conditions`, `medications`, `insurance_provider`, `insurance_policy`).
   - If sensitive fields exist $\rightarrow$ encrypt to Base64 ciphertext $\rightarrow$ store in `MeshMessage.encrypted_payload`.
   - Public fields (`name`, `blood_group`, `allergies`, `emergency_contact`) remain in plaintext `payload.plaintext_medical`.
   - If encryption key is missing $\rightarrow$ queue SOS with `encrypted_payload: null` and notify user ("Medical details couldn't be encrypted — sending emergency alert without them"). Safety always beats crypto.

---

## 8. Backend: Break-Glass Endpoint (`POST /medical/decrypt`)

- Add `backend/app/routers/medical.py` and `backend/app/services/medical_crypto.py`.
- Endpoint: `POST /medical/decrypt`
  - Body: `{ "ciphertext": "<base64>", "demo_pass": "<pass>" }`
  - Auth: `demo_pass == os.environ.get("DECRYPT_DEMO_PASS", "relink-demo")`.
  - Python AES-256-GCM decryption via `cryptography.hazmat.primitives.ciphers.aead.AESGCM`.
  - Output: `200 { "status": "success", "decrypted_data": { ...fields... } }` | `401 Unauthorized` | `422 Unprocessable Entity`.
- Pytest: Test with a known **Cross-Language Golden Vector** generated from Dart to prove cross-platform compatibility.

---

## 9. Demo Script & Backup Video (Required Deliverable)

Rehearse and record this exact flow to `demo/phase3_mesh_demo.mp4`:

1. **Phones A and B (Both in Airplane Mode, Bluetooth ON, Location ON):**
   - Open RELINK on both phones.
   - App bar displays `🟢 1 Peer Nearby` on both screens.
2. **Community Forum / Hazard Sharing:**
   - Phone A submits a road hazard: *"Aluva bridge submerged under 2ft water"*.
   - Within seconds, the hazard pin and card appear on Phone B's offline map with the `📡 Via Mesh` badge.
3. **Emergency SOS Propagation:**
   - Phone A taps SOS $\rightarrow$ confirms send.
   - Phone A shows: *"No signal — SOS saved & broadcasting to nearby peers"*.
   - Phone B shows banner: *"Relayed an emergency beacon for [Name] — will upload when signal returns"*.
4. **Cloud Flush:**
   - Phone C (or Phone B reconnecting to Wi-Fi) receives the packet and flushes to backend.
   - Backend `GET /sos` returns the event with populated `encrypted_medical`.
5. **Decryption Verification:**
   - Hit `POST /medical/decrypt` with the ciphertext and demo passphrase $\rightarrow$ sensitive medical records render cleanly.

---

## 10. Verification & Testing

- **Flutter Unit Tests:**
  - `crypto_test.dart`: AES-256-GCM round-trip, invalid key rejection, golden cross-language vector test.
  - `mesh_manager_test.dart`: Packet decoding, deduplication via `seen_ids`, TTL decrement, two-way gossip routing, and SOS priority dequeuing.
- **Backend Tests:**
  - `test_medical_crypto.py`: Python decryption of golden vector, invalid passphrase rejection, malformed payload error handling.
- **Static Analysis:**
  - `flutter analyze` clean (0 errors, 0 warnings).
