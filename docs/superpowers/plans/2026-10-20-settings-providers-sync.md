# Settings unlock, cloud AI providers, screenshot folder, second sync backend: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close wave 10. Then remove every value tied to the owner's own setup (agenda feeds, models, Studio host, screenshot paths) so any user can set them. Add cloud AI providers behind local-first defaults, a user-chosen screenshots folder, and a second sync backend next to Nextcloud.

**Architecture:**
- Settings stay where they are today: the vault `settings.json` for calendars, `_system/settings/ai.json` for AI, `nextcloud.json` plus secure storage for sync.
- Cloud providers reuse the existing `openai-compatible` connection kind. OpenAI, Gemini, Anthropic, Mistral and OpenRouter all expose OpenAI-compatible chat endpoints, so the work is presets plus an API key kept in secure storage. No new Dart dependency.
- The second sync backend starts as plain WebDAV, which reuses `lib/nextcloud_sync/webdav_client.dart`.
- A peer-to-peer backend (Ouisync or iroh) is a measured spike with a go/no-go gate, not a commitment.

**Tech Stack:** Flutter/Dart, drift, flutter_secure_storage, Rust via flutter_rust_bridge (already used by `packages/typst_flutter`), Python scripts in `~/Nextcloud/InstantUpload/Screenshots` (uv).

**Spec:** The user's request of 2026-10-20 (quoted in Part 0 below) and the open wave 10 plan at `~/.claude/plans/lets-think-how-its-eager-moonbeam.md`.

## Global Constraints

- No release while any found issue is open. 0.19.2 ships only after Part 1 is verified on the Mac and a phone; the big update ships as 0.20.0 after Part 2.
- Local first: a fresh install offers local/LAN connections (Ollama, Unsloth Studio, LM Studio) first. Cloud providers are opt-in, and a task never falls back to cloud silently.
- API keys live only in OS secure storage (`FlutterSecureStorage`), never in `ai.json`, `settings.json` or the vault. The vault syncs, so anything written there leaves the device.
- Existing user values must survive. A user who already has `settings.json` or `ai.json` sees the same feeds and models after upgrading.
- Never touch phone stay-awake settings. Screenshot before every adb tap. No Mac UI clicks while the user is at the Mac.
- Never commit `graphify-out/`, `macos/Podfile.lock` or `docs/research-on-device-llm-phone-node.md`.
- Python: `uv` only.
- Delegation: codex `gpt-5.6-luna` does multi-file edits (`codex exec -m gpt-5.6-luna -c model_reasoning_effort=low -s workspace-write "..." < /dev/null`). Ornith 1.5 35b on Studio (via `~/.claude/skills/pi-delegate/scripts/pi-run.sh`, loaded at 64k) writes only new or small files. Claude reviews diffs, runs `flutter analyze` and the full `flutter test`, and does device checks.

## Review Focus

1. An upgrade over an existing `settings.json` with the owner's feeds: feeds keep working. Only fresh installs get empty defaults (Task 2.1 test `keeps saved feed URLs`).
2. A cloud connection's API key must never appear in `ai.json` after a save/load round trip (Task 2.3 test `api key not written to ai.json`).
3. A screenshots folder that the user picks but that has no scripts in it: the setting is saved and the health line says "scripts not found" instead of throwing (Task 2.2 test `missing scripts folder`).
4. A Studio host that is unreachable while traveling: the screenshot pipeline logs and retries, and no screenshot is marked as processed (Task 2.4 Python test `unreachable host leaves file pending`).
5. The WebDAV backend pointed at a non-Nextcloud server with no chunked upload: large files fall back to a single PUT (Task 3.1 test `no chunking endpoint`).

---

## Part 0: Status check (what was done, how it was fixed, what needs attention)

User request: "let's perform check what was done, how it's fixed. What needs attention. Before next big update."

