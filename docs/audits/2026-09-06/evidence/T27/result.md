# T27 integrated software regression gate

Date: 2026-09-09
Status: PASS

Commands and exact results:

- `flutter test docs/audits/2026-09-06/reproduction_test.dart --reporter expanded` — **5 passed, 0 skipped** (`reproduction.log`).
- `flutter test --reporter expanded` — **599 passed, 1 skipped** (`full_flutter_rerun.log`).
- `TYLOG_RUN_10K_BENCHMARK=1 flutter test test/pkms_10k_benchmark_test.dart --reporter expanded` — **1 passed** (`10k.log`).
- `flutter analyze lib test integration_test` — exit 0; no errors, with three pre-existing info lints in `lib/knowledge_screen.dart` (`analyze.log`).
- `cd packages/tylog_core && dart test` — **209 passed** (`core209.log`).
- `cd packages/typst_flutter/rust && cargo test --lib` — **19 passed, 0 failed** (`native19.log`).
- `flutter test integration_test/share_pdf_native_test.dart -d macos` — **5 passed** (`report5.log`).
- `git diff --check` — passed (`diff_check.log`).
- `graphify update .` — passed after all gates; generated graph output is included in the final fingerprint.

The first full-suite attempt had two interaction-test failures; after the test-only interaction fixes, the clean rerun above passed. The original logs remain preserved in `full_flutter.log` and `reproduction.log`; no product code was changed by this gate.

Base commit: `bacbf111a2af5cd7a4a2cc39379d610e75ba570a`.
Final working-tree diff SHA-256: `3a57adeceb577dfec59e6a9f565cb586c902bb21300cfcd2df38fc2cf6ff2142` (`fingerprint.log`).

## Addendum (2026-09-09)

The two failures were test interaction misses under the full-suite layout/timing, not product regressions. `full_flutter.log` records the Bold tap warning: its derived point was `(192.3, 528.0)` and did not hit-test the off-screen formatting control; the actual source therefore remained unformatted. The Settings failure likewise occurred before the modal transition had been settled. The editor implementation had no relevant diff.

Minimal test fix: settle the More sheet, ensure the Settings tile is visible before tapping, settle the editor dock, ensure Bold is visible before tapping, and settle the Vaults dismissal. No production code changed.

Verification:

- `flutter test test/widget_test.dart --plain-name 'settings menu shows real app data' --reporter expanded` — 1 passed.
- `flutter test test/widget_test.dart --plain-name 'journal rich editor shows one body and formats the selection' --reporter expanded` — 1 passed.
- `flutter test test/widget_test.dart --reporter expanded` — 52 passed, 0 failed.
- `git diff --check` — clean.
