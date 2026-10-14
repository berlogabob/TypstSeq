# Activity plan (auto mode, started 2026-10-14)

Rules: Claude coordinates; codex CLI does multi-file edits; pi + Ornith 35b on Studio does new small files, scripts, docs and tests (read every diff); haiku Explore for read-only digging. Every slice: analyze + FULL flutter test green, graphify update, visual check on P30 (adb) and the Mac app, then commit. No release before the user confirms GUI. New issues go to the log below and into the queue.

## Queue (in order)
1. D3 dialogs, sheets, notices  [in progress, codex]
2. D4 icon sweep (app_icons.dart)
3. Release 0.18.0 candidate (D1-D4 + presets): install on P30 + Mac, A24 when connected; user confirms; then tag
4. D5 Today/Journal/Search consistency, editor menu naming, Split view entry, `/` palette Task, graph chips
5. D6 component themes, raw colours/fonts to tokens, dark hint colour
6. AI: Articles card in AI settings (tasks.articles), screenshot script reads ai.json, real-key check, schedule 03:00 test, RAG docs corpus
7. Verify on both platforms after each slice (Mac app: update from release zip; for unreleased UI use `flutter build macos`)

## Issue log
- 2026-10-14: full flutter test is blocked inside the codex sandbox (localhost sockets, disk); Claude runs the full suite after every codex slice.
- 2026-10-14: A24 not reachable over adb since the 0.17.3 release; still on 0.17.0.
- 2026-10-14: Mac app is 0.17.3; D1/D2 UI not yet on Mac (needs a local macOS build or the 0.18.0 zip).
