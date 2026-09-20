# P13 progress — incremental FTS5 foundation

Status: RUNNING

Added a lazy SQLite FTS5 index over node title, content, and JSON attributes. Durable node edits upsert one FTS row in the same transaction; `rebuildNodeSearch` repairs or bootstraps the derived index. Queries use Unicode61 with `remove_diacritics 2`, bounded limits, quoted prefix terms, and tombstone filtering. Existing in-memory search remains the UI fallback until the full UI routing and scale acceptance are complete.

Evidence:

- `flutter test test/database/node_search_fts_test.dart` — 2 passed.
- Full suite: `flutter test` — 688 passed, 2 skipped.
- `flutter analyze lib/database/tylog_database.dart test/database/node_search_fts_test.dart` — clean.

Remaining P13 work: route keyword search surfaces through this API, add changed-record rebuild accounting, and measure EN/PT/RU full-corpus latency.