| Item | Fix (commit) | Verified | Needs attention |
|---|---|---|---|
| Search double-pop: black screen on the phone, Today on the Mac | One shared `openFromSearch` pops Search once (0951345, eb7a3d2) | Tests; P30 | Mac retest by the user |
| "пробежка" showed only passages | DB ids mapped to paths (983718b); note hits above passages (14d7fa5) | Tests; Mac screenshots | none |
| False hits ("Malinki") | Unknown query terms no longer match every doc (7c3f4cf) | Real-vault copy test | none |
| Open a result at the match (S2) | Query passed to the editor and reading view, 2 s amber highlight (eb7a3d2) | Widget tests; P30 lands on the match | No visible highlight on screenshot notes; Mac "пробежка" → 2023-03-29 retest |
| First search slow (57 s every launch) | Built index persisted and warm-built (eb7a3d2) | P30: 3.0 s | none |
| Search index memory (S6) | Shared vocabulary + compact tf, format v3 (7c3f4cf) | P30 PSS after a search 394–515 MB | Target ≤350 MB not met |
| Worker loads search lazily | 942c53b | P30 PSS before a search 196–249 MB | none |
| Desktop vault revision sync without an account | `startCloudPolling` desktop branch | Test | none |
| Screenshots automatic | LaunchAgents + backfill watcher (scripts repo 592dea7) | Health OK, new upload processed in 6 min | Studio host and paths hard-coded (Part 2) |
| Fold tall images (S3) | not started | none | open |
| Fold list subtrees (S4) | not started | none | open |
| Mac DB projection 103/9,843 (S5) | not started | none | open |
| Keep the query when going back to Search | not started | none | open (user answer pending) |

## Part 1: Close wave 10, then release 0.19.2

These are the existing wave 10 tasks. Their done-when metrics stay as written in `~/.claude/plans/lets-think-how-its-eager-moonbeam.md`.

### Task 1.1: S2 highlight on screenshot notes

**Files:** Find the screenshot note view with `graphify query "screenshot note view widget"`, then modify it; the likely file is `lib/widgets/screenshot_strip.dart`. Test: `test/search_reveal_test.dart`.

- [ ] Write a failing widget test. Open a screenshot note whose OCR text contains "Cervejaria" with `searchQuery: 'cervejaria'`. Expect a `kSearchRevealFill` decoration within 500 ms.
- [ ] Wire `searchQuery` through to the OCR text widget the same way `lib/widgets/reading_mode.dart` does (`SearchReveal` from `lib/widgets/search_reveal.dart`).
- [ ] Run `flutter test test/search_reveal_test.dart`; expect PASS. Commit "Wave 10 S2: highlight in screenshot notes".

### Task 1.2: S3 fold tall images

Follow the S3 row of the wave 10 plan. The fold store is device-local: a JSON map `{notePath: [assetPath,...]}` at `deviceLocalStorage()/fold_state.json`.

- [ ] Write a failing widget test. Render an image 3× the viewport height and expect its rendered height ≤ 0.4 × viewport with an "Expand" toggle. Tap the toggle and expect the full height. Rebuild from the store and expect the fold to be kept.
- [ ] Implement the capped preview plus toggle in the image block widget (rich editor and reading view).
- [ ] Add a test that the note source bytes are unchanged after folding. Commit.

### Task 1.3: S4 fold list subtrees

Uses the same fold store as Task 1.2, with keys `block:<lineId>`.

- [ ] Write failing tests for: fold hides children; unfold shows them; source bytes unchanged; fold kept after reopen; typing inside an unfolded child still edits.
- [ ] Implement the chevron on bullets that have children. Commit.

### Task 1.4: S5 Mac DB projection

- [ ] Add a test that opens a desktop-managed vault fixture with 50 notes and runs the worker once. Expect DB `nodes` count = 50 and `nodeProjectionComplete` true. Run it and confirm it fails.
- [ ] Find where projection stops for desktop vaults. Start with `graphify path "nodeProjectionComplete" "startCloudPolling"`. Fix it, run the test, commit.
- [ ] Mac: after one app run, `sqlite3 <db> "select count(*) from nodes"` ≈ note count.

### Task 1.5: S6 memory target ≤350 MB

- [ ] Measure the P30 PSS after a search: `adb shell dumpsys meminfo org.tylog.tylog | grep TOTAL`. Record the number.
- [ ] Once Task 1.4 is done, answer queries from DB FTS and drop the in-memory index after 60 s idle. Measure again and record both numbers in `docs/plans/activity-plan.md`.

