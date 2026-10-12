# T00 device crash diagnosis

Selecting the empty `TyLogAuditVault` folder entered `_openVault` twice. The
initial `_pickVault(closeCurrent: false)` already selected and opened the new
entry; `_open()` then continued to its common startup path and opened the same
entry again. The second open killed the first worker while its SAF requests
were still pending. The native `SafBridge` later posted a `MethodChannel.Result`
to that worker's closed Dart response port, causing Flutter's fatal
`platform_message_response_dart_port.cc:53` `did_send` check.

The startup path now completes onboarding and returns after the successful
pick, so the common open path runs only once. Failure behavior is unchanged.

## Current-code verification — 2026-10-12

**Resolved.** `lib/app_mobile/vault_lifecycle.dart:22` picks and opens the vault;
the successful branch completes onboarding and returns at
`lib/app_mobile/vault_lifecycle.dart:28`, before the common startup open at
`lib/app_mobile/vault_lifecycle.dart:82`. The picker itself opens the selected
entry at `lib/app_mobile/vault_lifecycle.dart:144`.

The shutdown defense is also present: `lib/vault_worker.dart:621` sends a
cooperative shutdown and `lib/vault_worker.dart:627` waits for isolate exit;
`lib/vault_worker.dart:211` exits only after serving and draining work. Native
engine teardown suppresses queued replies through
`android/app/src/main/kotlin/org/tylog/tylog/SafBridge.kt:401` and disposes the
bridge before destroying the engine at
`android/app/src/main/kotlin/org/tylog/tylog/VaultSyncWorker.kt:67`.

The active-worker disposal/replacement regression in
`test/vault_worker_test.dart:216` passes locally. The SAF counterpart remains
`integration_test/vault_worker_saf_shutdown_test.dart:18`; it was not run here
because this review excludes device installs. This is a code verification,
not a new hardware crash reproduction or Android onboarding replay.
