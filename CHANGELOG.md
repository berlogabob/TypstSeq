# Changelog

Notable changes per release. Builds before 0.2.0 were all tagged `0.1.0+N`;
their history is in the commit log and the GitHub release notes.

## 0.4.1+96

Three fixes for a class of problem 0.4.0's own schema bump exposed on the
device an hour after release: index donors are shared files, and the code that
prunes them and the code that syncs them disagreed about what a deleted one
means.

### Fixed

- **A device no longer deletes another device's index donor.** The P30 dropped
  its unusable local replica seconds after the desktop had replaced it with a
  readable one, and the next sync read that absence as a user deletion and
  removed the desktop's donor from Nextcloud — the one file the whole fleet
  needed to skip the version-10 recompile. Sync now refetches an absent cache
  file instead of propagating it, and pruning someone else's donor requires it
  to have sat untouched for seven days.
- **A shared cache file is never a conflict.** A prune racing its own
  republication, or two devices simply holding different derived indexes,
  produced a conflict over a file nothing user-authored ever touches.
- **A conflict already recorded on a donor clears itself**, rather than
  outliving the fix that stops new ones being made — the sync loop skips a
  conflicted path before reaching anything that knows a donor is regenerable.

## 0.4.0+95

Sync stops freezing over conflicts nobody made, an index bump stops costing the
whole fleet a recompile, and the numbers behind both are measured rather than
guessed.

**This release forces one re-index** (index version 10) — the last one that
will. Run `tylog index` on the desktop first and the phones pick the result up
from its donor instead of recompiling.

### Added

- **Sync records where its time goes.** Every terminal trace event now carries
  a per-stage profile. First real numbers, P30 / 11,610 files / a pass that
  transferred nothing: `scan-local` 9.3 s, `list-remote` 5.6 s,
  `prepare-remote-folder` 1.2 s, and the entire per-file loop over all 11,610
  files **96 ms**. That retired two planned optimisations before they were
  written — both targeted half a percent of the cost.

### Fixed

- **One conflict no longer suspends the whole vault's sync.** Five conflicts,
  none of them files the user had edited, left the A24 695 articles behind for
  four hours. The sync loop already skipped conflicted paths individually; only
  the poll gate was vault-wide.
- **A conflict whose remote was deleted can be resolved.** It compared the
  record against a missing remote and threw on every attempt, while the only
  code that could repair the record ran solely when the remote still existed.
  The escape was deleting the record by hand over adb.
- **Append-only conflicts resolve themselves.** When one copy is the other plus
  an appended block, the longer side wins — lossless by definition, counted as
  repaired and named in the trace. A genuine two-sided edit still stops for
  review.
- **The resolve dialog no longer defaults to destroying the newer side.** It
  preselected keep-local unconditionally; on one real daily note that would
  have silently deleted an appended line. A default is offered only where it is
  provably lossless, and each side is described against the other rather than
  in raw byte counts.
- **A not-yet-synced image no longer costs a note its metadata.** A note whose
  `#image()` target had not arrived could not compile, so it fell back to the
  source parser — 432 of 4,225 notes (10%) on the mid-sync A24 against 18 on
  the fully-synced P30.
- **A stray keystroke no longer strands a daily note.** Removing the character
  failed forever, leaving a 2-byte file nothing could clean up and the editor
  permanently dirty — which also disabled idle maintenance and the midnight
  rollover.
- **Temp files from interrupted writes are swept**, after an hour untouched so
  an in-flight write is never disturbed.
- **The vault is no longer walked twice per sync**, and the root folder is no
  longer re-created on every run to be told it already exists. The no-change
  pass fell from 21–25 s to 5.9–9.8 s.

### Changed

- **A derive-only index bump costs a re-derivation, not a recompile.** Versions
  6, 7, 8 and 9 were every bump this index has ever had and none changed the
  Typst query, yet each made every device recompile the whole vault — 14.2
  minutes for 5,086 notes on the P30. The query version and the index version
  now move independently, and entries carry the queried half they need to be
  re-derived from. Donors (schema 4) survive such a bump instead of being
  deleted.

## 0.3.0+94

Indexing gets cheaper, the journal shows today again, and the desktop starts
pulling its weight. No re-index is forced by this release.

### Fixed

