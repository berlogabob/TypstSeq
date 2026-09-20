# P19 progress — durable annotations

Status: RUNNING

Schema v7 adds `annotations`, keyed to a durable PDF source version and storing page, character start/end, quote, and surrounding context. Reads are ordered by source offset, so navigation does not depend on the current page rendering order. Deleting a source version cascades its annotations rather than leaving dangling anchors.

Deterministic quote reattachment now resolves unique anchors across a re-indexed PDF and reports ambiguous or missing matches without silently moving the highlight.

Evidence:

- `flutter test test/database/annotation_test.dart` — annotation persistence and offset ordering pass.
- `flutter test test/database/tylog_graph_schema_test.dart` — v2→v7 migration passes.
- `flutter analyze lib/database/tylog_database.dart test/database/annotation_test.dart` — clean.
- `flutter test test/pdf_annotation_reattach_test.dart` — moved, ambiguous, and missing anchor behavior is covered.

Remaining work: connect reader selection and surface ambiguous anchors for review.
