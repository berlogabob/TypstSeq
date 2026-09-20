# P15 progress — durable revision publication

Status: DONE

Added a storage-level publication seam over the existing outbox. `pendingRevisionUploads` returns bounded revision/node payloads; `RevisionPublisher` materializes them as `_system/revisions/*.json`, invokes the existing Nextcloud file-sync path, and acknowledges only a conflict-free completed sync. Failed or interrupted uploads leave the outbox row untouched for retry. Binary attachments already live under `assets/`, which is a syncable vault prefix handled by the same retrying transfer engine; no second attachment queue is needed.

Evidence:

- `flutter test test/database/revision_outbox_test.dart` — 1 passed.
- `flutter test test/nextcloud_sync_test.dart` — asset transfer/conflict coverage passed.
- `flutter analyze lib/database/tylog_database.dart test/database/revision_outbox_test.dart` — clean.
- `flutter test test/database/revision_publisher_test.dart` — 3 passed.
- `flutter analyze lib/workspace_controller.dart lib/database/revision_publisher.dart` — clean.

Combined full suite after the P14–P16 storage changes: `flutter test` — 693 passed, 2 skipped.
