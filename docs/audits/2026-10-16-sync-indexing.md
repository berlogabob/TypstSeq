# Sync and indexing: startup walk safety

The requested six-hour shortcut is **not enabled**. Measurements supplied for
the Huawei P30 were 5–6 s for the no-change local walk and 9–10 s for the
worker's fresh scan. No new device timings were collected in this sandbox.

## Why a restart cannot trust an empty pending-write set

`lib/vault.dart` keeps `_pendingSyncWrites` in memory. `restoreWriteMarkers`
changes those in-memory sets; it does not restore a durable sync journal.
`saveNote`, note creation, and `deleteNote` add pending paths after changing
the data. A new background-service Vault and a new worker Vault start empty.

`packages/tylog_core/lib/src/storage.dart` does persist an index-dirty marker
before `LocalVaultStorage.writeBytes` writes a `.typ` file outside `.tylog/`,
`_index/`, and `_system/`. This protects indexing, not sync: maintenance removes
committed markers after scanning, even if the write has never synced. Deletes
do not create markers. All other extensions are outside this mechanism.

These are the concrete gaps relevant to the proposed shortcut:

| Vault paths | Writers and missing tracking |
| --- | --- |
| Note `.typ` paths, including `notes/`, `daily/`, and module `projects/<id>/` paths | `lib/vault.dart` records pending sync only in memory; `VaultMaintenance.buildIndex` consumes their durable index markers independently of sync. |
| Deleted note/file paths, including module uninstall paths | `LocalVaultStorage.delete` has no durable marker; `Vault.deleteNote` records pending sync after deletion, only in memory. |
| `assets/**`, including audio, `<audioPath>.peaks`, and `assets/articles/<articleId>/*` | `lib/app_mobile/audio_flow.dart`, `lib/platform_file_actions.dart`, `lib/audio/audio_note_doc.dart`, and `lib/markdown_article_import.dart` write non-`.typ` files without a durable sync marker. |
| `_system/jobs/transcripts/<sha1>.json` and `_system/jobs/translations/<sha1>.json` | `lib/audio/transcript_jobs.dart` writes directly through storage; `_system/` and JSON are excluded from index markers. |
| `_system/revisions/<envelopeId>.json` | `lib/database/revision_publisher.dart` materializes via `opened.storage.writeBytes` in `WorkspaceController.syncNow`. The database has its own revision upload queue, but this does not populate `Vault.hasPendingSyncWrites` or index markers. |
| `projects/<moduleId>/**`, `assets/modules/<moduleId>/**`, `_system/modules/<moduleId>.json` | `packages/tylog_core/lib/src/module_pack.dart` installs, updates, and removes files through storage. Only eligible `.typ` writes get index markers; assets, records, and deletions do not. |
| Imported assets and arbitrary imported file paths | `lib/app_mobile/vault_import_flow.dart` and `lib/database/portable_import.dart` write directly through storage. Non-`.typ` content has no index marker or durable sync-pending entry. |
| Migration destination paths | `copyVaultStorage` in `lib/vault_registry.dart` deliberately uses raw atomic writes for exact `LocalVaultStorage` destinations, bypassing index markers for every copied file. |
| Sync download/replacement paths | `lib/nextcloud_sync/webdav_client.dart` and `path_sync.dart` write through storage; downloads deliberately do not enter the pending-sync set. Non-`.typ` writes and deletes lack index markers, and interrupted sync must still reconcile its receipts. |

`VaultEntry.storageKind == 'app-local'` explicitly identifies app-private
vaults. `VaultEntry.storage` maps both app-local and local-path entries to
`LocalVaultStorage`, so runtime storage type cannot prove sole-writer ownership.
Neither `Vault.withStorage` nor `NextcloudSync` currently receives that entry
kind. A future shortcut needs an explicit flag plus a durable journal covering
all syncable writes and deletions, acknowledged by sync rather than indexing.
No path heuristic, six-hour stamp, or new shortcut flag was added. Folder/SAF
behavior is unchanged.

## Worker timing interpretation

`index-published` now carries the scan stage map and parsed-note count.
`scan-done` carries the completed worker map, including search and communities.
`list-stat` covers the listing and its stat metadata; `note-hash` measures cache
verification reads; `note-parse` covers note reads, parsing, and inspection,
excluding separately measured support-file work. `scan` contains the remaining
cache/fingerprint comparison and reuse work. Existing donor, encode, write,
finalize, and search stages remain separate.

The confirmed cold-start defect was comparison against `_lastBuiltIndex` only,
ignoring the disk index loaded for this scan. The regression test observed one
unnecessary index write before the fix and zero afterward. This establishes
avoidable work, not the proportion of the P30's 9–10 s spent in each stage;
the next device log provides that breakdown.
