# P25 — production migration and release acceptance

Status: BLOCKED (external prerequisites)

Host prerequisites are complete: P24 passed, the profile build configuration is documented, and the acceptance sequence is deterministic. Execution is blocked because P03 has no configured Nextcloud account on the Mac and phone, and the A24 is not currently available for the profile APK and real-vault checks.

When access is restored, run in order:

1. `flutter build apk --profile` and install with `adb install -r build/app/outputs/flutter-apk/app-profile.apk`.
2. Capture `dumpsys gfxinfo org.tylog.tylog` after cold open, sync, search, and index resume.
3. Verify the real-vault hash before and after sync on Mac and A24.
4. Run a two-device edit, conflict, resume, and restart cycle; record sync latency, notification-loop count, and missing-data count.
5. Attach the redacted logs and mark P03/P25 DONE only when all integrity checks pass.

No production acceptance claim is made until those measurements exist.