- **Journal opens on today.** Five daily notes have no `date:` in their header,
  and the feed sorted on `date ?? path` — so their key became
  `daily/2026/08/…`, and `d` sorts above `2`. Every undated note outranked every
  dated one, which is why the journal sat on 08-17 with today six entries down
  in a list that loads one day at a time. The same five were missing from the
  calendar entirely. The day is now derived from the path, on both the scanner
  and the read paths, so it needs no re-index.
- **The day arrows respond immediately.** Each `<` / `>` press did five storage
  round-trips (save, mkdir, exists, write, read) queued behind any running sync,
  with the date frozen until they finished — so people pressed again — and every
  day merely passed through left an empty daily note behind. The label now moves
  on the tap, presses coalesce, and only the day you land on is created.

### Changed

- **Rebuilds stop repeating work.** A rebuild re-read and re-decoded the whole
  index (1.65 MB gz → 8.82 MB plain, ~13k objects) even though the worker
  already held it, then re-encoded and re-hashed all of it just to decide
  whether to write. Both are now skipped when nothing changed. The search index
  also stops re-tokenising every task and attachment document on rebuilds where
  no note changed.
- **WebP images are no longer read during indexing.** The placeholder trick
  shipped in +93 covered png/jpg/gif/svg but missed webp — 598 files, 38.6 MB of
  the 50.4 MB still pulled through storage on any changed note. The inspect
  payload is now 11.3 MB across 35 files. Measured on a real device: a
  donor-seeded rebuild of 6,214 notes fell from 211 s to **172 s**, with
  metadata quality unchanged (20 fallbacks).
- **The desktop can publish an index for the phones.** `tylog index` now writes
  a donor under a stable per-machine id, and prunes donors this build can never
  read — `_system/index/` syncs, so those were downloaded by every device
  forever (5.7 MB of dead weight on the real vault). A scan also reports what it
  reused from other devices, so the feature can no longer fail silently.

## 0.3.0+93

Performance floor, linking that just works, and kinds-as-tags. One forced full
re-index on first open (index schema v9) — with the indexing fix below it takes
minutes, not hours. No note file is rewritten by anything in this release.

### Fixed

- **Cold indexing is orders of magnitude faster on the native path.** Every
  note inspection re-serialised the entire vault's support files — 854 MB of
  `assets/` — across the FFI boundary. Three stacked fixes: the file set now
  crosses once per scan instead of once per note (measured on the real vault:
  15.6 → 3,600–5,100 notes/min per-note inspect cost, A/B in
  `integration_test/vfs_base_files_bench_test.dart`; issue #54's ~25 notes/min
  ≈ 2.2 h cold rebuild becomes minutes); the handoff is streamed in 48 MB
  chunks (one message carrying the whole vault was a single contiguous
  allocation that aborted the app on the P30); and images travel as valid
  1×1 same-format placeholders — a metadata query only needs `#image()` to
  resolve, and its records are layout-independent, so the vault's real
  image bytes are never read or shipped at all. The placeholders are
  compile-verified against the typst CLI in tests (broken bytes would
  silently degrade notes to the fallback parser). Measured on the Huawei P30
  (release build, real vault): the full forced re-index of 5,086 notes took
  14.2 min with the app usable throughout and native heap ≤360 MB — the
  pre-fix build OOM-crashed twice on the same scan — and metadata quality
  ended at 5,068/5,086 typst-query (18 fallback, 0.35%).
- **Warm rebuilds skip the search-index round trip.** The worker re-decoded
  (8.4 MB gz → 31 MB JSON), rebuilt 107k posting sets twice, and re-encoded the
  search index even when nothing changed. It now reuses the in-memory index and
  skips the save when the document set is unchanged.
- **`_index/index.json` is gzipped** (~4:1 on the real vault) and identical
  bytes are not rewritten. Older plain-JSON files still open; the CLI reads and
  writes the same format.
- **Typing a mention no longer has a corruption window.** The popup replaced
  `[[query` with the reference in two separate editor writes; a round-trip
  failure between them could mangle the paragraph. It is now one atomic edit
  with one validation and a clean rollback.
- **`@` completes non-ASCII names.** `@Илья` never matched (ASCII-only word
  class); the trigger now accepts any Unicode letter or digit. New `@`
  insertions also emit the same reference shape as `[[` instead of a second
  `[@Title]` spelling.
