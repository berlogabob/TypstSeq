# P18 progress — PDF extraction contract

Status: RUNNING

Added a parser-neutral extraction boundary in `lib/pdf/pdf_extraction.dart`. A platform PDF reader supplies one nullable text value per page; TyLog records the source-version ID, PDF SHA-256, page number, combined character offsets, and an explicit status. Invalid bytes and image-only PDFs are accounted for instead of being silently indexed as empty text. SQLite schema v6 persists those records in `source_versions` with a source/time index.

Evidence:

- `flutter test test/pdf_extraction_test.dart` — 3 passed.
- `flutter analyze lib/pdf/pdf_extraction.dart test/pdf_extraction_test.dart` — clean.
- `flutter test test/database/pdf_source_version_test.dart test/database/tylog_graph_schema_test.dart` — 11 passed, including v2→v6 migration.
- `flutter analyze lib/database/tylog_database.dart lib/pdf/pdf_extraction.dart test/database/pdf_source_version_test.dart` — clean.

Remaining P18 work: connect a native PDF reader and add selection/navigation integration. The contract is deliberately independent of that reader so changing PDF backends does not move existing anchors.

## Native reader implementation (2026-09-20)

PDF attachment opening now routes to an in-app PDFium reader (`pdfrx` 2.4.8, compatible with the pinned Dart SDK). It reads vault bytes through the existing storage adapter, persists source identity/version/page text and creates derived chunks. The extraction uses the same structured text as PDF selection. Repeated opens preserve the original projection; changed text under the same extractor version is rejected. Image-only PDFs remain viewable and are labelled as lacking selectable text.

API verified against the installed package and [upstream selection documentation](https://github.com/espresso3389/pdfrx/blob/master/doc/Text-Selection.md). Native smoke covers a generated selectable-text PDF, not the private corpus or image-only/password-protected corpus. Full-document byte/text buffering and opening/extraction memory still require corpus-scale measurements.

A24 native reader fixture passes, including rendered text selection, durable save, reopening and highlight navigation. Repeating after a force-stop verifies retained records; see P24 for exact commands.

Mac native smoke also passes with PDFium (one test). Xcode 27 rejects the former macOS 10.15 deployment setting, so Runner and all CocoaPods targets now consistently require macOS 12.0. This is a compatibility-floor change, not a claim of testing on macOS 12 hardware.

### No-text native fixture

Added a valid vector-only PDF to the native integration test. On Mac, both tests pass: text highlight save/reopen/navigation and no-text viewer readiness/status/disabled save. The latter checks the no-extractable-text path; it does not establish scanned-image rendering quality, OCR, or large-corpus acceptance. Coordinator corrected the test's tooltip finder to inspect the actual IconButton and disposes the reader before database teardown.

## Mac smoke rerun (2026-09-21)

`flutter test --no-pub integration_test/pdf_reader_native_test.dart -d macos`
passed both native tests. The run covered durable text selection/reopen/navigation
and the vector-only no-selectable-text state. Corpus-scale memory, scanned-image
quality/OCR, password-protected PDFs, and Android acceptance remain open.

A24 native run also passed both tests (`flutter test --no-pub --no-uninstall integration_test/pdf_reader_native_test.dart -d 000251565001005`). Targeted analyzer clean. Tests use separate fixture databases in the debug package; production vaults are unchanged.
