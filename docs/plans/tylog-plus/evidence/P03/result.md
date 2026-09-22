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
- Verify an attachment's checksum survives the round trip and a cold app
  restart.

The Mac account check was read-only. The A24 started a production safe merge,
but it was stopped before completion at the user's request. No test edit,
attachment, or conflict resolution was performed.

Host regression after the interruption: `flutter test test/nextcloud_sync_test.dart`
passed 105 tests, including interrupted-bootstrap resume and unsupported-ZIP
fallback. This verifies the code paths, not the pending real-device result.
