# P08 — atomic edits and durable work queues

Date: 2026-09-15. Status: PASS.

Schema version 4 adds an upload outbox and a derived-data invalidation queue keyed by immutable revision IDs. `commitNodeEdit` upserts node content, inserts its revision, and queues both downstream actions in one SQLite transaction. Revision identity must match the edited node.

SQLite triggers reject revision updates and deletes. Queue lifecycle, retries, upload batches, job cancellation, and scheduling remain owned by P14 and P15.

## Verification

```bash
dart run build_runner build
flutter test test/database
flutter analyze lib/database test/database
flutter test
```

- Twenty-three database checks passed.
- A forced duplicate-revision failure after the node upsert rolls the content change and all new rows back.
- Successful edits leave exactly one matching revision, outbox row, and invalidation row.
- Revision/entity mismatch fails before any write.
- Revision mutation/deletion fails at the database boundary.
- A rehearsed v3-to-v4 migration preserves existing data and creates both queues and guards.
- The full Flutter suite passed: 622 tests, with one existing skipped test.

Codex `gpt-5.6-luna` was assigned the design scan but was stopped after its bounded window without returning a result. The coordinator implemented the minimal transaction and schema. A separate `gpt-5.6-luna` reviewer returned PASS; provider usage was unavailable.