- **A fully-typed `[[Page]]` is a real link.** It used to be dead text —
  displayed as a link in excerpts but invisible to backlinks, the graph, and
  triage. Literal wikilinks are now indexed as outgoing links (the note's text
  keeps its brackets; nothing rewrites it).

### Added

- **Enter creates the page.** Selecting the "New page" row in the `[[` popup
  creates the note immediately and links it — no dangling chip, no confirm
  dialog. Bare `[[` or `@` now shows recently-opened notes instead of "No
  matches", and matching is substring-based ("assistant" finds
  "Home Assistant").
- **Kinds are tags now.** `kind: article/person/place/…` also surfaces as a
  tag (`#article`, `#person`), so the existing tag filters slice by kind
  everywhere — search, saved searches, reports. Index-only: headers and the
  article-pipeline contract are untouched; the plain `note` kind is not
  aliased; kind tags are excluded from the concept map and community
  detection so `#article` doesn't swallow the graph.
- **One Notes list instead of three tabs.** Notes, Projects and Entities
  merged into a single list with kind filter chips; Articles keep their
  reading shelf, Journal/Calendar unchanged.
- **The magic-menu note/entity choosers have a filter field** — they were
  unsearchable full-vault lists.

## 0.3.0+92

A design audit of the whole interface, and the fixes for what it found. Nothing
here touches your vault, your notes, or how anything is stored.

### Fixed

- **Tapping a task in Library ▸ Tasks no longer completes it.** The row toggled
  the task done, while the identical-looking row on Today opened its note — so
  whichever screen you learned first taught you the wrong thing about the other,
  and the cost of the mistake was a task disappearing under your finger. Both
  lists now open the note; the checkbox is the only thing that changes status.
- **The warning icon in Problems is legible.** It was drawn in a yellow that
  scored 1.56:1 against the app background, below even the 3:1 floor icons are
  held to — effectively invisible in daylight.
- **Graph edges are legible in light mode.** Link, citation and tag edges sat
  between 2.3:1 and 3.3:1 against the background. All four kinds now clear 3:1.
  Dark mode was already fine and is unchanged.
- **The status and relevance chips on an article row can be hit.** They drew
  about 26px tall, immediately next to each other — well under the 48px minimum
  and the easiest mis-tap in the app. They look exactly the same; the touch
  area is now full size.

### Added

- **Highlight colours without a long-press.** The four colours were reachable
  only by long-pressing the toolbar button — a gesture nothing announces and
  nobody finds on a phone. Magic ▸ Highlight and `/highlight` now offer the
  palette directly, including "Remove highlight".
- **The Voronoi map is usable with a screen reader.** Every visible cell is now
  a labelled, activatable target that does what tapping it does. Before, the
  entire view was invisible to assistive tech.
- **Deleting an article no longer requires a long-press** — it is in the row's
  ⋮ menu, styled as the destructive action it is. Long-press still works.
- **The timeline graph's "Read" edges have a legend entry** and can be toggled
  like the other three kinds. They were drawn, but unexplained and unfilterable.

### Changed

- **Today is capture-first.** The agenda and reading shelf could take 60% of the
  screen, pushing the editor — the reason Today opens on Today — into whatever
  was left. They are capped at 45% now, and when nothing is due and nothing is
  part-read they take no space at all, instead of spending a row to say so.
- The rating sheet's "Shit" button is now **"Discard article…"**, which is what
  it always did: it deletes the article. Stars fill in as you press them.
- One icon per concept. A note, a person, a place, a project now look the same
  in every list, picker and chip.
- Dialog text fields are styled alike — the metadata editor's were invisible
  while the identical new-entity dialog's were outlined.
- "More" separates everyday actions from maintenance, so "Rebuild index" and
  "Relink vault" no longer sit flush against "New page".

### Guarded

- **Colour contrast is now a test.** Every colour the UI hardcodes is checked
  against the WCAG 3:1 floor on both themes, reading the real values the app
  draws with rather than a copy of them. The three failures above cannot come
  back silently.
- **The design tokens are now a test.** The brand seed, the corner-radius scale,
  the palette rule and the one-icon-per-kind rule are enforced by a source scan.
  The seed had drifted into three files and seven unrelated corner radii were in
  use; that is the class of rot this stops.

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
