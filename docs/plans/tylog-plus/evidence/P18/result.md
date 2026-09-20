# P18 progress — PDF extraction contract

Status: RUNNING

Added a parser-neutral extraction boundary in `lib/pdf/pdf_extraction.dart`. A platform PDF reader supplies one nullable text value per page; TyLog records the source-version ID, PDF SHA-256, page number, combined character offsets, and an explicit status. Invalid bytes and image-only PDFs are accounted for instead of being silently indexed as empty text. SQLite schema v6 persists those records in `source_versions` with a source/time index.

Evidence:

- `flutter test test/pdf_extraction_test.dart` — 3 passed.
- `flutter analyze lib/pdf/pdf_extraction.dart test/pdf_extraction_test.dart` — clean.
- `flutter test test/database/pdf_source_version_test.dart test/database/tylog_graph_schema_test.dart` — 11 passed, including v2→v6 migration.
- `flutter analyze lib/database/tylog_database.dart lib/pdf/pdf_extraction.dart test/database/pdf_source_version_test.dart` — clean.

Remaining P18 work: connect a native PDF reader and add selection/navigation integration. The contract is deliberately independent of that reader so changing PDF backends does not move existing anchors.
