# P25 — production migration and release acceptance

Status: HOST ACCEPTED / EXTERNAL BLOCKED

Host prerequisites remain incomplete: P24 has been reopened because injected exceptions did not prove actual process-death recovery. Execution is blocked because P03 has no configured Nextcloud account on the Mac and phone, and the native release/real-vault acceptance checks are still outstanding. The A24 was detected via adb on 2026-09-20.

When access is restored, run in order:

1. `flutter build apk --profile` and install with `adb install -r build/app/outputs/flutter-apk/app-profile.apk`.
2. Capture `dumpsys gfxinfo org.tylog.tylog` after cold open, sync, search, and index resume.
3. Verify the real-vault hash before and after sync on Mac and A24.
4. Run a two-device edit, conflict, resume, and restart cycle; record sync latency, notification-loop count, and missing-data count.
5. Attach the redacted logs and mark P03/P25 DONE only when all integrity checks pass.

No production acceptance claim is made until those measurements exist.

Fresh device check (2026-09-20): production registry readable; two vault entries; active selection valid; zero configured Nextcloud entries. Only aggregate booleans/counts were printed.

Normal Android entry point rebuilt with `flutter build apk --profile --target-platform android-arm64` and installed using `adb install -r`. Install succeeded without uninstall or data clearing. A private before/after registry SHA-256 comparison matched. The main activity opened, indexing completed, and the production Library displayed existing notes. The synthetic test package was stopped. This is an installation/launch check, not the full release, sync, or integrity acceptance gate.

Mac: native reader smoke passes. Normal Apple Silicon release built (74.8 MB) and launched with `open -n build/macos/Build/Products/Release/TyLog.app`. At that checkpoint the standard universal build failed in Flutter's architecture validation despite `lipo` reporting both slices. A local `XCODE_XCCONFIG_FILE` containing `ARCHS = arm64` and `ONLY_ACTIVE_ARCH = YES` produced a working host release. App artifact is under `build/` and is not committed. No installed `/Applications` bundle was overwritten.

### Reproducible Apple Silicon build

`tool/build_macos_arm64.sh` now supplies the temporary architecture override and cleans it on exit; `FLUTTER_BIN=/Users/berloga/development/flutter/bin/flutter tool/build_macos_arm64.sh` passed (74.8 MB). README documents the command and macOS 12 minimum. No SDK files were modified.

Root-cause check: on the untouched Flutter SDK universal framework, `/usr/bin/lipo <framework-binary> -verify_arch arm64 x86_64` exits 1 with `-verify_arch requires exactly one input file`; checking either architecture separately exits 0, and `-info` reports both. This local Xcode tool behavior explained Flutter's misleading missing-architectures error at the time; the later Xcode 27 rerun below closes the packaging check. The ARM64 script remains available for Apple Silicon-only builds.

## ARM64 release rerun (2026-09-21)

`FLUTTER_BIN=/Users/berloga/development/flutter/bin/flutter
tool/build_macos_arm64.sh` completed successfully. The release bundle measured
**72 MB** and the app executable SHA-256 was
`8f904b03ece287de1550c920f01b77c8718d0cdb9214cdeb767cf5bbb276a2f7`. This
validates repeatable Apple Silicon packaging only; universal packaging,
signing, real-vault integrity, and Nextcloud acceptance remain open.

## Universal release rerun (2026-09-21)

The standard `flutter build macos --release` now succeeds under Xcode 27 and
produces a 153.5 MB `TyLog.app`. The main executable is a verified universal
Mach-O containing both `x86_64` and `arm64` slices.

```text
Executable SHA-256: 9f678622bcccb281aa550b32e1121a553c60e34e960316d101b1bd3f20f5a7b9
```

P25c closes universal packaging. Real Nextcloud configuration, migration, and
device release acceptance remain the P25 blockers.

## Universal launch smoke (2026-09-21)

`open -n build/macos/Build/Products/Release/TyLog.app` launched the universal
bundle successfully; the expected `TyLog` process was observed after three
seconds and then stopped cleanly. This closes the host launch smoke only.

## Android native report packaging (2026-09-22)

