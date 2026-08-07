# Changelog

Notable changes per release. Builds before 0.2.0 were all tagged `0.1.0+N`;
their history is in the commit log and the GitHub release notes.

## 0.3.0+91

Everything here came out of running 0.2.0 against a real phone and a real
3,351-note vault for the first time. Four defects, all of which you would have
hit; none were introduced by 0.2.0 — they had been there and nothing looked.

### Fixed

- **Resolving a sync conflict no longer blocks the app.** It used to allow
  exactly one resolve, then silently refuse every tap until you force-quit.
  Cause: resolving awaits a full index rescan, and the dashboard held its "busy"
  flag for that entire window — hours on a large vault. Resolution now runs on
  its own path; it contends with nothing. Anything still refused says so.
- **Geotagged photos stop conflicting forever.** Android hands the app a
  GPS-redacted copy of a photo whose bytes on disk are intact, so the sync saw a
  difference that did not exist. Resolving never helped, and "keep this device
  version" would have destroyed the coordinates on the server. Sync now compares
  the image data and ignores metadata segments.
- **Concurrent writes can no longer fork a file.** The two Flutter engines in
  this app each held their own storage lock, so both could write the same path
  and the Android provider would silently rename the loser to `name (1)` — found
  on a real device as `.tylog/vault (1).lock`, a lock nothing could release. The
  lock is now process-wide, and a rename that lands under the wrong name is
  rejected rather than accepted. Old forked locks are swept on vault open.
- A note whose bytes are unchanged is no longer re-indexed for search just
  because its timestamp moved. A sync that touched only mtimes used to
  re-tokenise the entire vault.

### Guarded

- **TyLog can no longer write a field the Typst package does not declare.** That
  is what cost 167 notes: `clocked:` was written as an argument the package had
  never declared, so every note carrying one stopped compiling, and the fallback
  parser read them back as fine. A test now derives the package's side from the
  package itself.
- `SafBridge.writeAtomic` — the one path that can lose a note — has tests for
  the first time, against a provider that reproduces Android's rename
  de-duplication. Reverting the fix reproduces the real-world artifact by name.
- The integration suite is globbed rather than listed by hand. Six of twelve
  tests were in no target at all; four had rotted, one of them failing inside
  `make verify` since a commit already on main.

### Known

- A cold index rebuild is ~25 notes/min (~2.2 hours for this vault). Tracked in
  #54 with the measurement needed to fix it properly.
- Credentials stored in note properties still reach the local search index by
  design. They no longer leave the device in the index donor.

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
