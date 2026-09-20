# P15 progress — durable revision publication

Status: RUNNING

Added a storage-level publication seam over the existing outbox. `pendingRevisionUploads` returns bounded revision/node payloads; successful publishers call `acknowledgeRevisionUpload`. Failed or interrupted uploads leave the outbox row untouched for retry.

Evidence:

- `flutter test test/database/revision_outbox_test.dart` — 1 passed.
- `flutter analyze lib/database/tylog_database.dart test/database/revision_outbox_test.dart` — clean.

Combined full suite after the P14–P16 storage changes: `flutter test` — 693 passed, 2 skipped.

Remaining P15 work: connect this contract to the Nextcloud publisher and include attachment payload publication/retry.
