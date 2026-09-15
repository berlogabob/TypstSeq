# P09d2a — restart-safe materialization

Date: 2026-09-15  
Status: PASS

The batch runner now checkpoints the source hash and selected target path while
the item remains pending. It then materializes the converted node and commits
the node, immutable revision, and terminal import state. A retry reuses the
checkpointed path even when conversion would choose another collision suffix.

The focused interruption test forces the materializer to fail after observing
the first path. The item remains pending, no revision is committed, and the
second runner uses the same path and finishes with exactly one node and one
revision.

```text
flutter test test/import/legacy_import_runner_test.dart
8 tests passed

dart analyze lib/database/tylog_database.dart \
  lib/import/legacy_import_runner.dart \
  test/import/legacy_import_runner_test.dart
No issues found
```

The UI adapter remains P09d2b. Asset handling and cancellation remain P09d3.
