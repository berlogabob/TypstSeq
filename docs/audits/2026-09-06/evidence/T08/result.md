# T08 verification

Date: 2026-09-08

Focused navigation and save-gate checks:

- `flutter test docs/audits/2026-09-06/reproduction_test.dart --plain-name 'AUDIT navigation retains edits when save fails' --reporter expanded` — 1 passed.
- `flutter test test/widget_test.dart --plain-name 'failed save keeps the current note during navigation' --reporter expanded` — 1 passed.
- `flutter test test/widget_test.dart --plain-name 'editor changes are autosaved' --reporter expanded` — 1 passed.
- `flutter test test/widget_test.dart --plain-name 'typing during autosave keeps the newer editor text dirty' --reporter expanded` — 1 passed.
- `flutter analyze lib/app_mobile.dart lib/app_mobile/vault_lifecycle.dart lib/app_mobile/markdown_import_flow.dart lib/app_mobile/vault_import_flow.dart test/widget_test.dart` — clean.
- `git diff --check` — clean.

The injected storage fixture keeps the current note, source, dirty state, and error on a failed write, then opens the requested note after writes recover. The audit probe confirms the original rejected-save navigation path remains safe.

SHA-256:

```text
f931cf5b9d951140cc5c120b9be4e73b2eac3e1b5946ca2dbf0320c5d00d96e1  lib/app_mobile.dart
be9531f8905ba51e7d9ab9fba6de945a8367e359adc110edcea569ef322e0e2d  lib/app_mobile/vault_lifecycle.dart
b29ec308e5628152f02d569a07d8046486a324dcafd70accbec76a83d9d0c752  lib/app_mobile/markdown_import_flow.dart
906ed304eddfe4ddc507152762a78e322c320e6747336812b0b9be13b222ec35  lib/app_mobile/vault_import_flow.dart
a5d11c42807d8149c508c441122a304b61f05219be77d435563fc7ce5c092a81  test/widget_test.dart
```
