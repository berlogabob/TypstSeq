# T17 result

## Change

`_showKnowledge` now closes over a mutable current saved-search list and advances it only after `SavedSearchStore.save` succeeds. `KnowledgeScreen` keeps its own current list, updates chips after successful save/delete, and reports persistence errors while retaining the previous chips.

## Verification

- `graphify query` scoped the investigation to `app_mobile.dart`, `knowledge_screen.dart`, and saved-search code.
- `graphify update .` completed successfully (21 files extracted; unrelated pre-existing dirty files remain).
- `git diff --check` passed.
- `flutter test test/widget_test.dart --plain-name 'saved searches'`: 2 passed.
- `flutter test test/widget_test.dart --plain-name 'delayed write'`: 1 passed.
- The audit reproduction's saved-search test passed; its full run had 3 passes and 2 unrelated failures (T07/T05).
- `flutter analyze lib/app_mobile.dart lib/knowledge_screen.dart test/widget_test.dart`: 0 errors, 3 existing style/info lints.

## Counts

- Production files changed: 2
- New dependencies: 0
- New tests: 1 widget regression covering two saves, delete, and failed save.

Scoped file SHA-256: `lib/app_mobile.dart` 2e7b34862cbf616b1c923753991046039c50e0f8004e85845be5225ec148488a; `lib/knowledge_screen.dart` bb346fc391ee1e0b63598666fe7f8451c62d42693c5f21a6688124f8591b63b9; `test/widget_test.dart` 03148fbf3eea1075f5e1fcbc93830c6c61bd39d837e2ea95b1c0ddd51fdc11d5.

## Limitations

The analyzer reports only style/info lints; no T17 errors remain.

Coordinator accepted 2026-09-08: actual app storage audit probe preserves First+Second; two focused tests and delayed-write guard regression pass. UI/persistence diff reviewed.
