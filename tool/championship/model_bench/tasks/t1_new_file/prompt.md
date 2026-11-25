Create ONE new file, lib/sync_stage_text.dart, in this Flutter project. Do not modify or create any other file.

It exports one pure top-level function:

    String syncStageText(String stage)

It turns a sync engine stage id into text a user can read.
- Input is either `<id>` or `<id> · <detail>` (space, middle dot U+00B7, space). The detail, when present, is kept unchanged at the end, including the ` · ` separator.
- An id that starts with `sync-file ` followed by a counter (example `sync-file 3/9`) becomes `Syncing 3/9`.
- Known ids:
  load-local-state, scan-local-shortcut, scan-local -> Checking local notes
  probe-root -> Checking server
  prepare-remote-folder -> Connecting to server
  list-remote -> Reading server list
  push-local -> Uploading changes
  detect-renames -> Matching renamed notes
  download-archive -> Downloading vault
  validate-archive -> Checking download
  extract-archive -> Unpacking download
  verify-remote-writes -> Verifying uploads
  save-local-state -> Finishing sync
- Any other input is returned unchanged.

Examples: `push-local` -> `Uploading changes`; `sync-file 3/9 · notes/a.typ` -> `Syncing 3/9 · notes/a.typ`; `detect-renames · a.typ → b.typ` -> `Matching renamed notes · a.typ → b.typ`; `Uploading…` -> `Uploading…`.

No dependencies beyond the Dart core library. `flutter analyze --no-pub lib/sync_stage_text.dart` must report no issues.
