# P2-B: extensions in the app (folder mounts end to end)

Uses P2-A (packages/tylog_core/lib/src/mounts.dart: Mount, parseMounts/encodeMounts, ReadOnlyVaultStorage, CompositeVaultStorage, mountsSettingsPath, mountPrefix).

1. WorkspaceController: on vault open read `_system/settings/mounts.json` (same settings-path/local-override pattern as kinds.json, reload on peer edit like reloadKindRegistry). Build storages per mount: folder -> ReadOnlyVaultStorage(LocalVaultStorage(path)) (desktop + Android local paths; skip unavailable with a status line, never fail the vault open). Github mounts: storage over the per-device cache dir `<appSupport>/mounts/<id>/` if present (P2-D fills it), else skipped.
2. Index/scan through CompositeVaultStorage(vault storage, mounts) so ext/<id>/ notes are searchable/linkable. Worker isolate path too (check how the worker gets storage). Cached index must not keep ext/ notes of a removed mount.
3. Writes: any note under `ext/` opens read-only (editor locked, small "extension · <name>" badge, no autosave). Writes to ext/ never reach the vault.
4. Nextcloud sync must ignore `ext/` (path filter where sync enumerates local files; add a test).
5. Settings > Extensions page (find where Settings > Modules lives: lib/widgets/settings/maintenance_page.dart / settings sheet): list mounts (name, source, note count, last refresh), Add folder (FilePicker getDirectoryPath on desktop; on Android show "GitHub only" for now), Remove (confirm), Refresh. GitHub add/sign-in UI comes in P2-D: leave a disabled "Add GitHub repo (soon)" row.
6. Tests: controller loads mounts and indexes an ext note; removing a mount drops its notes from the index; ext note is read-only (write attempt not performed); sync skips ext/; settings page add/remove writes mounts.json. Widget tests: real IO in tester.runAsync, pump outside, no pumpAndSettle.

Done when affected flutter tests + core dart tests + flutter analyze pass. Do not commit. 3-line report.