### Task 1.6: Keep the search query when going back

- [ ] Write a failing test: type a query, open a result, go back, and expect the field to still hold the query and the results to be listed.
- [ ] Keep the query in the route state (`KnowledgeScreen` `initialQuery`). Commit.

### Task 1.7: Release 0.19.2

- [ ] Re-verify every Part 0 "needs attention" row on the Mac and the P30. If any row fails, stop.
- [ ] Update CHANGELOG, run the full `flutter test` + `flutter analyze` + `dart test` in `packages/tylog_core`, tag `v0.19.2`, install on the Mac, P30 and A24.

## Part 2: Unlock hard-coded settings

The codex audit (2026-10-20) found these values tied to the owner's setup:

| Where | Value | Today |
|---|---|---|
| `lib/calendar_feeds.dart:11-12`, used at `lib/workspace_controller.dart:773` | berlogabob.github.io classes and lab feeds | Fallback when the setting is empty |
| `lib/widgets/settings_sheet.dart:115-120` | the same URLs plus group `MCIA003N01` | Dialog defaults |
| `lib/ai/ai_settings.dart:153` | `ollama/ornith-1.5:9b` / `:35b` | Default translate models |
| `lib/screenshots_ocr.dart:25,28,31` and `lib/widgets/screenshots_settings.dart:63` | `/opt/homebrew/bin/uv`, `~/Nextcloud/InstantUpload/Screenshots` | Fixed |
| Scripts repo `config.py:60-61` | `VAULT_ROOT ~/Nextcloud/TyLogVault`, `STUDIO_BASE_URL http://desktop-vdsrh2e:8888/v1` | Env for the vault, Studio fixed |
| `lib/vault.dart:546` | `~/Nextcloud/TyLogVault` fallback | Picker and env override it; keep |

Nextcloud is already fully configurable (server, user, folder, password in secure storage). No API keys or LAN IPs are hard-coded in the app.

### Task 2.1: Calendar feeds without owner defaults

**Files:**
- Modify: `lib/calendar_feeds.dart:11-12` (delete the constants)
- Modify: `lib/workspace_controller.dart:773`
- Modify: `lib/widgets/settings_sheet.dart:115-120`
- Test: `test/calendar_feeds_test.dart`

**Interfaces:**
- Produces: an empty feed URL means "feed off". `workspace_controller` skips that feed.

- [ ] Write two failing tests:
  - `fresh vault fetches no feeds`: empty `settings.json` → zero HTTP requests (fake client counts calls).
  - `keeps saved feed URLs`: `settings.json` with the owner's two URLs → both are fetched.
- [ ] Implement:
  ```dart
  // workspace_controller.dart:773
  final url = (config[key == 'classes' ? 'classesUrl' : 'labUrl'] as String?)?.trim() ?? '';
  if (url.isEmpty) continue; // feed off until the user sets a URL
  ```
  In `settings_sheet.dart`, set the `classesUrl`, `group` and `labUrl` defaults to `''`. Use the hint text "https://…/calendar.ics" in place of real URLs.
- [ ] Before committing, check the owner's real vault `settings.json` holds both URLs (`grep -c berlogabob <vault>/settings.json` ≥ 2). If it doesn't, write them there first, so the upgrade keeps the owner's feeds.
- [ ] Run the tests; expect PASS. Commit "Calendar feeds: no built-in owner URLs; empty URL = off".

### Task 2.2: User-chosen screenshots folder and uv path

**Files:**
- Modify: `lib/screenshots_ocr.dart` (the plist builder takes `scriptsDir`; uv is found on PATH)
- Modify: `lib/widgets/screenshots_settings.dart` (folder picker row)
- Modify: `lib/ai/ai_settings.dart` (`AiServerTask` gets `String? folder`)
- Test: `test/screenshots_ocr_test.dart`

**Interfaces:**
- Produces: `String screenshotPlist({required String mode, required String time, required String vault, required String scriptsDir, required String uvPath, String? home})`.
- Produces: `Future<String?> findUv()`, which checks `/opt/homebrew/bin/uv`, `/usr/local/bin/uv`, `$HOME/.local/bin/uv` and `$HOME/.cargo/bin/uv` and returns the first that exists.
- Produces: `ai.json` `tasks.screenshots.folder`. When it is null the folder defaults to `~/Nextcloud/InstantUpload/Screenshots`, so the owner's install keeps working.

