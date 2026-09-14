# T09 result

Date: 2026-09-09

Focused gated regressions: `flutter test test/workspace_controller_test.dart --plain-name='late'` — 3 passed, including stale open success/failure, stale sync success/failure, and stale scan after close. Each released operation completed within the test's 1 second bound.

Full controller suite: `flutter test test/workspace_controller_test.dart` — 43 passed, 0 failed.

Targeted analysis: `flutter analyze lib/workspace_controller.dart test/workspace_controller_test.dart` — no issues.

Scoped diff fingerprint: SHA-256 `2137a198b31d4ba483a52f4bbbf5666a9ba6a7d271ca670b94e109bede6dae08` for the current diff of `lib/workspace_controller.dart` and `test/workspace_controller_test.dart` (includes accepted T03–T07 changes). Plain diff counts: controller 411 additions/176 deletions; tests 766 additions/187 deletions.

Known limit: the suite logs expected simulated WebDAV failures; these are handled by the tests and do not fail the run. Device/native validation remains outside T09.
