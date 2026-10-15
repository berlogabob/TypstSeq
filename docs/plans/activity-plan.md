# Activity plan (auto mode, started 2026-10-14)

Rules: Claude coordinates; codex CLI does multi-file edits; pi + Ornith 35b on Studio does new small files, scripts, docs and tests (read every diff); haiku Explore for read-only digging. Every slice: analyze + FULL flutter test green, graphify update, visual check on P30 (adb) and the Mac app, then commit. No release before the user confirms GUI. New issues go to the log below and into the queue.

## Queue (in order)
1. D3 dialogs, sheets, notices  [done 2026-10-15, 1498 tests green, P30 checked: More, Library, Insert sheet]
2. D4 icon sweep (app_icons.dart)  [done 2026-10-15, 1498 green, P30 checked; agenda icon clash fixed]
3. Release 0.18.0 candidate  [version bumped + changelog committed 2026-10-15, NOT tagged; waiting for user GUI confirmation] (D1-D4 + presets): install on P30 + Mac, A24 when connected; user confirms; then tag
4. D5 Today/Journal/Search consistency, editor menu naming, Split view entry, `/` palette Task, graph chips
5. D6 component themes, raw colours/fonts to tokens, dark hint colour
6. AI: Articles card in AI settings (tasks.articles), screenshot script reads ai.json, real-key check, schedule 03:00 test, RAG docs corpus
7. Verify on both platforms after each slice (Mac app: update from release zip; for unreleased UI use `flutter build macos`)

## Issue log
- 2026-10-14: full flutter test is blocked inside the codex sandbox (localhost sockets, disk); Claude runs the full suite after every codex slice.
- 2026-10-14: A24 not reachable over adb since the 0.17.3 release; still on 0.17.0.
- 2026-10-14: Mac app is 0.17.3; D1/D2 UI not yet on Mac (needs a local macOS build or the 0.18.0 zip).
- 2026-10-15: D3 Insert sheet shows title 'Insert' above group heading 'Insert' (duplicate). Fix in D5: sheet title 'Add to note', groups Insert / Text style / Structure.
- 2026-10-15: editor dock on P30 is a single scrolling row; Insert (+) is last, off-screen on first view. Consider moving Insert to the first slot in D5.
- 2026-10-15: codex modifies ~1300 lines per sweep (re-indentation from wrapping); always run the full suite and a P30 check before committing.
- 2026-10-15: Mac visual check impossible while the screen is locked (lock screen at 00:18); debug macOS build compiles and launches (flutter build macos --debug ok). Redo Mac checks when the user is at the Mac; do not try to unlock.
- 2026-10-15: D4 sweep changed agenda icon to view_agenda (same as group-by); fixed to checklist_outlined. Lesson: after icon sweeps look at Today, Library, Settings on P30.
- 2026-10-15: earlier bare `git push -q` silently skipped (no upstream); use `git push -q origin HEAD`.
- 2026-10-15: D5 done and checked on P30 (Add to note sheet, + first in dock, Split in view popup); Date icon changed to calendar_month grid (D4) - fine.
- 2026-10-15: D6 regression: dropping the app-level `inputDecorationTheme(border: none)` boxed the editor (then underline); restored in tyLogTheme, test pins it. Lesson: always screenshot Today (editor) after any theme change.
- 2026-10-15: Vaults sheet shows raw `content://com.android.exte...` as the vault subtitle; show a friendly path (D7 candidate).
- 2026-10-15: AI settings section: sub-headers weak (Articles/Screenshots titles look like field values); polish in D7 together with the Vaults subtitle. A24 still needs the install.
- 2026-10-15: D7 done: Vaults friendly path, AI task block headers. No new releases until the user asks.

