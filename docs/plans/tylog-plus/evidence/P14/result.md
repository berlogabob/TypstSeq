# P14 result — persistent resumable jobs

Status: DONE

The existing import job tables now expose the complete control contract: idempotent creation/resume, bounded pending batches, explicit cancellation, and rejection of stale worker results after cancellation. Completed jobs remain terminal; cancelled jobs can be reopened and resumed without duplicating items.

Evidence:

- `flutter test test/database/tylog_import_schema_test.dart` — 11 passed.
- Full suite before this checkpoint: 690 passed, 2 skipped.
- `flutter analyze lib/database/tylog_database.dart test/database/tylog_import_schema_test.dart` — clean.
