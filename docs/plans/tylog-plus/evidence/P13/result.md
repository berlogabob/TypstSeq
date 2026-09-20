# P13 progress — incremental FTS5 foundation

Status: DONE

Added a lazy SQLite FTS5 index over node title, content, and JSON attributes. Durable node edits upsert one FTS row in the same transaction; `rebuildNodeSearch` repairs or bootstraps the derived index. Queries use Unicode61 with `remove_diacritics 2`, bounded limits, quoted prefix terms, and tombstone filtering. Existing in-memory search remains the UI fallback until the full UI routing and scale acceptance are complete.

Evidence:

- `flutter test test/database/node_search_fts_test.dart` — 2 passed.
- Full suite: `flutter test` — 688 passed, 2 skipped.
- `flutter analyze lib/database/tylog_database.dart test/database/node_search_fts_test.dart` — clean.

The Knowledge search entry point now prefers the FTS result IDs when the projection is complete, applies the existing tag/status filters, and falls back to the worker/in-memory search on unavailable or incomplete derived data. `refreshNodeSearch` reindexes only supplied IDs and reports the inspected count.

Scale evidence:

- 10,000-node EN/PT/RU corpus, 100 keyword queries: p95 1 ms, max 5 ms.
- Keyword gate: p95 <= 200 ms — PASS.
- `flutter test test/database/node_search_fts_test.dart test/database/p13_fts_latency_test.dart` — 4 passed.
- Full suite: `flutter test` — 690 passed, 2 skipped.
