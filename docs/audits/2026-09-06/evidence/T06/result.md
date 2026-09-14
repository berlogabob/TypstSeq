# T06 result

Status: DONE (software); device validation pending T28

Startup now uses the existing Android foreground-service lifecycle. The worker
service starts before sync work, repeated resume callbacks cannot acquire a
second sync owner, and the existing `finally` path stops the service on both
success and failure. A small constructor seam enables deterministic mock-channel
coverage on desktop tests without changing production behavior.

Verification:

- `flutter test test/workspace_controller_test.dart --plain-name 'startup foreground service has one owner and stops on success/failure'`: 1 passed.
- `flutter test test/workspace_controller_test.dart`: 40 passed (progress ended at `+39`).
- `flutter analyze lib/workspace_controller.dart test/workspace_controller_test.dart`: no issues.
- `git diff --check`: passed.

The focused test records exactly one start during a gated startup sync, rejects
a repeated resume while that sync is active, observes one stop after success,
then observes one start and one stop for a failed startup sync. The first run
timed out because the Flutter test binding intercepted loopback HTTP; the test
now uses the existing `HttpOverrides.global = null` pattern used by other
WebDAV tests.

SHA-256 (working-tree files):

- `lib/workspace_controller.dart` df438c2db8707b139637257224b17add33e062969aadc689d8acebb288050f5b
- `test/workspace_controller_test.dart` 59fda9344ebfcebeb544843f460401651e81508bdcc45893718c1b4a1a20919d

Scoped diff SHA-256 for the two files above: `57d6ae646733ca1e9cac3371382f3b7443bc05fa8ddfb657ccc5b0750a2093e4`.

Limitations: actual Android service/background-resume behavior remains pending
device validation under T28.
