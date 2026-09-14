# T10 verification

Date: 2026-09-09

The latest note selection now owns a generation token allocated at each navigation request. `_openNote` checks the token, current vault identity, and `mounted` after save and storage reads; disposal invalidates pending opens. Today/day/page/link callers pass their request token through delayed path creation.

Checks:

- `flutter test test/widget_test.dart --plain-name 'latest note selection wins across a delayed vault read' --reporter expanded` — 1 passed.
- `flutter test test/widget_test.dart --plain-name 'a delayed note read is ignored after disposal' --reporter expanded` — 1 passed.
- `flutter test test/widget_test.dart --plain-name 'a delayed Today path cannot overwrite a later note selection' --reporter expanded` — 1 passed.
- `flutter test test/widget_test.dart --plain-name 'failed save keeps the current note during navigation' --reporter expanded` — 1 passed.
- `flutter test docs/audits/2026-09-06/reproduction_test.dart --plain-name 'AUDIT navigation retains edits when save fails' --reporter expanded` — 1 passed.
- `flutter analyze lib/app_mobile.dart test/widget_test.dart` — clean.
- `git diff --check` — clean.

SHA-256:

```text
1636774865ec9a03cf99c68c8373a5509dad8bdb25447e64ab1998518ba316e9  lib/app_mobile.dart
2e6ebb04bd930516b9af25315a2f0ccdde7621b634c333432adf0b3b3c5a863f  test/widget_test.dart
```
