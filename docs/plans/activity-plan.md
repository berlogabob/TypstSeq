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
