# P19 progress — durable annotations

Status: HOST ACCEPTED / DEVICE VERIFIED / SYNC READY

Schema v7 adds `annotations`, keyed to a durable PDF source version and storing page, character start/end, quote, and surrounding context. Reads are ordered by source offset, so navigation does not depend on the current page rendering order. Deleting a source version cascades its annotations rather than leaving dangling anchors.

Deterministic quote reattachment now resolves unique anchors across a re-indexed PDF and reports ambiguous or missing matches without silently moving the highlight.

The storage seam now supports manual reassignment: `reassignPdfReaderSelection` validates a new page range and updates the existing annotation identity, quote, context, and offsets atomically. Focused reader-store and reattachment tests pass.

The reader now exposes that seam: a Needs review dialog offers Select replacement, the PDF shows a replacement-mode banner, and Save highlight updates the selected annotation instead of creating a duplicate. Reader-screen analysis is clean; the native full interaction remains device-gated.

Annotation edits now create immutable `annotation` revisions in the existing
outbox. Revision envelopes carry the complete annotation row, and receive
applies them only when the parent revision matches, returning duplicate or
conflict otherwise. This reuses the existing file-sync path without a second
transport or schema.

Evidence:

- `flutter test test/database/annotation_test.dart` — annotation persistence and offset ordering pass.
- `flutter test test/database/tylog_graph_schema_test.dart` — v2→v7 migration passes.
- `flutter analyze lib/database/tylog_database.dart test/database/annotation_test.dart` — clean.
- `flutter test test/pdf_annotation_reattach_test.dart` — moved, ambiguous, and missing anchor behavior is covered.
- `flutter test test/database/revision_publisher_test.dart test/database/revision_receive_test.dart test/database/revision_outbox_test.dart` — revision upload, decode, retry, duplicate, and conflict gates pass.
- `flutter test test/database/annotation_revision_sync_test.dart` — a PDF annotation publishes, decodes, applies on a second database, deduplicates, and rejects a divergent parent.
- `flutter analyze lib/database/revision_publisher.dart lib/database/tylog_database.dart lib/pdf/pdf_reader_store.dart lib/workspace_controller.dart` — clean.

Remaining work: run annotation revisions through a real Nextcloud account and run corpus-scale acceptance.

## Reader integration (2026-09-20)

The reader saves selected page ranges with exact quote, surrounding context, version identity and global UTF-16 offsets. Multi-page saves are transactional; repeated saves are idempotent. The Highlights drawer navigates back to selected text. Prior-version quotes are resolved only when unique; repeated/overlapping or missing matches display Needs review and do not silently move. Annotation reattachment stops at the second match. Native select/save/reopen/navigation passed on A24 using an isolated debug package and synthetic PDF.

Remaining: manual reassignment of ambiguous anchors, annotation synchronization, private corpus acceptance. Mac and A24 native selection smoke tests pass.

## Host acceptance rerun (2026-09-21)

The combined extraction, annotation, reassignment, source-version, and chunk
navigation suite passed 21 tests. The macOS native reader run passed both text
highlight and vector-only PDF tests. Annotation synchronization, private corpus
quality, and Android validation remain open.

## Acceptance rerun (2026-09-22)

The host annotation, reattachment, reader-store, and stable-offset suite passed
21 tests with clean analysis. Mac and A24 native selection/save/reopen flows are
verified; annotation synchronization and private-corpus quality remain open.