- [ ] Write failing tests:
  - The plist built with `scriptsDir: '/x/Shots'` contains `/x/Shots` and no `Nextcloud`.
  - `findUv` with a temp HOME that has `.local/bin/uv` returns that path.
  - `missing scripts folder`: the health line for a folder without `ollama_ocr.py` is "Screenshot scripts not found in <folder>", and nothing throws.
- [ ] Implement. The picker uses the existing `file_picker` `getDirectoryPath()`. It saves into `ai.json` with `writeAiSettings`, then reinstalls the LaunchAgent.
- [ ] On Android, the folder picker is hidden. Screenshots are processed on the Mac/Studio; the phone only uploads.
- [ ] Run the tests, then commit.

### Task 2.3: Cloud AI providers (local first)

**Files:**
- Modify: `lib/ai/ai_settings.dart` (`AiConnection` gets `bool cloud`)
- Create: `lib/ai/provider_presets.dart`
- Create: `lib/ai/api_keys.dart` (secure storage, key `ai-key:<connectionId>`)
- Modify: `lib/ai/connection_probe.dart` (sends `Authorization: Bearer <key>`, plus `x-api-key` and `anthropic-version` for Anthropic)
- Modify: `lib/widgets/ai_connections_settings.dart` (two groups: "On this network" first, then "Cloud (sends your text off-device)"; API key field saves to secure storage)
- Test: `test/ai_settings_test.dart`, `test/connection_probe_test.dart`

**Interfaces:**
- Produces:
  ```dart
  class ProviderPreset {
    const ProviderPreset(this.kind, this.label, this.url, {this.cloud = false});
    final String kind, label, url;
    final bool cloud;
  }
  const providerPresets = <ProviderPreset>[
    ProviderPreset('openai-compatible', 'Ollama', 'http://localhost:11434/v1'),
    ProviderPreset('openai-compatible', 'Unsloth Studio', 'http://<host>:8888/v1'),
    ProviderPreset('openai-compatible', 'LM Studio', 'http://localhost:1234/v1'),
    ProviderPreset('openai-compatible', 'OpenAI', 'https://api.openai.com/v1', cloud: true),
    ProviderPreset('anthropic', 'Claude (Anthropic)', 'https://api.anthropic.com/v1', cloud: true),
    ProviderPreset('openai-compatible', 'Gemini', 'https://generativelanguage.googleapis.com/v1beta/openai', cloud: true),
    ProviderPreset('openai-compatible', 'Mistral', 'https://api.mistral.ai/v1', cloud: true),
    ProviderPreset('openai-compatible', 'OpenRouter', 'https://openrouter.ai/api/v1', cloud: true),
  ];
  ```
- Produces: `Future<String?> readApiKey(String connectionId)`, `Future<void> writeApiKey(String connectionId, String? key)`.
- Anthropic gets its own `kind` because its native API differs (`/v1/messages`, `x-api-key`). The probe lists models with `GET /v1/models` and the same headers.

- [ ] Write failing tests:
  - `api key not written to ai.json`: save a cloud connection with a key, then read the raw `ai.json` bytes; they don't contain the key.
  - The probe sends a Bearer header for `openai-compatible` and `x-api-key` for `anthropic` (fake HttpClient).
  - Preset order: every local preset comes before every cloud preset.
  - A cloud connection is never picked as a default: `AiSettings()` with one local and one cloud connection resolves tasks to the local one.
- [ ] Implement. Remove the "key not saved, test only" note at `ai_connections_settings.dart:286`.
- [ ] Keep `translateModelFor` defaults (Ornith), but only when a local connection exists. With no connection, the task shows "Choose a model".
- [ ] Run the tests, commit.

Skipped: Genkit Dart (preview since March 2026) and `dartantic_ai`. The app only probes endpoints today; the real AI work runs in the workers, so a framework buys nothing yet. Revisit when the app itself runs chat or agent features.

### Task 2.4: Workers read the endpoint from ai.json (scripts repo)

