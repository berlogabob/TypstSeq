# P07 — authoritative graph, source, and revision schema

Date: 2026-09-15. Status: PASS.

Schema version 3 adds typed nodes, typed edges, sources, and immutable revisions. Stable text IDs are independent of paths. Event and relationship-validity ranges are separate from creation/update timestamps. Optional attributes and revision payloads are JSON validated by SQLite.

Indexes cover node type/update reads, both typed edge traversal directions, edge updates, source kind, revision history by entity/time, and revision parents. Edge endpoints and revision parents use restrictive foreign keys. Migrations from versions 1 and 2 preserve the existing metadata table and create the complete schema; unsupported versions fail closed.

## Verification

```bash
dart run build_runner build
flutter test test/database/tylog_database_test.dart test/database/tylog_graph_schema_test.dart
flutter analyze lib/database/tylog_database.dart test/database/tylog_database_test.dart test/database/tylog_graph_schema_test.dart
flutter test
```

- Eighteen focused native database tests passed.
- The tests exercise an atomic source/node/edge/revision write, missing edge endpoints, duplicate-ID rollback, invalid JSON, invalid temporal ranges, null and distinct event dates, v1/v2 migrations, revision ancestry, and database pragmas.
- Focused analysis reported no issues.
- The full Flutter suite passed: 617 tests, with one existing skipped test.

Claude Haiku `claude-haiku-4-5-20251001` generated the initial schema and tests but was interrupted after exceeding the bounded runtime; its CLI did not report token/cost totals. The coordinator corrected false-positive rollback/null-date tests, removed redundant indexes, simplified migration branching, and added SQLite constraints. Codex `gpt-5.6-luna` independently reviewed the corrected result and returned PASS; provider usage was unavailable.
