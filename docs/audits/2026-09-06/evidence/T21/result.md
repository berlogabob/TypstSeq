# T21 verification

Date: 2026-09-09

Implementation: `_sharePdf` starts and retains an asset-load future for the captured source, waits for it to settle, snapshots source/files/name consistently, and rejects revision, note, vault, or source changes before sharing. Compile and share callbacks are optional HomeScreen test seams; production defaults remain `compileSourcePdf` and `_sharePdfBytes`. Missing assets use the real compiler path and surface the existing Typst error dialog without sharing.

Commands and results:

- `flutter test test/widget_test.dart --plain-name 'share PDF' --reporter expanded` — 3 passed (gated asset load/files, real missing-asset error/no share, stale export after note switch).
- `flutter test test/widget_test.dart --plain-name 'KnowledgeScreen' --reporter expanded` — 6 passed (T19 regression and replacement-state review).
- `flutter test test/widget_test.dart --plain-name 'saved searches stay current across saves, delete, and failure' --reporter expanded` — 1 passed.
- `flutter test test/widget_test.dart --plain-name 'saved-search controls stay locked during a delayed write' --reporter expanded` — 1 passed.
- `flutter analyze lib/app_mobile.dart lib/knowledge_screen.dart test/widget_test.dart` — no errors; 3 pre-existing infos in `knowledge_screen.dart`.
- `git diff --check` — clean.
- `graphify update .` — completed.

Final SHA-256:

- `lib/app_mobile.dart`: `1b9fe29bd2865a56aa896d844e46af7117f6024cdb64c4e39cc4e77646d5873a`
- `lib/knowledge_screen.dart`: `ea861cabc802b43f5f4236854329d8bd0d2f35cd461825459a61c2c50a617c6e`
- `test/widget_test.dart`: `cc6e3dd672822f4e22cb7e2ae4db5ec95ae16d96bc3ecf86e35db5b57fd89470`
