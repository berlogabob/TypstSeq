Task: T02
Outcome: DONE
Model / attempts / elapsed: requested Terra/high; backend not independently exposed / 1 / ~15 minutes
Changed files: `lib/vault_worker.dart`, `test/vault_worker_test.dart`
Reproduction: `flutter test docs/audits/2026-09-06/reproduction_test.dart --plain-name 'AUDIT disposing worker terminates its active command'` timed out after 1 second because disposal closed the relay without a terminal event. See `reproduction-before.log`.
Validation: `flutter test test/vault_worker_test.dart` (6 passed); audit probe (1 passed); `flutter analyze lib/vault_worker.dart test/vault_worker_test.dart` (0 issues); `git diff --check` passed. Details: `validation.log`.
Acceptance: Disposal queues one cancelled terminal event even before the caller listens; duplicate dispose shares completion; post-dispose `run` throws and `search` returns empty immediately; an error-plus-dispose race cannot emit a second terminal event; replacement worker rebuilds; single-flight remains green.
Decision for downstream tasks: Unexpected worker exit poisons future worker calls; none otherwise.
Limitations: Controller lifecycle acceptance belongs to T09 per coordinator direction.

Diff fingerprint: `175f2a20d5ebaee6de501a9bff869175a21c9eb10128a4656902f0a0ee0ee69f`.

Coordinator acceptance 2026-09-08: reviewed disposal, terminal relay and single-flight paths. Independent Luna/low rerun passed all worker tests in combined focused run (`independent-focused.log`); unrelated T03 controller regression failed and remains open.