The A24 profile report/export suite initially failed because the prebuilt
`libtypst_flutter.so` depended on `libc++_shared.so`, which was absent from the
APK. The plugin build now stages the ABI-matched NDK library into the arm64
package. The rebuilt profile APK contains `lib/arm64-v8a/libc++_shared.so`, and
all six Android report/export tests pass.

## Host release gate rerun (2026-09-22)

The current macOS release executable is a verified universal Mach-O with
`x86_64` and `arm64` slices. The current Android profile artifact has SHA-256
`a86ab072dd89ac08f615113ac6c1afb453e26523e1e89dd99440da085fdc4e61`.
Host packaging and launch evidence are complete; real Nextcloud credentials,
real-vault integrity, and two-device release rehearsal remain external gates.

## Integrated host artifacts (2026-09-22)

After the P21 cited-navigation host seam, `flutter build apk --profile` and
`flutter build macos --release` both passed. The Android profile APK is still
`org.tylog.tylog` 0.4.4+99; its SHA-256 is
`fd9ca41574dfd51bf9732eb0e11879064e04a22894d4e0ba64eb69caf88367d0`.
The macOS release executable contains arm64 and x86_64 slices, has SHA-256
`7e3392e9eed23f82ef2cc5db0fd0b736249414926583959c7dc8fad18f16d714`,
and `codesign --verify --deep --strict` passed. These integrated artifacts are
ready for device and release rehearsal; neither was used for that acceptance
in this checkpoint.

## A24 profile reinstall after integration-test cleanup (2026-09-23)

The normal profile APK was rebuilt and installed. Package `org.tylog.tylog`
reports version `0.4.4+99`; the installed APK SHA-256 is
`73ce0a774c8e41d32c4b6379b21a78c5f113be932ba5777be363191e72535e7c`.
The existing `/sdcard/TyLog` folder was reselected through SAF and the app
opened it. This is a recovery/launch smoke only; cloud credentials and the
production sync/release rehearsal remain open. See P03 for the app-private
state reset caused by the profile integration runner.

## Production release acceptance (2026-10-03)

**Android (A24 `000251565001005`).** The production package `org.tylog.tylog` was found
uninstalled; its last sync in the vault's own trace is 2026-09-27 21:14 UTC, so the removal
predates this session. App-private state (database, vault grant, account) was gone; the
shared-storage vault was intact. Recovery doubled as the release gate:

- Release APK 0.4.4+99, native libraries source-built (`tool/assert_source_built.sh android macos`
  ok), SHA-256 `9be0bb287e372ba4cd0d7a0b5f18597751843610cd29c06ac6026ed7b87605b3`.
- Installed with `adb install -r`, launched, `/sdcard/TyLog` reselected through SAF, account
  re-entered, **Safe merge** initial sync: uploaded 3, downloaded 1, unchanged 12,235,
  conflicts 3, deleted 0.
- Vault integrity: 12,239 files hashed before install; after the merge 0 missing, 0 changed,
  4 new (1 downloaded article, today's daily note, 2 app metadata files).
- The 3 conflicts were WebP article images, same size and dimensions, 7–54 bytes different
  (re-encodes). The Mac copy equals the server copy for all three; resolved as "Keep
  Nextcloud's version". Phone, server and Mac hashes now match.
- Two-way: the phone's new daily note is on the server and on the Mac (same hash); the server's
  new article is on the phone (same hash).
- Cold restart (force-stop, relaunch): startup sync uploaded 0, downloaded 0, conflicts 0,
  12,242 files.

**macOS.** Universal release (x86_64 + arm64), `codesign --verify --deep --strict` ok,
executable SHA-256 `ca0d6b274d8732dd77e5230b1fe65ed4bddf8fc8d0f13068a2d6a364bdb78aa4`;
launched for 15 s with no fatal/crash log lines and quit cleanly. Open warning: the linker
reports `libtypst_flutter.a` objects built for macOS 13.4 against the app's 12.0 deployment
target; macOS 12 is untested.

Mac vault sync runs through the Nextcloud desktop client, which was found not running (only
its Finder extension) and was restarted; it then pulled the phone's note.
