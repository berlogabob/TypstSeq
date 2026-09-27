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

The A24 profile APK was rebuilt after the later host integration without the phone:
`build/app/outputs/flutter-apk/app-profile.apk` (package `org.tylog.tylog`,
version 0.4.4+99, SHA256
`fd9ca41574dfd51bf9732eb0e11879064e04a22894d4e0ba64eb69caf88367d0`). Install
it with `adb install -r` after reconnecting; this build has not yet been run
on the device.

## A24 recovery after profile test attempt (2026-09-23)

The P05 profile integration runner removed `org.tylog.tylog` on exit. The
verified P01 external vault backup remained available, and `/sdcard/TyLog`
was still present. The normal profile APK was reinstalled, and its Android
folder picker was used to reselect that existing TyLog folder. The app opened
the vault and surfaced the two existing sync-conflict notifications; neither
was resolved and no sync/import was started.

The app-private sandbox was recreated. The P01 settings archive contains the
vault registry and marker, but not the local SQLite database or a saved
Nextcloud configuration. Any database-only annotations or unsynced state may
need recovery from another source. P03 remains open; configure the cloud
account again in the app before resuming sync acceptance. No credentials are
recorded here.

## A24 reconnected and initial sync completed (2026-09-27)

- The production app had been removed by an earlier profile run; the release
  build was reinstalled in place and the user reselected the vault. Nextcloud
  was configured on the A24 from the ignored `.secrets/` file (HTTPS endpoint;
  entered with the Maestro CLI so the password never appeared in tool output).
  Gboard autocorrect had corrupted the server URL ("next cloud. sounding
  doubts. pt"); fixed in f14721e (no autocorrect on URL/login/folder fields).
- Before the safe merge, a fresh backup of the phone vault was pulled:
  11,847 files, full SHA-256 manifest, stored outside Git.
- Safe merge ("unique files both ways, same-path differences become
  conflicts, nothing deleted") finished; latest sync reports 12,238 files on
  Nextcloud, all unchanged.
- 23 conflicts (2 pre-existing from 2026-09-02, 21 from the merge) were each
  classified by `tool/p03_conflict_report.py` (drafted by local ornith, fixed
  and self-checked) against both the pre-merge and 2026-09-15 backups:
  - 19 article assets: 9 are HTML error pages saved as images on both sides,
    6 real images where the server copy is the newer re-download, 3 webp where
    the phone file already equalled the server → keep Nextcloud.
  - One daily note: the phone copy was 54 lines of editor-benchmark junk from
    a 2026-09-21 test run against the production app, with no real line the
    server lacked → keep Nextcloud.
  - One guide note: the server copy is byte-identical to the 2026-09-15
    verified backup; the phone copy differed only by unescaped hyphens plus one
    junk line → keep Nextcloud.
  - The pre-existing pair (same daily note): the server had three lines
    written on another device, the phone one line the server lacked. Both
    records were resolved to Nextcloud and the union (every line from both
    sides, verified) was then written to the server; the phone downloaded it
    without a new conflict.
- No real content was lost; every overwritten phone copy remains in the
  pre-merge backup.

Remaining for P03: Mac↔A24 small edits in both directions, a concurrent
same-note edit preserved as a reviewable conflict, and an attachment hash
round trip with cold restart.

## Two-way, concurrent and attachment checks (2026-09-27)

Setup: the Mac vault `~/Nextcloud/TyLogVault` syncs through the Nextcloud
desktop client; the A24 uses TyLog's own sync. Test files: a dedicated test
note and two random 64×64 PNG attachments (no user content).

| Check | Result |
|---|---|
| Mac → A24 small edit | arrived, hash match, 46 s |
| A24 → Mac small edit | arrived, hash match, 91 s |
| Attachment Mac → A24 | hash match after 41 s; unchanged after A24 cold restart (220 ms), no conflict, no re-download |
| Attachment A24 → Mac | hash match after 90 s |
| Concurrent same-note edit (first try) | **phone edit silently overwritten** — a poll reused the cached local listing (scan-local 53 ms), judged the file unchanged and downloaded over it |
| Concurrent same-note edit (after 1b891d8) | phone keeps its edit and stores a conflict whose `.local`/`.remote` snapshots equal the two edits byte for byte; later runs skip it as `unresolved-conflict` |

Fix 1b891d8 (drafted by local ornith-1.5:9b, reviewed): the download branch
re-hashes the real file before overwriting and stores a conflict when it
differs; host test fails without it; full suite 877 passed.

Latency is far above the acceptance table's ≤10 s p95 sync target (a separate
Sync gate, measured later). Open question for P03 closure: the Mac side has no
TyLog sync engine, so a concurrent edit is reviewable on the A24 only; the Mac
keeps its own version and nothing is lost.
