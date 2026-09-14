# T20 verification

Date: 2026-09-09

Asset refreshes are revision-gated. Loads stage bytes locally and publish only when the source revision, current vault, and mounted state still match. Refreshes run after note loads and edits, including inserted attachments; a changed reference clears the prior compiler map.

Checks:

- `flutter test test/widget_test.dart --plain-name 'inserted images reach the preview compiler file map' --reporter expanded` — 1 passed, including removal/change clearing.
- `flutter test test/widget_test.dart --plain-name 'old note assets cannot repopulate a newer note preview' --reporter expanded` — 1 passed.
- `flutter test test/widget_test.dart --plain-name 'view chooser opens read preview source and editor modes' --reporter expanded` — 1 passed.
- `flutter analyze lib/app_mobile.dart test/widget_test.dart` — clean.
- `git diff --check` — clean.
- `graphify update .` — completed.

SHA-256:

```text
7674d0ba4352bfec83818007ac677d766aaa1b83088a7351e595e9a2ce5240b2  lib/app_mobile.dart
6b6a159708407e4c47014b0ee1bedd50acecc45bc9bd825057af56ed0b3219db  test/widget_test.dart
```
