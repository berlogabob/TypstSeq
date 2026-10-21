# Windows App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Windows build of TyLog (full workspace) attached to every GitHub release as `TyLog-windows.zip`, usable on the Studio PC without installing anything; sync uses TyLog's built-in Nextcloud sync (P2P later).

**Architecture:** Add the Flutter Windows host (`windows/`), a Windows plugin folder for `typst_flutter` that bundles a source-built `typst_flutter.dll` (same pattern as `packages/typst_flutter/linux/CMakeLists.txt`), Windows branches in `tool/setup_typst_native.sh` / `tool/assert_source_built.sh`, a `windows` job in `.github/workflows/release.yml`, and small Dart fixes (home folder, audio player, Mac-only UI).

**Tech Stack:** Flutter Windows desktop (MSVC via the `windows-latest` runner), Rust target `x86_64-pc-windows-msvc`, flutter_rust_bridge (existing), GitHub Actions.

**Spec (design approved in chat 2026-10-21):** full workspace on Windows; CI-built zip; built-in Nextcloud sync with the vault in app storage; audio recording works, playback via a Windows-capable player, waveforms hidden on Windows at first; Mac-only parts (LaunchAgents, screenshot scripts, Mac updater) hidden; home folder from `USERPROFILE`; checks = CI build + source-built gate, then a user smoke test on Studio (open, sync, search, edit).

## Global Constraints
- The engine DLL must be built from `packages/typst_flutter/rust` in CI (never downloaded); `assert_source_built.sh windows` gates the job.
- Release asset name: `dist/TyLog-windows.zip` (portable folder, `TyLog.exe` at the root).
- No change to Android/macOS/Linux/iOS behaviour or release assets.
- Code changes follow the existing patterns; Mac-only code stays behind `Platform.isMacOS`.

## Review Focus
1. Paths with spaces or non-ASCII under `C:\Users\<name>`: vault and app storage resolve via `path_provider`, never `HOME` (Task 3 test with `USERPROFILE` only).
2. A note with an audio attachment opens on Windows without a crash (no waveform plugin): Task 4 test with the waveform unavailable.
3. Sync paths: remote paths keep `/` while local paths use `\` (existing sync tests run on the Windows CI job in a later wave; noted, not in this plan).
4. First launch with no vault: the picker/app-storage flow works without SAF or macOS bookmarks (Studio smoke test).
5. Engine missing (DLL not bundled): the app reports the Typst engine problem instead of crashing (existing `typst-engine-unavailable` path; checked in the smoke test).

---

### Task 1: Windows host + engine plugin folder
**Files:** Create `windows/` (`flutter create --platforms=windows --org org.tylog .` then keep only `windows/`), `packages/typst_flutter/windows/CMakeLists.txt`.
- [ ] Generate the host; set the window title "TyLog" and product name in `windows/runner/main.cpp` / `Runner.rc`.
- [ ] Plugin CMake mirroring Linux: `set(_prebuilt_dll "${CMAKE_CURRENT_SOURCE_DIR}/../.typst_flutter_prebuilt/windows/typst_flutter.dll")`, `FATAL_ERROR` if missing with the setup hint, `set(typst_flutter_bundled_libraries "${_prebuilt_dll}" PARENT_SCOPE)`.
- [ ] Commit.

### Task 2: Native build + gate for Windows
**Files:** Modify `tool/setup_typst_native.sh` (Windows branch when `uname` reports MINGW/MSYS: `cargo build --release --target x86_64-pc-windows-msvc` into `.native-build-$toolchain-rustup-windows`, copy `typst_flutter.dll` to `.typst_flutter_prebuilt/windows/`, `mark_source_built windows`), `tool/assert_source_built.sh` (accept `windows`).
- [ ] Shellcheck-clean; on macOS the script's existing paths are unchanged (run it with `TYLOG_SKIP_ANDROID=1` locally: same output as before).
- [ ] Commit.

### Task 3: Home folder on Windows
**Files:** Modify the 6 `Platform.environment['HOME']` reads in `lib/` to a helper `String? userHome() => Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];` in `lib/vault_storage.dart`; Test `test/user_home_test.dart`.
- [ ] Failing test: with an injected environment map containing only `USERPROFILE`, `userHome(env)` returns it; with `HOME`, returns `HOME`.
- [ ] Implement (`String? userHome([Map<String, String>? env])`), replace the 6 reads. Run the affected tests + `flutter analyze`. Commit.

### Task 4: Audio on Windows
**Files:** Modify `pubspec.yaml` (add `just_audio_media_kit` + `media_kit_libs_windows_audio`, initialised in `main.dart` only on Windows), `lib/widgets/audio_inline_card.dart` / `audio_note_screen.dart` (no waveform on Windows: plain progress bar); Test `test/audio_widgets_test.dart`.
- [ ] Failing test: the audio card with `waveformAvailable: false` renders a progress bar and play button, no waveform.
- [ ] Implement; `waveformAvailable = !Platform.isWindows`. Run audio tests. Commit.

### Task 5: Release job
**Files:** Modify `.github/workflows/release.yml`: job `windows` (`runs-on: windows-latest`, `needs: test`, Flutter stable, Rust 1.92 with target `x86_64-pc-windows-msvc`, cache like Linux, `shell: bash` for `TYLOG_SKIP_ANDROID=1 ./tool/setup_typst_native.sh` and `./tool/assert_source_built.sh windows`, `flutter build windows --release`, zip `build/windows/x64/runner/Release` to `dist/TyLog-windows.zip`, upload artifact); add `windows` to the release job's `needs` and `dist/TyLog-windows.zip` to its files. Also add `windows` build (no zip) to `.github/workflows/ci.yml` only if it stays under 15 min, else release only.
- [ ] Push a test tag on a branch fork? No: run the release workflow via `workflow_dispatch` on the branch; confirm the zip contains `TyLog.exe`, `typst_flutter.dll`, `data/`.
- [ ] Commit; next release includes the zip.

### Task 6: Studio smoke test + docs
- [ ] User unzips on Studio, runs `TyLog.exe`, connects Nextcloud (Settings → Sync), waits for sync, searches, edits a note, checks Preview renders (engine present).
- [ ] README/USER_MANUAL: Windows as a platform, portable zip, built-in sync.
