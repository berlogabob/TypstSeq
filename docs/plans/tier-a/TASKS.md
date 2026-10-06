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
| A2 | P30 first sync on 0.9.4 finishes, no conflicts, no re-download loop | claude | `sync_trace.jsonl`: completed, then idle probes | todo |
| A3 | Search "MONSANTOS" finds the screenshot note on a phone | claude | screenshot of result | todo |
| A4 | Today arrow to Wed 8 Oct shows the class; `@Éti` links it | claude | screenshots | todo |
| A5 | Edit on P30 reaches A24 (phone to phone) under 30 s | claude | timed with adb | todo |

## B. Sync

| ID | Task | Who | Files | Verify | Status |
|---|---|---|---|---|---|
| B1 | Login Flow v2 client: start flow, poll, return server + login + app password | studio | new `lib/nextcloud_sync/login_flow.dart`, new `test/login_flow_test.dart` (fake HTTP server) | `flutter test test/login_flow_test.dart` | todo |
| B2 | Chunked upload v2 client: MKCOL upload dir, PUT chunks, MOVE to destination, resume after a failed chunk | studio | new `lib/nextcloud_sync/chunked_upload.dart`, new `test/chunked_upload_test.dart` | `flutter test test/chunked_upload_test.dart` | todo |
| B3 | Wire B1 into the Connect Nextcloud screen: "Sign in with browser" button | codex | settings/connect UI | widget test + A24 check | todo (after B1) |
| B4 | Use B2 for files over 10 MB in the upload path | codex | `webdav_client.dart` | sync tests with a 25 MB file, interrupted once | todo (after B2) |
| B5 | Remote delete takes ~40 s to apply, edits 0–7 s: find why, fix | codex | sync | A24 timing: delete under 15 s | todo |
| B6 | Phone index scan takes ~150 s with 0 notes parsed: make the all-reused case cheap | codex | `maintenance.dart`, `scanner.dart` | A24 trace `durationMs` under 20 s | todo |
| B7 | Soak test: 3 simulated devices edit, rename, delete for 500 rounds, must converge | codex | new `test/sync_soak_test.dart` | test passes, tagged slow | todo |
| B8 | One revision file per save (no revision churn on autosave) | codex | sync revisions | existing 22 revision tests + new one | todo |
| B9 | Release with B1–B8 | claude | — | GitHub release green, 3 devices updated | todo |

## C. Screenshots (Studio, already automated)

| ID | Task | Who | Verify | Status |
|---|---|---|---|---|
| C1 | Reprocess notes without tags (about 200) with GLM-OCR + qwen | studio job | notes with tags ≥ 90% | running |
| C2 | Backfill remaining screenshots | studio job | `backfill-full.log` reaches the end | queued after C1 |
| C3 | Category coverage check on a 30-note sample | claude | `measure.py`: category ≥ 90%, app ≥ 90% | todo (after C1) |

## D. User

| ID | Task | Status |
|---|---|---|
| D1 | P12: type on the phone with predictive text and swipe, check nothing duplicates and sync still runs | todo |
| D2 | P26: seven-day trial with TyLog as the only journal | todo |
