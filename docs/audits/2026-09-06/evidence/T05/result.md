# T05 result

Status: DONE

Cold startup now starts the worker before the initial sync can scan on the
root isolate. If that sync transfers content, its scan is the single index
publication; the cold-start fallback rebuild runs only when no current index
was published. Unchanged remote state and a pre-transfer sync failure still
fall through to one usable index. Warm startup keeps its concurrent rebuild.

Verification:

- `flutter test test/workspace_controller_test.dart --plain-name 'cold startup publishes one index for transfer, unchanged, or failure'`: 1 passed; all three cases publish once.
- `flutter test docs/audits/2026-09-06/reproduction_test.dart --plain-name 'AUDIT cold startup publishes index only once'`: 1 passed; audit counter reported 1.
- `flutter test test/workspace_controller_test.dart`: 39 passed.
- `flutter analyze lib/workspace_controller.dart test/workspace_controller_test.dart`: no issues.
- `git diff --check`: passed.

SHA-256 (working-tree files):

- `lib/workspace_controller.dart` c6a13e7164387a923881f4907e08affe486b5f254234c03926c63a63da377af0
- `test/workspace_controller_test.dart` e33f745d95593bf4b6e00d979023e90160596ce3b398e3704024e5a478c23715

Scoped diff SHA-256 for the two files above: `8b9a5341aabcbf61d13355ad7165865593c1eed77a83ecf84c906b7c9d9d350f`.

Limitations: device startup/background validation remains outside T05.
