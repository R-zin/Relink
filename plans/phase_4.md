# PHASE 4 — Intelligence + Alerts + Dashboard + Demo Prep

> Final phase: external hazard APIs + AI review + Sachet RSS polling + FCM system-tray push on the backend/app side, and the React command dashboard with seeded data and demo polish. Everything the judges see on the big screen comes from this phase.
>
> **You are the Phase 4 agent.** The master plan (`CLAUDE.md`, auto-loaded) is Core Context — §7's external-data-source table + AI-review prompt are your contract, §2 governs dashboard styling, §10 is your demo checklist. Read the Phase 1–3 entries in `CLAUDE.md §9 Status Log` first; skim `backend/app/` structure, `mobile/lib/screens/alerts/` + `stats/` (you're filling those placeholders), and `dashboard/decrypt.html` from Phase 3 (you're lifting its JS into a React component). Scope: `backend/` services/jobs/routers additions, `mobile/` alerts+stats screens + FCM wiring, all of `dashboard/`.
>
> **If anything is ambiguous or you hit a blocker (an external API is down/changed, FCM credentials missing, feed format drift) — STOP and ask the user, then continue with their answer.**

---

## 0. Scope & Definition of Done

**Build:**
1. Backend: external-API fetch services (GloFAS, GFM, Open-Meteo Forecast + Marine, NASA EONET) + static dam dataset, all cached in `stats_cache`.
2. Backend: AI review service (`/stats/ai-review`, cached, 15–30 min regen).
3. Backend: Sachet RSS poller + `/alerts` endpoint + FCM push dispatcher on Red/Orange alerts.
4. Mobile: real Alerts screen (feed + severity styling), real Stats screen (metric cards + charts + AI summary), FCM integration with system-tray notifications + deep link.
5. Dashboard: React + Vite app — live Leaflet map (all layers incl. GFM flood extent), charts (Recharts), AI review panel, SOS feed with decrypt-on-view, seeded data.
6. Demo prep: seed refresh, demo script checklist executed.

**Out of scope:** changes to mesh/crypto internals (Phase 3 owns those — report bugs, don't fix silently), social signal monitoring (optional stretch, only if everything else is done).

**Done when:**
1. `GET /stats`, `GET /stats/ai-review?region=…`, `GET /alerts?state=…` all serve cached data sourced from live fetches (or documented fallbacks).
2. A Red/Orange Sachet alert produces a **real OS notification-tray push** on a backgrounded/killed app; tapping it opens the alert detail in-app.
3. Dashboard renders seeded map + charts + AI summary + one live-updating SOS; decrypt view works with the Phase 3 ciphertext.
4. Master plan §9 Status Log, Phase 4 entry updated; demo checklist (§11) executed.

---

## 1. Prereqs

- Phase 1–3 Status Log entries read; backend + app running end-to-end.
- Env keys needed now: `LLM_API_KEY` (Claude or hackathon-provided), `FCM_SERVER_KEY` + Firebase project files (`google-services.json` for Android, `FirebaseOptions` for Dart). **If the user hasn't provided Firebase credentials, ask before starting §5 — FCM cannot be faked.** Sachet/Open-Meteo/EONET need no keys.
- Pick the target state for Sachet RSS (demo region's state, e.g. `rss_kerala.xml`) — confirm the exact URL slug from the master-plan pattern with the user or by fetching the index page; feed slugs are per-state and occasionally drift.

## 2. Backend: External Fetch Services (`backend/app/services/external_apis/`)

One module per source, each exposing `async def fetch() -> dict` returning a normalized metric payload, and each wrapped by a common `cached_fetch(metric_name, fetch_fn, ttl_minutes)` helper that writes/reads `stats_cache` (from Phase 1 schema). Use `httpx.AsyncClient` with 10 s timeouts. **Every fetcher must degrade gracefully**: on network/API failure, serve the last cached value (however stale) and mark `stale: true` in the payload; if no cache exists, serve the bundled fallback fixture (see §7) with `fallback: true`. Never 500 the `/stats` endpoint because a third party is down.

| Module | Source (master plan §7) | Normalized payload |
|---|---|---|
| `glofas.py` | Open-Meteo GloFAS (`https://flood-api.open-meteo.com/v1/flood?latitude=..&longitude=..&daily=river_discharge,river_discharge_mean,river_discharge_max`) | latest discharge m³/s, 7-day forecast array, trend vs mean, forward-looking risk note |
| `gfm.py` | Copernicus Global Flood Monitoring | latest observed flood-extent polygon(s) for the demo region + **observation timestamp** (never presented as real-time — master plan §10). If the live GFM product proves impractical to integrate in-session (auth/format), ship a bundled recent-extent GeoJSON fixture with a real historical observation time and log the deviation — ask the user first. |
| `weather.py` | Open-Meteo Forecast (`rain`, `precipitation`, `wind_gusts_10m`, hourly) | 24 h rainfall total, max gust, next-24 h rainfall forecast |
| `marine.py` | Open-Meteo Marine (`wave_height`, `swell_wave_height`) | current + max swell for a coastal point in the demo region |
| `eonet.py` | NASA EONET v3 `/events?status=open&limit=20` | cyclone/severe-storm events within ~1500 km of demo region (haversine filter), name + category + last position |
| `dams.py` | Static dataset | load `backend/app/data/dams_mock.json` (create: 5 realistic Kerala dams — Idukki, Mullaperiyar, Banasura Sagar, etc. — with `name, lat, lng, storage_pct, danger_level_pct, last_updated`). Label in API output as cached/static. |

Region config: `DEMO_REGION_LAT/LNG/NAME` env (default Kochi area, consistent with Phase 1 seed). UI copy rule from master plan §7: cite **IMD** as official source name for rainfall/wind, **INCOIS** for marine — source attribution strings live in the API payload so app + dashboard both show them.

**`GET /stats`** (`routers/stats.py`): aggregates all seven metrics from cache (triggering refresh of any expired entry inline is fine, but prefer returning cached + letting the scheduler refresh — keep p99 latency low). Response: `{region, fetched_at, metrics: {glofas:…, gfm:…, weather:…, marine:…, eonet:…, dams:…}}`, each metric carrying `source_label`, `stale`, `observed_at` where relevant.

## 3. Backend: AI Review (`services/ai_review.py`, `routers/stats.py`)

- `GET /stats/ai-review?region=…`: read `ai_review_cache` latest for region; if older than 15–30 min (env `AI_REVIEW_TTL_MIN`, default 20) or missing, regenerate synchronously (with a 20 s LLM timeout — on timeout serve stale cache or a `503` with `retry_after` hint; dashboard/app handle it).
- Generation: pull the `/stats` aggregate, then call the LLM with the master plan §7 system prompt **verbatim** (fill `[region]`), passing the metrics JSON as the user message. Parse the risk tag from the response — instruct the model to end with `RISK TAG: <Low|Moderate|High|Severe>` and regex-extract it (robust to prose drift); store `{region, summary_text, risk_tag, generated_at}`.
- LLM client: minimal `httpx` POST to the Anthropic API (or hackathon-provided endpoint — check `LLM_API_KEY`/`LLM_BASE_URL` envs with the user if unsure). Model: a current fast model; keep `max_tokens` ~300. No frameworks.
- pytest: mock the LLM HTTP call; verify prompt includes the metric numbers, tag extraction works on messy output ("…therefore RISK TAG: High"), caching prevents double-calls within TTL.

## 4. Backend: Sachet RSS + FCM (`services/alerts_service.py`, `jobs/scheduler.py`, `routers/alerts.py`)

**Poller (`jobs/scheduler.py`):** APScheduler `AsyncIOScheduler` started in the FastAPI lifespan. Jobs:
- `poll_sachet` every 10 min: fetch `SACHET_RSS_URL`, parse XML (use `feedparser` or `xml.etree` — feedparser is more forgiving of CAP-ish RSS drift), normalize items to `{id (guid hash), title, description, severity (map CAP severity or keyword-scan: red/orange/yellow/green — default `yellow` when unknown), area, issued_at, link}`. Store in a new table `alerts_cache` (migration `0003_alerts_cache.py`: `id text PK, state text, title, description, severity, area, issued_at timestamptz, link, raw_json jsonb, fetched_at timestamptz`) — upsert by guid, keep last 100 per state.
- After each poll: for any **new** item with severity red/orange, dispatch FCM (§5).
- `refresh_stats` every 15 min: call each `cached_fetch` so `/stats` never serves truly cold data. `refresh_ai_review` every 20 min for the default region (LLM calls cost money — only the demo region, not on-demand for arbitrary regions).
- Scheduler failures must not crash the app: wrap every job body in try/except + log.

**`GET /alerts?state=…&severity=…`** (`routers/alerts.py`): reads `alerts_cache`, newest first, default limit 50. Response items match the normalized shape above. Also `GET /alerts/{id}` for the deep-link target.

## 5. FCM Push (backend dispatch + mobile integration)

**Backend (`services/fcm_service.py`):**
- Topic-based: all app installs subscribe to `alerts_<state>` (single demo topic is fine: `alerts_kerala`). No device-token registry table — topics keep it stateless.
- Dispatch via FCM HTTP v1 (service-account JSON → OAuth2) **or** legacy server key if that's what the user provides (`FCM_SERVER_KEY` from master plan §7 implies legacy; legacy is fine for the hackathon — one POST, no OAuth dance). Message: `notification {title, body}` + `data {alert_id, severity, click_action: "FLUTTER_NOTIFICATION_CLICK"}`, Android `priority: HIGH`, channel id `relink_alerts_high`.
- Trigger: from the poller (§4) on new red/orange items. Also expose `POST /alerts/test-push` (demo-auth pass like Phase 3's decrypt endpoint) that sends a synthetic Red alert push — **this is your demo-day trigger**; judges can't wait for a real cyclone. Log it in the Status Log.

**Mobile (`lib/services/push_service.dart` + Android wiring):**
- Deps: `firebase_messaging`, `firebase_core`, `flutter_local_notifications`. `flutter pub add` and follow firebase setup for Android (`google-services.json` → `android/app/`; apply the plugin in gradle). Ask the user for the Firebase console files if not present.
- **The classic gotcha (master plan §6): the background message handler must be a top-level function**, annotated `@pragma('vm:entry-point')`, registered via `FirebaseMessaging.onBackgroundMessage(...)` in `main.dart` *before* `runApp`.
- Create the high-priority channel at startup: `flutter_local_notifications` `AndroidNotificationChannel('relink_alerts_high', 'Severe alerts', importance: Importance.max, playSound: true, enableVibration: true)` — heads-up behavior comes from the channel existing *before* the FCM arrives.
- On foreground message → show local notification on the same channel. On notification tap (background or terminated) → navigate to `AlertDetailScreen(alert_id)` via a `GlobalKey<NavigatorState>`.
- Subscribe to the demo topic on first launch (`FirebaseMessaging.instance.subscribeToTopic('alerts_kerala')`).
- **Test on a genuinely backgrounded and a genuinely killed app** (master plan §10 names this the common last-minute surprise). Verify with `POST /alerts/test-push`.

**Alerts screen (`screens/alerts/` — replace placeholder):** list from `GET /alerts`, severity tag chips (Red/Orange = alarm red styling — this is the other reserved-red usage; Yellow/Green = amber/teal), NDMA text quoted verbatim (master plan §2 — official alert text is the exception to plain-language copy), issued time relative, tap → detail screen. Pull-to-refresh.

## 6. Mobile: Stats Screen (`screens/stats/` — replace placeholder)

- `GET /stats` → metric cards grid: river discharge + forecast trend arrow (GloFAS), 24 h rainfall + gusts (IMD attribution), swell (INCOIS), dam storage bars (labeled "cached data"), cyclone events count (EONET), flood-extent card showing GFM observation time ("Satellite-observed flood extent · observed {time}").
- `fl_chart` for: 7-day river-discharge forecast line, 24 h rainfall bars. Keep chart styling calm (soft colors, no red unless a value is genuinely severe).
- `GET /stats/ai-review` → plain-language summary card at top with the risk tag chip (Severe/High → reserved red/amber respectively; Moderate/Low → teal/gray). Show `generated_at` ("updated 12 min ago"). Loading state: skeleton cards; error state: plain-language retry.
- Every card shows its `source_label` + stale badge when applicable — judges ask about data provenance; this preempts it.

## 7. Fallback Fixtures (`backend/app/data/`)

Create `fixtures/{glofas,gfm,weather,marine,eonet}.json` — real responses captured once during this session (curl them and save verbatim, trimmed). These serve when network is unavailable mid-demo. Record capture date in each file's `captured_at` field. **Do not fabricate fixture numbers** — trim real responses; demo credibility depends on it.

## 8. React Dashboard (`dashboard/`) — the big-screen artifact

Vite + React + TypeScript (template: `npm create vite@latest dashboard -- --template react-ts`; keep Phase 3's `decrypt.html` in the repo root of dashboard/ or `public/` — lift its logic, don't delete it). Deps: `leaflet`, `react-leaflet`, `recharts`, plain CSS (no UI framework — hand-roll with the calm palette from master plan §2; denser tables are fine, audience is responders).

```
dashboard/src/
├── main.tsx, App.tsx, theme.css
├── api.ts                  # fetch wrappers, VITE_API_BASE_URL env
├── components/
│   ├── CommandMap.tsx      # Leaflet: layer toggles — SOS (red), shelters (teal),
│   │                       # hazard clusters (amber, count badges), missing persons (violet),
│   │                       # GFM flood extent (semi-transparent blue polygons + observation-time label)
│   ├── SosFeed.tsx         # live SOS list; auto-refresh 15 s (Supabase realtime optional, polling acceptable)
│   ├── DecryptPanel.tsx    # Phase 3 logic as a component: select SOS → POST /medical/decrypt →
│   │                       # plaintext + decrypted side-by-side, "decrypted on view, never stored" caption,
│   │                       # demo-pass input
│   ├── StatsGrid.tsx       # metric cards mirroring mobile stats + provenance labels
│   ├── ChartsPanel.tsx     # Recharts: discharge forecast line, rainfall bars, confirm-count trends
│   ├── AiReviewPanel.tsx   # summary + risk-tag chip + generated_at; regenerate button (calls endpoint)
│   └── AlertsList.tsx      # Sachet alerts w/ severity chips; "Send test Red alert push" button (demo pass)
└── fixtures/               # none — dashboard reads live backend only
```

Layout: map dominant (left 2/3), right rail = SOS feed + decrypt panel; bottom strip = stats grid + charts + AI review. Header: "RELINK — Command Dashboard" + region name + live clock. Keep it one screen, no routing — judges see everything at once.

## 9. Seed Data & Demo Prep

1. Re-run Phase 1's `seed.py` against the demo DB, then add **Phase 4 seeding**: one synthetic Red alert row in `alerts_cache` (so the alerts list is never empty even if NDMA is quiet — mark it `[DEMO]` in the title), plus confirm-count history spread over days so trend charts aren't flat (extend `seed.py` in place; keep idempotency).
2. Populate `stats_cache` by hitting `GET /stats` once (or letting the scheduler run) before demo.
3. Pre-cache offline map tiles on the demo phones for the venue region (master plan §10) — document the exact steps you used in the Status Log for the user.
4. Execute the demo checklist in §11; fix what fails or escalate to the user.

## 10. Testing

- Backend pytest: each fetcher's normalization (recorded-response fixtures), stale-on-failure behavior, AI-review tag extraction + cache TTL, RSS parse → upsert → red/orange triggers FCM dispatch (mocked HTTP), `/alerts` filtering, `/alerts/test-push` auth.
- Mobile: widget tests for alerts list severity rendering + stats cards from fixture JSONs; manual: backgrounded push → tray → tap → deep link; killed app → push → tap → cold-start deep link.
- Dashboard: `npm run build` clean; manual sweep against live backend.

## 11. Demo-Day Checklist (execute, don't just write)

- [ ] 2–3 physical phones charged, BLE mesh verified again post-Phase-4 changes, `demo/phase3_mesh_demo.mp4` on the demo laptop + a phone.
- [ ] Test-push button sends a Red alert → killed app on the demo phone buzzes in the tray → tap opens alert detail. **Do this twice.**
- [ ] Dashboard on the big screen: seeded map populated, GFM layer shows with observation-time label, live SOS triggered from a phone appears within one refresh cycle, decrypt panel opens it.
- [ ] `/stats` + AI review render; risk tag matches the numbers.
- [ ] Airplane-mode SOS → relay → flush → appears on dashboard (the Phase 3 path, re-verified end-to-end with push + dashboard now live).
- [ ] Offline map tiles confirmed cached with Wi-Fi off.
- [ ] Backup plans staged: fixtures warm (airplane-mode the demo laptop and `/stats` still serves), video reachable in ≤3 clicks.

## 12. Known Gotchas

- **Sachet RSS slugs/format drift** — fetch the real feed early this session; if the expected URL 404s, find the current one from the NDMA CAP index and tell the user (master plan's URL is a pattern, not a promise).
- FCM legacy API vs v1: match whatever credential the user provides; don't build both.
- Android 13+ needs the `POST_NOTIFICATIONS` runtime permission — request it on first launch or pushes silently never show.
- Heads-up notifications require the channel created before the push arrives *and* app not battery-restricted (OEM aggressive battery killers — whitelist the app in demo phone settings).
- LLM latency: AI review generation is the slowest call in the system; never block `/stats` on it.
- Copernicus GFM access mechanics (STAC/WEkEO auth) may not fit a hackathon session — the fallback-fixture path in §2 is a legitimate, pre-approved deviation; label it honestly.
- Timezone: serve all timestamps in UTC ISO8601; render relative times client-side.
- Recharts + large arrays: downsample forecast series to daily points; nobody reads hourly at demo distance.

## 13. Finish Checklist

- [ ] `/stats`, `/stats/ai-review`, `/alerts` live with cached real data; fixtures + fallbacks verified by killing the network.
- [ ] Backgrounded AND killed push verified on the demo phone; deep link lands on the right alert.
- [ ] Dashboard: all panels render with live backend; decrypt works on a Phase 3 SOS.
- [ ] Demo checklist §11 executed; failures fixed or escalated.
- [ ] **Update `CLAUDE.md` §9 Status Log, Phase 4 entry** — what shipped, exact feed/topic/region config, any API substitutions (esp. GFM path taken), FCM credential type used, demo checklist results, remaining rough edges.
- [ ] Commit: `phase 4: alerts, stats, AI review, FCM push, command dashboard`.
