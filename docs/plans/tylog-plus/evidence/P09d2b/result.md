# P09d2b — durable UI import adapter

Status: PASS

The mobile vault import now creates or resumes a deterministic Drift job from
the source manifest and drives conversion through `LegacyImportRunner`. The
existing vault paths, rendered Typst, journal append behavior, duplicate hash
decisions, progress text, asset pass, and report counters remain in the flow.
Imported nodes and revisions use IDs derived from the job, source path, and
source hash. `NodeData.content` stores the exact final rendered note, including
the full journal content after an append. Reporting metadata stays in a local
source-path map used by the materializer.

The adapter seams have focused tests for deterministic job/node/revision IDs,
normal note materialization, existing journal append content, and completed-job
rerun accounting. Runner/materializer failures now close the modal and produce
a private-safe resumable report. Note counters, metadata, and link sets are
reconstructed from committed nodes, so resumed jobs include every completed
batch; asset copying remains after successful completion for P09d3.

Validation:

```text
flutter analyze lib/app_mobile.dart lib/app_mobile/vault_import_flow.dart \
  lib/import/legacy_import_runner.dart lib/import/legacy_import_plan.dart
No issues found

flutter test test/vault_import_policy_test.dart \
  test/import/legacy_import_plan_test.dart test/import/legacy_import_runner_test.dart
18 tests passed
```
