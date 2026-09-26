# U0 result — existing controls and UI audit

Status: HOST PARTIAL / NATIVE CONTROL SWEEP OPEN

## make verify (2026-09-26, macOS 26.6.2, M4 Pro)

- `flutter analyze`: no issues. Core + typst suites: pass. App unit/widget
  suite: 762 passed, 3 skipped.
- macOS integration glob: every test passed or skipped by design across two
  runs, after these fixes (not yet in one uninterrupted run):
  - stale macOS typst_flutter dylib (FRB content-hash mismatch) — rebuilt from
    source via `make setup-native`;
  - `ort` has Android prebuilts for arm64 only — embeddings gated to
    `aarch64` Android, all four ABIs now build and are stamped source-built;
  - P12 frame diagnostics opt-in (`P12_FRAME_GATE`), private-corpus tests
    skip without their root, VFS benchmark opt-in (`VFS_BENCH`).
- `flutter build macos --release`: pass. `flutter build apk --release`: pass
  from a clean tree (arm64 signed APK installed on A24, cold start 509 ms);
  inside make verify it failed once because integration runs left the
  test-flavour `GeneratedPluginRegistrant.java`.
- The uninterrupted rerun stalled at `graph_share_native_test` because the Mac
  display was locked (app cannot be foregrounded). Rerun with the screen awake.

## Controls

[control-inventory.md](control-inventory.md): 130 controls. The two
long-press-only actions (heading levels, saved-search delete) now have tap
routes with tests that fail pre-fix. Contrast/48 dp regression tests are in
the passing unit suite. Mac and A24 per-control results remain pending.
