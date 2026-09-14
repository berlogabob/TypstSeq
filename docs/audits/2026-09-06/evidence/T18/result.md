# T18 result

Date: 2026-09-09

Focused worker/controller suites:

- `flutter test test/vault_worker_test.dart` — 6 passed, 0 failed.
- `flutter test test/workspace_controller_test.dart` — 43 passed, 0 failed.
- `flutter analyze lib/vault_worker.dart lib/workspace_controller.dart test/vault_worker_test.dart test/workspace_controller_test.dart` — no issues.

The worker now keeps a candidate search index private until maintenance completes, atomically swaps it, then emits `SearchReadyEvent(revision)`. Cancellation/failure leaves the prior searchable index and readiness revision intact. The controller publishes readiness after the worker event or after local `searchIndex.replaceWith`, and invalidates readiness on close/open. Tests query immediately on readiness and assert no readiness on cancellation.

Scoped diff SHA-256: `47023ccf6a5386616336bcc2fedb2b467a929c2034c991a2ecd35c544f8816ac` for the current diff of the four touched code/test files (includes accepted T09 and earlier changes). Plain counts: worker 55+/15-; controller 425+/176-; worker tests 94+/34-; controller tests 770+/187-.

Known limit: native integration worker validation remains outside this software unit suite; T19 owns Search UI refresh.
