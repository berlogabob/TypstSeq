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
| E1 | Search index load/write per pass — 0.11.1: loaded once, write deferred (5 min / background / close). P30 per changed note: write-search 6.7 s → 0.01 s, load-search 0. Left: `durationMs` 12 s for one parsed note (list-stat, support files, index write) and build-search 3 s (rebuilds all task/attachment documents and postings)  0.11.2 stage timings on P30 for one changed note: list-stat 7-10 s (SAF walk; whole-vault listing cache is dropped by every vault write and has a 60 s TTL), build-search 2.3 s, support-files 1.5 s, validate 1.4 s, encode+write index 1.2 s. Tried and reverted: concurrent shallow SAF listing (slower), search posting reuse (0.7 s). Rejected as unsafe: deferred index write (nextNoteId/nextTaskId read it), support-file metadata cache. Next: patch the SAF listing cache per written folder instead of dropping it | codex | partly done |
| E2 | Incremental note index (branch `wip/incremental-index`): spins at 90% CPU on the P30 and stops syncing; 4 stale-index cases from review (NFC receipts, service vs worker cache, same-content, both-missing) | codex | parked |
| E3 | `list-remote`: 0.11.2 lists sibling folders concurrently, P30 7.3 s → 4.5-5 s (8 folders, 4 serial hops at ~1.1 s each). Further cut needs notify_push file ids or one REPORT instead of a Depth:1 walk | codex | partly done |
| E4 | Background delivery when the app is suspended | — | not started |
