# P03 — Mac–phone Nextcloud sync

Status: BOTH ACCOUNTS CONNECTED / FIRST DEVICE SYNC INTERRUPTED

The Mac TyLog documents contain a saved legacy Nextcloud configuration. A
read-only authenticated WebDAV `PROPFIND` against its configured collection
returned HTTP 207. This confirms the saved Mac endpoint and credential can
reach a DAV collection. No remote file contents were downloaded or changed,
and no account values or secrets are recorded here.

The A24 production app was reinstalled in place as a profile build, selected
the surviving vault through SAF, and connected to the same Nextcloud account.
Its safe-merge sync passed folder discovery and reached `download-archive`.
The user needed to disconnect the phone, so the app was force-stopped before
that initial transfer finished. No completed device sync or bidirectional
behavior has been observed. The app displayed two pre-existing conflict cards;
neither was resolved during this check.

## Remaining acceptance

- Reconnect A24, resume the safe merge, and record its completed result and
  transfer counts. A profile install must use `adb install -r`; avoid test
  commands that uninstall the production package and erase its private state.
- Verify a small test edit moves Mac → A24 and A24 → Mac through the existing
  sync controls.
- Verify a same-note concurrent edit is preserved as a conflict on both sides.
- Inspect the two already displayed A24 records for the same note by record ID,
  timestamp, and snapshot hashes before resolving either; the verified P01
  backup predates them and contains no conflict records.
- Verify an attachment's checksum survives the round trip and a cold app
  restart.

The Mac account check was read-only. The A24 started a production safe merge,
but it was stopped before completion at the user's request. No test edit,
attachment, or conflict resolution was performed.

Host regression after the interruption: `flutter test test/nextcloud_sync_test.dart`
passed 105 tests, including interrupted-bootstrap resume and unsupported-ZIP
fallback. This verifies the code paths, not the pending real-device result.

The archive download previously reported only its stage, leaving the A24
screen unchanged while bytes streamed. A host change now reports transfer
percentage about twice per second (downloaded MiB if the server omits the
total size), without changing transfer or fallback decisions. A delayed ZIP
fixture verifies a progress update before completion; all 106 sync tests pass.
The updated profile build and real A24 display still need verification after
the phone is reconnected.

Host follow-up found a reproducible same-path race: two concurrent conflict
writers could both remove the previous record before writing distinct new
records. The shared writer is now serialized within the app isolate. A focused
race test failed with two records before the fix and passes with one after it;
the sync and dashboard suites pass 117 tests. This prevents that race from
creating new duplicate cards, but does not establish whether it caused the
two existing A24 records. Those remain untouched pending device inspection.

The next A24 profile APK was built from commit `8b1c9cd` without the phone:
`build/app/outputs/flutter-apk/app-profile.apk` (package `org.tylog.tylog`,
version 0.4.4+99, SHA256
`6fb242fbabeae2bf058ff91efc5f4ddaa310f9d9685fc2a4588218999431686e`). Install
it with `adb install -r` after reconnecting; this build has not yet been run
on the device.
