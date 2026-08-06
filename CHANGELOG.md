# Changelog

Notable changes per release. Builds before 0.2.0 were all tagged `0.1.0+N`;
their history is in the commit log and the GitHub release notes.

## 0.2.0+90

First release with a version that carries a signal. It contains a fix that
needs action from you, and a cross-device format change.

### Action required

**Rotate any credentials stored in note properties.** Before this release the
index donor TyLog publishes to `_system/index/<deviceId>.json` carried every
note property verbatim, and `_system/` is inside the sync allowlist — so those
values were uploaded to the server and handed to every other device. On the
author's vault, two donor files carried `pswrd` five times each.

The donor no longer publishes properties TyLog did not write, but the files
already uploaded are still there. See issue #49 for the purge checklist.

Separately: the search index tokenises whole note bodies, so note text —
including those values — sat in `_index/`. TyLog never synced `_index/`, but a
vault inside `~/Nextcloud` is uploaded by the desktop client regardless. New
vaults now get a `.sync-exclude.lst` that keeps `_index/` and `.tylog/` local.

### Compatibility

- **Index donor schema 2 → 3.** A device on 0.2.0 ignores donors written by an
  older build, and vice versa. Nothing breaks — each device re-parses the notes
  it cannot take from a peer — but the cross-device cache only helps again once
  every device is upgraded. A first scan on a not-yet-upgraded pair is slower.

### Fixed — data safety

- "Migrate entity types" and "Clean up imported notes" were one-tap tiles that
  rewrote every note with no confirmation and no undo. Both now say how many
  notes will change and copy each one to `.tylog/undo/<timestamp>/` first.
- "Relink vault" now says that it replaces the Related section, rather than
  asking only whether to "rescan and refresh".
- Relinking no longer truncates a note at the auto-related marker, so anything
  written below a Related section survives.
- The macOS updater verifies the download against a published SHA-256 before
  applying it, and no longer deletes the running app before the replacement is
  in place — a failed swap used to leave no app at all.

### Fixed — notes that would not compile

- A page title containing `"`, `\`, `#` or `[` produced Typst that could not
  compile, and the note silently never regained real metadata.
- Time tracking (`clocked`) moved into `properties`, so notes carrying it still
  open on an older Typst package.
- Several task writers produced malformed calls when a task was written on one
  line; a quote or backtick in prose could hide every task after it.
- Chip labels containing escaped or nested brackets no longer truncate.

### Added

- Logseq `:LOGBOOK:`/`CLOCK:` time tracking is captured on import, and tasks
  read and write `clocked` sessions.
- A fresh device now gets tasks from a peer's index donor instead of an empty
  Tasks view.
- `writer_compiles_test.dart` compiles the output of each writer, rather than
  parsing it — the fallback parser accepts malformed Typst, which is how a
  167-note breakage once passed CI.