## Wave 2 (2026-10-15, user: "do all 3", then ONE release; codex+pi max, Claude reviews)
W1 Module Packs phase C: (a) upgrade removes files dropped by the new pack (unedited only); (b) Reschedule: shift due of open module tasks to a new start date (surgical writes, task_mutation); (c) Progress: per-module done/total tasks + scores in the module dialog; (d) docs/modules/AUTHORING.md + manifest.schema.json (pi).
W2 RAG docs corpus: bundled docs (spec/, docs/modules/) indexed under `doc:` source ids in lib/retrieval, searchable alongside notes.
W3 Audio: peak backfill for pack mp3s (waveform without first open); A24 device checks pending (needs adb).
Release after W1-W3: full test, tag, install P30/Mac/A24.
- 2026-10-15: W1 core+UI, W2 RAG docs corpus done (1510 green); W3 audio: peaks backfill left to first open per plan; moduleProgress reads record paths, not a vault listing (SAF cost).
- 2026-10-15: P30 test in an empty vault (Download/TyLogModTest): install 72 notes + 99 mp3 OK, Modules sheet "0/72 tasks", Reschedule +5 days shifted all due dates and start (~50 s), Uninstall removed all 171 files (~70 s). Test vault removed from use; TyLog vault active again.
- 2026-10-15 ISSUE: Reschedule and Uninstall show no progress UI for ~50-70 s on SAF; add a progress dialog (like Install).
- 2026-10-15 ISSUE: Vaults sheet showed "SD card//storage/emulated…" for a Downloads-provider tree uri (raw:/storage/...); friendlyVaultPath now maps raw: to Internal storage (fixed, unreleased).
- 2026-10-15 OPEN: prebuilt peaks for pack audio (pack.py computes 200 buckets, app draws lesson attachment waveform from stored peaks) awaiting user decision.
- 2026-10-15: peak sidecars done: pack.py (BerloPortuga, 1.1.0) writes `<mp3>.peaks` (200 hex buckets) and manifest `unit: lessons`; app reads sidecar before codec decode (AudioInlineCard.readPeaks). P30 check: pack 1.1.0 installed in test vault (198 asset files, 99 .peaks), Modules shows "0/72 lessons", lesson 1 waveform drawn at once. Reschedule/Uninstall now show a progress dialog (not re-timed on device).
- 2026-10-15 ISSUE: after Uninstall empty folders (projects/<id>, assets/modules/<id>) remain in the vault; harmless, SAF dir delete not implemented.
- 2026-10-15 NOTE: pack.py in BerloPortuga is not under git (no repo); dist/pt-pt-a2b1.tylogpack 1.1.0 is the build to publish with the next release.

## Wave 3: pre-release checks for 0.18.1 (2026-10-15, user: Mac unlocked, A24 connected, "whole scope")
C1 pack upgrade 1.0.0 -> 1.1.0 on device (adds 99 .peaks, unit, edited note kept)
C2 RAG docs search on device (P30 + Mac)
C3 Nextcloud sync of pack files (.peaks, 198 assets)
C4 Mac visual check D1-D7, Modules sheet
C5 A24: install, record, import mp3, waveform
C6 real server key: articles/screenshots task cards, 03:00 schedule
C7 housekeeping: BerloGPortuga git init, upload pack 1.1.0 to release, empty dirs after uninstall
Then: tag v0.18.1+151, install everywhere.
- 2026-10-15 ISSUE (Mac 0.18.1 real vault 5046 notes): Search tab 'Search failed. Try again.' for query 'tylogpack manifest sha256'; investigate (RAG doc kind? FTS syntax?)
- 2026-10-15 FIXED: Mac "Search failed" = query embedder ran on the UI isolate before RustLib was initialised there ("flutter_rust_bridge has not been initialized"); nativeEmbedder now initialises it once via TypstCompiler.create(). Affected semantic search on every desktop/phone start until a Typst compile ran. Verified on Mac debug: search works, docs corpus results (AUTHORING.md, PACK-SPEC.md) appear.
- 2026-10-15 INCIDENT: blind adb taps on P30 after app relaunch (keyboard was open, active vault was the REAL TyLog) typed junk ('п', 'р-н р-н р-н р-н') into today's note; deleted it at once (Today empty again) but a sync cycle was running; check the 2026-10-15 daily in the real vault has no stray text. RULE: screenshot before every blind tap sequence; check active vault first.
- 2026-10-15 C1 DONE on P30 (test vault): 1.0.0 installed, lesson 5 edited via adb, Update to 1.1.0 -> 99 .peaks added, unit "lessons", edit kept, 72 notes / 198 assets. Uninstall showed "Removing module" dialog. Vaults sheet now shows "Internal storage/Download…" for the Downloads-provider vault.
- 2026-10-15 C3 DONE by code: isSyncableVaultPath is prefix based (assets/, projects/, _system/), no extension filter, so .peaks and module records sync.
- 2026-10-15 C4 DONE on Mac (0.18.1 release build, real vault): More, Settings, Library toolbar/chips/tabs match the design; Search failure found and fixed (see above).

## Wave 4 (2026-10-15): pack docs + example pack repo (proposal, awaiting user go)
- docs/modules/AUTHORING.md grows into a step-by-step guide; spec stays in this repo (authoritative); example pack repo `tylog-pack-pt-pt` (from BerloPortuga: sources, tools/pack.py with peaks, CI building the .tylogpack onto a GitHub release) is the worked example the guide links to.
- 0.18.1+151 released 2026-10-15: pack 1.1.0 attached; installed on P30, A24, Mac.