The worker machines can't read the phone's secure storage. Workers get cloud keys from env (`TYLOG_AI_KEY_<ID>`), and local endpoints from `ai.json`.

**Files (in `~/Nextcloud/InstantUpload/Screenshots`, owner: Ornith, small changes):**
- Modify: `config.py:61`. `STUDIO_BASE_URL` comes from `ai.json` `tasks.screenshots.connection` → `connections[].url`, then env `STUDIO_BASE_URL`, then today's value.
- Test: `test_config.py`

- [ ] Write a failing test: an `ai.json` fixture with a connection URL `http://host-a:8888/v1` → `config.studio_base_url() == 'http://host-a:8888/v1'`.
- [ ] Write a failing test `unreachable host leaves file pending`: point at `http://127.0.0.1:9`, run one pipeline block, and expect no ledger entry for the file and a log line containing "unreachable".
- [ ] Implement, run `uv run pytest -q`, commit in the scripts repo.

## Part 3: Second sync backend

### Task 3.1: Generic WebDAV backend (any server: Nextcloud, ownCloud, Synology, Hetzner Storage Box, rclone serve)

**Files:**
- Modify: `lib/nextcloud_sync.dart`, `lib/widgets/nextcloud_connect_dialog.dart`. Add a "WebDAV (any server)" choice: URL + user + password, no Login Flow v2.
- Modify: `lib/nextcloud_sync/chunked_upload.dart`. Use chunking only when the server is Nextcloud (`status.php` answers); otherwise do a single PUT.
- Test: `test/nextcloud_sync_test.dart`

- [ ] Write failing tests:
  - `no chunking endpoint`: a fake server returns 404 for `/remote.php/dav/uploads`, so a 20 MB file is sent as one PUT.
  - A plain WebDAV URL (no `/remote.php/dav/files/<user>`) lists and syncs the fixture vault.
- [ ] Implement; this is mostly config: the base path comes from the user's URL as-is. Commit.
- [ ] Device check: sync the A24 against `rclone serve webdav` on the Mac over the LAN. 50 notes round-trip with identical hashes.

### Task 3.2: Peer-to-peer spike (decision gate, no app changes merged)

Candidates:
- **Ouisync** (Rust library, MPL-2.0, Flutter app exists, BitTorrent DHT discovery, encrypted repos).
- **iroh 1.0** (Rust, QUIC + NAT traversal; iroh-docs/iroh-blobs for sync; used by Delta Chat). TyLog already ships Rust through flutter_rust_bridge, so either can sit next to `packages/typst_flutter`.
- Syncthing is not embeddable as a library (Go daemon) and is out.

- [ ] In a scratch crate, build each for `aarch64-linux-android` and `aarch64-apple-darwin` and record the .so/.dylib size.
- [ ] Sync a copy of the 9,843-note vault Mac ↔ P30 on the LAN and record:
  - Time to first full sync.
  - Time for one edited note to reach the other device.
  - Idle CPU and battery over 30 min.
  - Behavior with the phone backgrounded (Huawei suspends apps).
- [ ] Gate: pass if the library adds ≤ 15 MB to the APK, an edit arrives in ≤ 30 s over the LAN, and a full sync takes ≤ 10 min. If it passes, write a separate plan for a `SyncBackend` interface with two implementations. If not, keep Nextcloud + WebDAV and log the numbers.

## Verification

- After each task: `flutter analyze`, full `flutter test`; `dart test` in `packages/tylog_core` for Part 1.5.
- Part 2 on the Mac: a fresh vault shows no berlogabob URLs and no Ornith model until a local connection exists. The owner's vault keeps its feeds, models and screenshots, and the health line stays OK.
- Results go as one line per task in `docs/plans/activity-plan.md` (Wave 11).
- Release 0.20.0 only when every Part 2/3.1 task is verified on the Mac and a phone.

Sources for the research rows: [genkit-dart](https://github.com/genkit-ai/genkit-dart), [dartantic_ai](https://pub.dev/documentation/dartantic_ai/latest/), [Ouisync](https://github.com/equalitie/ouisync), [iroh](https://github.com/n0-computer/iroh), [iroh 1.0](https://www.iroh.computer/blog/the-road-to-iroh-1-0).
