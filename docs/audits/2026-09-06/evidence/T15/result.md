# T15 verification

Date: 2026-09-09

Implementation: `_newPage` now rejects duplicate requests, allocates the open-generation token at request entry, checks mounted/generation/vault ownership after title/template/save awaits, opens the created page before background refresh, and reports creation failures. Widget coverage includes gated refresh ordering/deduplication, save failure preservation, stale request after vault switch, and visible failure with retry.

Commands and results:

- `flutter test test/widget_test.dart --plain-name 'new page opens before a gated refresh and deduplicates taps' --reporter expanded` — 1 passed.
- `flutter test test/widget_test.dart --plain-name 'new page save failure preserves the original buffer' --reporter expanded` — 1 passed.
- `flutter test test/widget_test.dart --plain-name 'stale new page request cannot create after vault switch' --reporter expanded` — 1 passed.
- `flutter test test/widget_test.dart --plain-name 'new page creation error is visible and retryable' --reporter expanded` — 1 passed.
- `flutter test test/widget_test.dart --plain-name 'failed save keeps the current note during navigation' --reporter expanded` — 1 passed.
- `flutter analyze lib/app_mobile.dart test/widget_test.dart` — clean.
- `git diff --check` — clean.
- `graphify update .` — completed.

Final SHA-256:

- `lib/app_mobile.dart`: `512a5da134fe406c21ea47c7fc7fae3360b4255d6ca46be20c14789fcfcda517`
- `test/widget_test.dart`: `4b3d6ffda8f30d2ee9c3471c947b800ef607e31df4a62c53585fb240316a2b99`
