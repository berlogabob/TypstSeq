# Tier-A task board

Small tasks, one run each. Update the status column when a task changes state.

**Executors**
- **studio** — Unsloth Studio (`Qwen3-Coder-30B`) through `pi-delegate`. Only self-contained work: one new file plus its test, named function, no reading of the big files (`work_surface.dart`, `nextcloud_sync.dart`, `workspace_controller.dart`).
- **codex** — cross-cutting changes in existing large files, device-evidence bugs, reviews.
- **claude** — coordination, device checks over adb, releases.
- **user** — hands-on checks.

**Studio rule:** Studio serves one model at a time. While a studio coding task runs, the screenshot jobs are paused (`pkill -STOP -f 'backfill.py|reprocess_metadata.py'`) and resumed after (`pkill -CONT -f …`).

**Done means:** `flutter analyze --no-pub` clean, the named test passes, full `flutter test --no-pub` passes, codex data-loss review for anything touching sync, then commit.

## A. Devices (now)

| ID | Task | Who | Verify | Status |
|---|---|---|---|---|
| A1 | Install 0.9.4 on A24 and P30 | claude | `dumpsys package` shows 0.9.4 | done |
| A2 | P30 first sync on 0.9.4 finishes, no conflicts, no re-download loop | claude | `sync_trace.jsonl`: completed, then idle probes | done: startup sync 10 s, polls 4 s, no loop |
| A3 | Search "MONSANTOS" finds the screenshot note on a phone | claude | screenshot of result | done on A24: 2 screenshots + 1 daily found |
| A4 | Journal "Coming up" shows the classes; `@Éti` links it | claude | screenshots | done on the P30: `@tica` and, from 0.10.2, `@Eti` link the Ética class |
| A5 | Edit on P30 reaches A24 (phone to phone) under 30 s | claude | timed with adb | todo |

## B. Sync

| ID | Task | Who | Files | Verify | Status |
|---|---|---|---|---|---|
| B1 | Login Flow v2 client: start flow, poll, return server + login + app password | studio | new `lib/nextcloud_sync/login_flow.dart`, new `test/login_flow_test.dart` (fake HTTP server) | `flutter test test/login_flow_test.dart` | done (Studio draft + 1 fix: absolute poll URL) |
| B2 | Chunked upload v2 client: MKCOL upload dir, PUT chunks, MOVE to destination, resume after a failed chunk | studio | new `lib/nextcloud_sync/chunked_upload.dart`, new `test/chunked_upload_test.dart` | `flutter test test/chunked_upload_test.dart` | done (Studio draft unusable, rewritten; verified on real server) |
| B3 | Wire B1 into the Connect Nextcloud screen: "Sign in with browser" button | codex | settings/connect UI | widget test + A24 check | done; tapped on the P30: browser opens the Nextcloud approval page, app shows "Waiting for approval" (approval itself not completed) |
| B4 | Use B2 for files over 10 MB in the upload path | codex | `webdav_client.dart` | sync tests with a 25 MB file, interrupted once | done; real server: 12 MB round-trip, destination conditions verified |
| B5 | Remote delete takes ~40 s to apply, edits 0–7 s: find why, fix | codex | sync | A24 timing: delete under 15 s | done: P30 delete 12 s (was 31 s) |
| B6 | Phone index scan takes ~150 s with 0 notes parsed: make the all-reused case cheap | codex | `maintenance.dart`, `scanner.dart` | A24 trace `durationMs` under 20 s; no full rebuild after an update | done: P30 index pass 15 s, 1 note parsed (was 42-58 s); post-update rebuild not yet observed |
| B7 | Soak test: 3 devices create, edit, rename, delete and attach; 30 rounds by default, 300 with `SOAK=1` | codex | `test/nextcloud_sync_test.dart` soak group, existing fake | tagged `soak`; file/hash convergence and content-loss oracle | done: 300 rounds passed; fixed stale/orphaned conflicts, NFC/NFD cleanup and cached remote ghosts; focused regressions, analysis and full suite green; data-loss review complete; uncommitted |
| B8 | Coalesce autosaves into one revision envelope per device/note session (gap under 10 min) | codex | note persistence, revision publisher/receiver | 20 saves: one file and one upload per push; gap, peer, restart and retry tests | done: immutable revision IDs retained, durable local grouping, parent history preserved; analysis and full suite green; data-loss review complete; uncommitted |
| B10 | Machine-written `_system/revisions/**` with local missing downloads without a conflict (stale record on P30) | codex | sync | test | done: P30 conflicts 0 |
| B11 | Search tab does nothing while the index rebuilds | codex | search/navigation | widget test | done in code and widget test; Search opens on the P30 after launch (not caught mid-rebuild) |
| B9 | Release with B1–B11 | claude | — | GitHub release green, 3 devices updated | done: 0.10.0 published (all assets), 0.10.1 tagged; P30 and Mac updated, A24 still on 0.9.4 |

## C. Screenshots (Studio, already automated)

| ID | Task | Who | Verify | Status |
|---|---|---|---|---|
| C1 | Reprocess notes without tags (about 200) with GLM-OCR + qwen | studio job | notes with tags ≥ 90% | done: 348 of 349 notes have tags |
| C2 | Backfill remaining screenshots | studio job | `backfill-full.log` reaches the end | running (`--only-processed`, then `--only-new`) |
| C3 | Category coverage check on a 30-note sample | claude | `measure.py`: category ≥ 90%, app ≥ 90% | done: 30-note sample 93.3% category, 100% app; all 417 notes 94.7% / 99.8% |

## D. User

| ID | Task | Status |
|---|---|---|
| D1 | P12: type on the phone with predictive text and swipe, check nothing duplicates and sync still runs | todo |
| D2 | P26: seven-day trial with TyLog as the only journal | todo |

## E. After 0.11.0

| # | Task | Who | Status |
|---|------|-----|--------|
| E1 | Search index load/write dominates the phone index pass (P30: load-search 6.3 s, write-search 6.7 s, worker-load-search 5.0 s, list-stat 4.9 s, build-search 2.8 s; note scan 2 s) — make it incremental or skip when no note text changed | codex | todo |
| E2 | Incremental note index (branch `wip/incremental-index`): spins at 90% CPU on the P30 and stops syncing; 4 stale-index cases from review (NFC receipts, service vs worker cache, same-content, both-missing) | codex | parked |
| E3 | Sync `list-remote` costs 8–10 s per run; use notify_push file ids to fetch only the changed files | codex | todo |
| E4 | Background delivery when the app is suspended | — | not started |
