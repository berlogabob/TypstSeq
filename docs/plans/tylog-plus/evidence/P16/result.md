# P16 progress — transactional revision receive

Status: RUNNING

Added `receiveRevision` to the durable database boundary. A matching parent applies atomically and updates derived invalidations without re-queueing a publication; an already-seen revision is idempotent; a divergent parent returns `conflict` without changing local rows.

Evidence:

- `flutter test test/database/revision_receive_test.dart` — 1 passed.
- `flutter analyze lib/database/tylog_database.dart test/database/revision_receive_test.dart` — clean.

Combined full suite after the P14–P16 storage changes: `flutter test` — 693 passed, 2 skipped.

Remaining P16 work: connect the receive contract to the sync transport and add cross-device convergence/retry evidence.
