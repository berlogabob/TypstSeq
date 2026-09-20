# P12e result — latency acceptance

Status: HOST COMPLETE / DEVICE PENDING

Host acceptance uses the plan gates from `docs/plans/tylog-plus/plan.md` and runs 30 database startups plus 100 durable saves of 50 KB notes:

```bash
flutter test test/database/p12_latency_acceptance_test.dart
```

Observed on the development Mac:

- Startup: p50 1 ms, p95 2 ms, max 370 ms across 30 samples.
- Durable open/save: p50 2 ms, p95 2 ms, max 32 ms across 100 samples.
- Gates: startup p95 <= 2,000 ms; save p95 <= 150 ms — PASS.

Full regression suite: `flutter test` — 686 passed, 2 skipped.

Android release/profile samples remain device-gated. The required follow-up is `flutter build apk --profile`, install over the release app, then capture 30 startup and 100 open/save samples on the A24.

### A24 database smoke (debug integration runner)

The same 30-startup/100-save workload also ran on the connected A24 through
`integration_test/p12_latency_native_test.dart`:

```text
startup_ms p50=2 p95=6 max=53; save_ms p50=6 p95=9 max=75; samples=30/100
```

Both thresholds passed. This is useful device evidence for the SQLite workload,
but it is not the release/profile gate: `flutter test` installs a temporary
debug test APK. P12e remains device-pending until the workload is exercised
inside a profile build with the app's normal startup path.

### A24 production cold-start timing

The installed production package (`org.tylog.tylog`, version `0.4.4`, profile
APK installed over the existing app) was force-stopped and launched 30 times
with Android activity timing. The vault was not cleared or modified.

```text
TotalTime_ms p50=417 p95=450 max=452 samples=30
```

This passes the 2,000 ms startup gate. The remaining device measurement is a
profile-run normal editor save/open workload; the 100-save result above is the
bounded database workload from the debug integration runner.

### A24 workspace save path

The real `WorkspaceController.save()` route was exercised on a temporary local
vault with the durable database attached. Across 100 50 KB editor saves:

```text
editor_save_ms p50=11 p95=15 max=179 samples=100
```

The p95 save gate (150 ms) passed; one outlier reached 179 ms. This is still a
debug integration runner, so the profile-build repetition remains required.

### A24 profile save-path acceptance

The same test ran through `flutter drive --profile` with the release-shaped
profile APK and the integration driver:

```text
editor_save_ms p50=2 p95=3 max=16 samples=100
```

The profile save gate passed. Combined with the 30 production-package cold
starts above (p95 450 ms), the startup and save timing gates are satisfied.
The scripted five-minute frame-budget gate and normal note-open timing still
need a dedicated profile workload.

### A24 profile frame attribution probe

`flutter drive --profile` ran the existing worker attribution workload (2,000
synthetic notes) for 12 seconds. Worst observed timer gaps were 26 ms while
the index was published, 18 ms while communities were built, 25 ms while the
search projection completed, and 16 ms during search. The test passed and
confirms the worker path is bounded, but this is not the required five-minute
real-editor workload or a frame-budget acceptance result.
