# P19 progress — durable annotations

Status: RUNNING

Schema v7 adds `annotations`, keyed to a durable PDF source version and storing page, character start/end, quote, and surrounding context. Reads are ordered by source offset, so navigation does not depend on the current page rendering order. Deleting a source version cascades its annotations rather than leaving dangling anchors.

Evidence:

- `flutter test test/database/annotation_test.dart` — annotation persistence and offset ordering pass.
- `flutter test test/database/tylog_graph_schema_test.dart` — v2→v7 migration passes.
- `flutter analyze lib/database/tylog_database.dart test/database/annotation_test.dart` — clean.

Remaining work: connect reader selection and reattachment scoring, then surface ambiguous anchors for review.
