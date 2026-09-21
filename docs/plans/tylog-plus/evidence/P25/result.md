# P25 — production migration and release acceptance

Status: BLOCKED (external prerequisites)

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

Mac: native reader smoke passes. Normal Apple Silicon release built (74.8 MB) and launched with `open -n build/macos/Build/Products/Release/TyLog.app`. The standard universal build failed in Flutter's architecture validation despite `lipo` reporting both slices. A local `XCODE_XCCONFIG_FILE` containing `ARCHS = arm64` and `ONLY_ACTIVE_ARCH = YES` produced a working host release; universal release packaging remains unverified. App artifact is under `build/` and is not committed. No installed `/Applications` bundle was overwritten.

### Reproducible Apple Silicon build

`tool/build_macos_arm64.sh` now supplies the temporary architecture override and cleans it on exit; `FLUTTER_BIN=/Users/berloga/development/flutter/bin/flutter tool/build_macos_arm64.sh` passed (74.8 MB). README documents the command and macOS 12 minimum. No SDK files were modified.

Root-cause check: on the untouched Flutter SDK universal framework, `/usr/bin/lipo <framework-binary> -verify_arch arm64 x86_64` exits 1 with `-verify_arch requires exactly one input file`; checking either architecture separately exits 0, and `-info` reports both. This local Xcode tool behavior explains Flutter's misleading missing-architectures error. Universal packaging remains open; the script deliberately produces only ARM64.

## ARM64 release rerun (2026-09-21)

`FLUTTER_BIN=/Users/berloga/development/flutter/bin/flutter
tool/build_macos_arm64.sh` completed successfully. The release bundle measured
**72 MB** and the app executable SHA-256 was
`8f904b03ece287de1550c920f01b77c8718d0cdb9214cdeb767cf5bbb276a2f7`. This
validates repeatable Apple Silicon packaging only; universal packaging,
signing, real-vault integrity, and Nextcloud acceptance remain open.
