# P18 progress — PDF extraction contract

Status: HOST ACCEPTED / DEVICE VERIFIED / CORPUS OPEN

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

Android profile rerun on 2026-09-22 passed both native cases: text highlight
save/reopen/navigation and vector-only PDF rendering. The process-death seed,
force-stop, and reopen sequence also passed after keeping the seed process
alive between runs.

Mac native smoke also passes with PDFium (one test). Xcode 27 rejects the former macOS 10.15 deployment setting, so Runner and all CocoaPods targets now consistently require macOS 12.0. This is a compatibility-floor change, not a claim of testing on macOS 12 hardware.

### No-text native fixture

Added a valid vector-only PDF to the native integration test. On Mac, both tests pass: text highlight save/reopen/navigation and no-text viewer readiness/status/disabled save. The latter checks the no-extractable-text path; it does not establish scanned-image rendering quality, OCR, or large-corpus acceptance. Coordinator corrected the test's tooltip finder to inspect the actual IconButton and disposes the reader before database teardown.

## Mac smoke rerun (2026-09-21)

`flutter test --no-pub integration_test/pdf_reader_native_test.dart -d macos`
passed both native tests. The run covered durable text selection/reopen/navigation
and the vector-only no-selectable-text state. Corpus-scale memory, scanned-image
quality/OCR, password-protected PDFs, and Android acceptance remain open.

## Large extraction contract (2026-09-21)

The host extraction suite now exercises a deterministic 1,000-page corpus and
verifies every page retains a strictly increasing character range with the
expected page length. Four extraction tests pass. This closes large-corpus
offset correctness; native memory limits and private corpus quality remain
open.

The same host acceptance rerun also passed the PDF storage and chunk persistence
checks, confirming source-version identity and stable ranges alongside the
1,000-page extraction contract.

A24 native run also passed both tests (`flutter test --no-pub --no-uninstall integration_test/pdf_reader_native_test.dart -d 000251565001005`). Targeted analyzer clean. Tests use separate fixture databases in the debug package; production vaults are unchanged.

## Acceptance rerun (2026-09-22)

The combined extraction, source-version, reader-store, annotation, reattach,
and chunk-navigation suite passed **21 tests** with clean analysis. Native
reader smoke is verified on Mac and A24; private corpus, scanned-image/OCR,
password-protected PDF, and memory-scale checks remain open.
