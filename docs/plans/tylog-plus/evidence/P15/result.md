# P15 progress — durable revision publication

Status: RUNNING

Added a storage-level publication seam over the existing outbox. `pendingRevisionUploads` returns bounded revision/node payloads; `RevisionPublisher` materializes them as `_system/revisions/*.json`, invokes the existing file-upload seam, and acknowledges only successful uploads. Failed or interrupted uploads leave the outbox row untouched for retry.

Evidence:

- `flutter test test/database/revision_outbox_test.dart` — 1 passed.
- `flutter analyze lib/database/tylog_database.dart test/database/revision_outbox_test.dart` — clean.
- `flutter test test/database/revision_publisher_test.dart` — 2 passed.

Combined full suite after the P14–P16 storage changes: `flutter test` — 693 passed, 2 skipped.

Remaining P15 work: invoke this publisher from the Nextcloud sync coordinator and include attachment payload publication/retry.
