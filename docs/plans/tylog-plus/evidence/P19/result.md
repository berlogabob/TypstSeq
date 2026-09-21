# P19 progress — durable annotations

Status: RUNNING

Schema v7 adds `annotations`, keyed to a durable PDF source version and storing page, character start/end, quote, and surrounding context. Reads are ordered by source offset, so navigation does not depend on the current page rendering order. Deleting a source version cascades its annotations rather than leaving dangling anchors.

Deterministic quote reattachment now resolves unique anchors across a re-indexed PDF and reports ambiguous or missing matches without silently moving the highlight.

The storage seam now supports manual reassignment: `reassignPdfReaderSelection` validates a new page range and updates the existing annotation identity, quote, context, and offsets atomically. Focused reader-store and reattachment tests pass.

Evidence:

- `flutter test test/database/annotation_test.dart` — annotation persistence and offset ordering pass.
- `flutter test test/database/tylog_graph_schema_test.dart` — v2→v7 migration passes.
- `flutter analyze lib/database/tylog_database.dart test/database/annotation_test.dart` — clean.
- `flutter test test/pdf_annotation_reattach_test.dart` — moved, ambiguous, and missing anchor behavior is covered.

Remaining work: expose reassignment from the review UI, synchronize annotation revisions, and run corpus-scale acceptance. Reader selection and review status are wired.

## Reader integration (2026-09-20)

The reader saves selected page ranges with exact quote, surrounding context, version identity and global UTF-16 offsets. Multi-page saves are transactional; repeated saves are idempotent. The Highlights drawer navigates back to selected text. Prior-version quotes are resolved only when unique; repeated/overlapping or missing matches display Needs review and do not silently move. Annotation reattachment stops at the second match. Native select/save/reopen/navigation passed on A24 using an isolated debug package and synthetic PDF.

Remaining: manual reassignment of ambiguous anchors, annotation synchronization, private corpus acceptance. Mac and A24 native selection smoke tests pass.
