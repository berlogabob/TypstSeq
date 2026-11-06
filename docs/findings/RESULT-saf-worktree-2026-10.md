# Foreground-service seam attempt — 2026-10-12

Outcome: implementation and test changes reverted; no commit. The required native validation could not run, so the task did not meet the all-green condition. Only this findings document remains changed on `findings/saf`.

## What changed, then was reverted

Read AGENTS.md, CONTEXT.md Engineering rules, the prior assessment in this file, and the native source/callers/tests before editing. There was no `graphify-out/graph.json` at the start, so orientation used source and the prior assessment.

Moved only the three foreground-service dispatches into an internal `handleMethodCall(context, call, result): Boolean` on the existing SyncForegroundService companion object. SafBridge returned when that handler recognized a call and otherwise continued its existing dispatch. The same argument extraction, synchronous execution, success(null), Throwable catch, `foreground_sync_error`, message fallback and null error details were retained. No channel or Dart public API changed.

Extended SafBridgeWriteTest with native delegation coverage using a ContextWrapper that intercepts service calls without starting a service. It checked start/update/stop replies, start detail forwarding including null, main-thread start/stop execution, service errors with and without messages, invalid update detail, unrecognized-handler silence, unknown bridge methods and known-method fallthrough. This test was written but could not be compiled or executed; no native pass is claimed.

Restored SafBridge.kt, SyncForegroundService.kt, SafBridgeWriteTest.kt and GRAPH_REPORT.md byte-for-byte from HEAD, and removed graph artifacts created during this attempt. Git restore could not create the linked worktree index lock outside the writable worktree; restoration instead wrote HEAD contents directly to the four files inside this worktree. Final tracked status contains only this document.

## Verification output

- `flutter analyze`: exit 0, **No issues found!** before editing and with the attempted seam. After restoration: exit 0, **No issues found!** (4.0 seconds).
- Root `flutter test --no-pub`: exit 0, **1,379 passed, 8 skipped**, final output `All tests passed!` (1 minute 11 seconds). This ran the entire root host suite, including storage/controller tests and all six CONTEXT.md local gates. The existing skips were not changed.
- Core package `flutter test --no-pub`: exit 1; test loading failed because `package:test/test.dart` was unresolved. Attempts to use the package's Dart runner/dependency setup were blocked by SDK engine-stamp, pub-cache active-root and telemetry writes outside writable roots. The core package contract suite did not pass; no dependency files were changed to bypass it.
- Android `:app:compileDebugAndroidTestKotlin --offline`: blocked. This worktree has no gradlew script. A retry using the cached Gradle 9.1.0 distribution first encountered an invalid inherited JAVA_HOME; selecting the installed Java 17 runtime then failed to initialize native services (`libnative-platform.dylib` for macOS aarch64). Compilation and instrumentation execution remain unverified.
- `graphify update .`: exit 0; AST-only update produced 9,336 nodes and 13,426 edges. It warned of partial parsing in linux/runner/my_application.h and packages/typst_flutter/android/build.gradle, and 23 files with no extracted symbols. Generated graph changes were reverted with the implementation.
- `git diff --check`: clean after restoration.

The native foreground integration smoke test and instrumented suite require Android execution/install, which is prohibited for this task. Host channel mocks and a clean analyzer cannot establish Kotlin dispatch behavior. No seam-related host golden tests were found; device embedding golden/profile tests were not run. These validation gaps are why the code/test changes were reverted instead of committed.

## Not done

No retained production or test implementation, test weakening, new dependencies, manifest/configuration/API changes, device execution or installs, deployment, push, or commit. No sibling worktree source was read or modified; file writes stayed inside this worktree (temporary test output stayed in /tmp). No SDK/cache permission changes were made. Storage locks/caches, sync leases, workers, picker handling and Dart callers remain unchanged. The requested seam still needs native validation in an environment that can run it.
