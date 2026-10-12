# Audit finding recheck — 2026-10-12

Reviewed the two graph-linked documents on branch `findings/audit`.

| Finding | Current verdict and evidence |
|---|---|
| Background timeout lock strand | Fixed the remaining startup/acquisition drift. Native deadline: `android/app/src/main/kotlin/org/tylog/tylog/VaultSyncWorker.kt:49`; Dart handoff: `lib/vault_service.dart:39`; lock acquisition: `lib/vault_service.dart:69`; absolute expiry: `lib/vault_lock.dart:56`. Duration callers and legacy records remain supported. |
| T00 double-open / closed response port | Already resolved. Successful onboarding returns at `lib/app_mobile/vault_lifecycle.dart:29`; worker disposal drains at `lib/vault_worker.dart:627`; native replies are guarded at `android/app/src/main/kotlin/org/tylog/tylog/SafBridge.kt:401`. Added current-code verification to the diagnosis. |
| Unlocked cold rebuild | Still open; corrected the prior closure rationale. Maintenance can restore/delete stranded notes (`packages/tylog_core/lib/src/scanner.dart:941`), prune peer donors (`packages/tylog_core/lib/src/index_donor.dart:155`), and sweep backups (`packages/tylog_core/lib/src/maintenance.dart:592`). No data-loss reproduction claimed. Coordination changes deferred. |

Added deadline regressions and updated the entrypoint contract check. Initial
new tests failed to compile against the old API; after the fix, they pass.
No existing assertion was removed or relaxed.

Validation:

- `flutter analyze`: **No issues found**. Initially failed on nine errors and
  one warning in standalone benchmark challenge fixtures. Excluded only
  `tool/model_bench/tasks/**/hidden/**` from app analysis; benchmark checks still
  copy these tests into `test/` and run them unchanged.
- `flutter test --no-pub test/vault_lock_test.dart test/background_completion_test.dart test/release_config_test.dart`: **16 passed**, including a final rerun.
- `flutter test --no-pub test/vault_worker_test.dart test/workspace_controller_test.dart test/maintenance_parity_test.dart test/rich_editor_test.dart test/widget_test.dart test/graph_test.dart test/archive_release_test.dart`: **389 passed**.
- All four production Android Kotlin files compiled with cached Kotlin 2.2.20,
  JVM target 17, Android 36, Flutter and WorkManager dependencies: **exit 0**.
  Gradle compilation could not start: configured Java home was missing, then
  Gradle failed to load `libnative-platform.dylib`. No packaged APK verification.
- `git diff --check`: passed.
- `graphify query` initially lacked `graph.json`; used the checked-in report.
  `graphify update .` rebuilt the AST graph at zero API cost; queries now work.
  The report changed with the generated graph. Extraction warned about
  `linux/runner/my_application.h` and
  `packages/typst_flutter/android/build.gradle`, and 23 files without symbols.
  Historical semantic document links were not re-extracted.

Commit: **blocked by sandbox permissions**, despite green checks. `git add`
failed creating the linked worktree's index lock at
`../TypstSeq/.git/worktrees/TypstSeq-audit/index.lock` (`Operation not permitted`).
No commit or staging occurred; changes remain on `findings/audit`. No permission
workaround or sibling source edit was attempted.

Did not do: large refactors, whole-repo audit, device installs, device/SAF
integration or Android onboarding replay, deployment, push, or edits to the
sibling worktree's source. Cold-rebuild coordination remains a concurrency risk;
this review does not provide new hardware acceptance evidence.
