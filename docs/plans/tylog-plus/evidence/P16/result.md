# P16 progress — transactional revision receive

Status: DONE

Added `receiveRevision` to the durable database boundary and wired revision envelopes into the sync coordinator. A matching parent applies atomically and updates derived invalidations without re-queueing a publication; an already-seen revision is idempotent; a divergent parent returns `conflict` without changing local rows. Malformed envelopes are retained for retry.

Evidence:

- `flutter test test/database/revision_receive_test.dart` — 1 passed.
- `flutter analyze lib/database/tylog_database.dart lib/database/revision_publisher.dart lib/workspace_controller.dart` — clean.

Combined full suite after the P14–P16 storage changes: `flutter test` — 693 passed, 2 skipped.

Cross-device transport now uses the existing `_system/` sync path; divergent revisions remain available for conflict handling rather than being acknowledged.
