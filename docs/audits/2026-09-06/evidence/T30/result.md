# T30 result

Date: 2026-09-09
Status: PASS (software and focused Android profile regression)

`T00/diagnosis.md` identifies the exact startup race: an empty-registry pick
already calls `_openVault`, then `_open()` continued into its common startup
`_openVault` call. The second open disposed the first worker while SAF
MethodChannel requests were pending; later `SafBridge.Result.success` targeted
the dead worker response port and triggered Flutter's `platform_message_response_dart_port` fatal.

The worker-side fix keeps a busy isolate alive after client disposal: shutdown
sets cancellation, the worker waits for `_rebuild`'s `finally`, and only then
exits. The client still settles the active stream immediately and remains
idempotent. A permanently wedged native call may leave a detached worker; a
timeout kill is intentionally unsafe while its platform reply can still be in flight.

Evidence:

- `flutter test test/vault_worker_test.dart`: **6 passed**.
- T30 Android SAF shutdown replacement profile: **2 passed in 8s**; log:
  `saf-shutdown-profile.txt`.
- New regression file hash:
  `integration_test/vault_worker_saf_shutdown_test.dart`
  SHA-256 `2fe2bf1b0d4432361a61cc89b8c524db5059b67649711f1d32319fe09d501d83`.
- Current lifecycle diff returns after successful empty-vault onboarding, so
  the duplicate open path is not re-entered.
- Normal profile cold-launch reproduction recorded **TotalTime 452ms**, the
  process remained alive for **15s**, and no fatal/did_send errors occurred.
  The historical pre-fix crash remains in Android exit-info at **10:55:36,
  PID 4393**.
