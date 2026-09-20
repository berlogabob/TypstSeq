# P15 progress — durable revision publication

Status: RUNNING

Added a storage-level publication seam over the existing outbox. `pendingRevisionUploads` returns bounded revision/node payloads; successful publishers call `acknowledgeRevisionUpload`. Failed or interrupted uploads leave the outbox row untouched for retry.

Evidence:

- `flutter test test/database/revision_outbox_test.dart` — 1 passed.
- `flutter analyze lib/database/tylog_database.dart test/database/revision_outbox_test.dart` — clean.

Remaining P15 work: connect this contract to the Nextcloud publisher and include attachment payload publication/retry.
