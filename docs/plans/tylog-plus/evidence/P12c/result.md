# P12c result — bounded node-summary pages

Status: DONE

Added `TyLogDatabase.pageNodeSummaries` with a bounded keyset query over `nodes`. It returns only list fields (`id`, `type`, `title`, `attributes_json`, `updated_at_ms`), caps requests at 100 rows, and returns an ID cursor. `nodeProjectionComplete` / `markNodeProjectionComplete` expose an explicit projection-completeness marker so list surfaces can choose paged reads or the existing index fallback during migration.

Evidence:

- Focused test: `flutter test test/database/node_summary_page_test.dart` — 2 passed.
- Full suite: `flutter test` — 684 passed, 2 skipped.
- Static checks: `flutter analyze lib/database/tylog_database.dart test/database/node_summary_page_test.dart` — clean.

P12d remains responsible for wiring Library, Articles, and picker surfaces to this API. The current slice intentionally leaves existing UI behavior unchanged.
