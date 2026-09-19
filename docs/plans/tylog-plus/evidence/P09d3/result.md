# P09d3 — assets and cooperative cancellation

Status: PASS

The import dialog now exposes a cancel action. The runner checks the signal
between pending items, so the current item can finish atomically while later
items remain pending and resume on the next run. Asset references are persisted
in imported node attributes and reconstructed from committed job nodes before a
resumed asset pass. The existing namespaced destinations and destination-exists
check keep the copy idempotent.

Validation:

```text
flutter analyze lib/app_mobile.dart lib/app_mobile/vault_import_flow.dart \
  lib/import/legacy_import_runner.dart test/vault_import_policy_test.dart
No issues found

flutter test test/vault_import_policy_test.dart \
  test/import/legacy_import_plan_test.dart test/import/legacy_import_runner_test.dart
20 tests passed
```
