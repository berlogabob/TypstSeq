# T13 result

Date: 2026-09-09

- Relevant suites: `flutter test test/workspace_controller_test.dart test/articles_shelf_test.dart test/rich_editor_test.dart` — 143 passed, 0 failed.
- Targeted analysis: `flutter analyze lib/app_mobile.dart lib/workspace_controller.dart test/workspace_controller_test.dart` — no issues.

`_setNoteProperty` and `_rateArticle` now use `WorkspaceController.mutateNote`, so open-buffer edits survive metadata changes and closed notes use ordered read-modify-write. Rating logs are written only after mutation success; failures surface a snack and do not log reading progress. Duplicate refresh calls were removed; mutation refresh remains controller-owned and coalesced.

Scoped diff SHA-256: `65caa305e09e00d865f9a15208b8d4f7a572398b66ea2029886afa3fce040c95`; plain counts: app_mobile 120+/66-, controller 501+/176-, controller tests 941+/187- (includes accepted prior changes).
