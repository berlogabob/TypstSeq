# Changelog

Notable changes per release. Builds before 0.2.0 were all tagged `0.1.0+N`;
their history is in the commit log and the GitHub release notes.

## 0.12.1+134

### Fixed

- **No false sync conflict while typing.** A second sync run could start
  before the first had saved its state and then report a conflict against
  this device's own upload, leaving the page unsynced until resolved by hand.
  Runs for one vault no longer overlap, and a server copy that matches this
  device's last upload or an earlier local version is never a conflict.
- **Task popups show their rows.** The command list, date suggestions and
  priority list were blank or cut off with the keyboard open; the list now
  sizes to its content and opens above the line when there is no room below.
- The caret stays at the end of the task text after picking a date.
- No blank gap between task lines that have chips, and chips of a
  scrolled-out line no longer paint over the page header.

## 0.12.0+133

### Added

- **A task line shows its state.** Status glyph (☐ todo, ◐ doing, ☑ done,
  ☒ cancelled) and, beside the line, priority, due or scheduled date, repeat
  and time spent. Tap one to change it in the same popup the commands use.
- **One task row everywhere.** Today, Tasks, Journal, Calendar, Search and
  saved queries show the same row: tap to complete, long-press for all four
  statuses, the same chips. Journal, Calendar and Search rows were read-only.
- **Quick add** on Today and Tasks: type a line, it becomes a task on today's
  journal page.

### Changed

- The play/stop button is gone from task rows: Doing runs the timer. Stop on
  the running pill returns the task to Todo.
- The "All" filter shows everything, including cancelled and older done
  tasks.

### Fixed

- A task changed from a list or by sync now updates in the open editor.
- The Typst-help Task chip inserts a unique id each time.

## 0.11.9+132

### Added

- **Tasks are typed, not filled in.** `TODO `, `[] ` or `[ ] ` at the start of
  a line, or `/todo`, turns the line into a task with no dialog. Enter starts
  the next task; Enter on an empty task returns to plain text.
- **Commands on a task line:** `/todo` `/doing` `/done` `/cancel`, priority
  `/a` `/b` `/c` `/urgent`, `/due` and `/scheduled` (`/deadline`), `/repeat`.
- **Typed dates.** `/due` opens a date field in the popup: type `fri`,
  `tomorrow`, `завтра`, `15.10` or `+3d` and pick from the list; the calendar
  icon opens the grid picker.
- **Ctrl/Cmd+Enter** cycles todo → doing → done. Long-press the checkbox for
  all four statuses.
- **Doing runs the timer.** Setting a task to Doing starts its clock; leaving
  Doing stops it. Starting another task returns the previous one to Todo.

### Fixed

- Ticking a repeating task in the editor records one occurrence instead of
  ending the repeat.
- Removing a task's checkbox with Backspace is one undo step that restores
  the task with all its fields.

## 0.11.8+131

### Fixed

- **A journal page is never saved without its header.** Using the timestamp
  shortcut on a day that had no page yet could save only the timestamp line,
  leaving a broken page that later cleanup could treat as empty and delete.
  The page template is now always loaded and saved first.
- **A broken journal page is repaired, not replaced.** An existing page with
  no header gets its header back with the text kept, after an undo copy is
  taken in `.tylog/undo`.
- Writes made right after a sync now go through the normal save queue.

### Internal

- Groundwork for the tasks redesign, not yet visible: one writer for task
  fields, one status transition (Doing runs the timer), and a date-words
  parser for English, Russian and Portuguese.

## 0.11.7+130

### Added

- **Images are blocks you can size and place.** An attached image now splits
  the paragraph at the cursor and sits on its own line. Tap it for a toolbar:
  size (S / M / full width), alignment (left / centre / right), move up or
  down, delete. Size and alignment are stored in the note as plain Typst, so
  the PDF matches. Images already in notes are left as they are until you
  change them; an image inside a list item stays inline.
- **Crop.** The same toolbar opens a crop screen (free, 1:1, 4:3, 16:9). The
  result is saved as a new file beside the original, which is kept.
- **Task timer.** Tasks in Library > Tasks and the Today agenda have a
  start/stop button, the running task shows in a floating pill with its
  elapsed time, and a task's total tracked time appears on its row. One timer
  runs at a time. A session under 30 seconds is dropped (with Undo); stopping
  a timer left running for too long asks whether to stop now or discard it.

## 0.11.6+129

### Fixed

- **A note written just before the server crashed is no longer deleted.** An
  upload the server acknowledged and then lost (a crash or restore) left the
  file missing remotely; the app read that as another device's deletion and
  removed its own copy. An upload now counts as proof only after the server
  lists the file again; until then a missing file is uploaded again.
- A folder listing cut off mid-response is rejected. Files missing from a
  truncated listing could be treated as deleted on the server.
- Before sync deletes or overwrites a local file whose content the server
  never confirmed, it keeps a copy under `.tylog/undo/sync-…` (30 days).
- Typing `@` to mention a note no longer stalls the keyboard on a large
  vault: the lookup scored every note again inside the sort (about 390 ms
  per keystroke at 5,000 notes on a desktop, now about 1 ms).

### Changed

- **Journal lists journal pages only.** The "Coming up" card and the empty
  days created for past events are gone; a day's events sit behind one
  collapsed "Agenda" line.

## 0.11.5+128

### Fixed

- **A sync conflict on a note's revision record no longer sticks forever.**
  When two devices wrote the same record and one then added a newer
  revision, the conflict could never clear, and that device ran a full sync
  every 20 seconds instead of a cheap check. Such conflicts now resolve
  themselves when one side's revision descends from the other; records that
  really diverged still wait for review.
- An upload race on a revision record no longer records a conflict between
  two identical copies.

## 0.11.4+127

### Changed

- **No more periodic full vault walk on Android.** Once a minute TyLog checks
  only the folders that contain subfolders (29 of 1,870 on the test vault)
  instead of re-reading every folder every five minutes: 9.5 s down to about
  1 s on a Huawei P30. A full walk still runs every 30 minutes and whenever
  the app is opened. A file another app rewrites in place while TyLog stays
  open is noticed at that walk.
- Index passes no longer read sync revision records as Typst inputs (7-9 s
  down to 1 s per pass on a Samsung A24).

## 0.11.3+126

### Changed

- **Much faster indexing on Android.** After a change, TyLog re-reads only
  the folders it wrote to instead of the whole vault (index pass: 13 s down
  to 3.5 s on a Huawei P30, 39-64 s down to 10 s on a Samsung A24). A file
  changed by another app while TyLog stays in the foreground is noticed
  within five minutes; changes made while TyLog is in the background are
  noticed when it is opened.

### Fixed

- Closing a vault no longer reports an error when the search cache cannot be
  written.

## 0.11.2+125

### Changed

- **Faster sync.** Changed Nextcloud folders are listed concurrently (about
  7 s down to 5 s per sync on a Huawei P30).
- The sync trace times every stage of the index pass.

## 0.11.1+124

### Changed

- **Faster indexing after a change.** The search index is no longer rewritten
  to disk after every changed note (about 7 s per change on a Huawei P30). It
  is kept in memory and saved at most every five minutes, and when the app
  goes to the background or closes.
- The sync trace records how long each index stage took.

## 0.11.0+123

### Added

- **Live Nextcloud updates.** While TyLog is open, servers with push support
  notify it of changes within a second or two; the sync that follows still
  takes several seconds. Other servers keep the usual 20-second check.

### Changed

- **Smaller Android download.** The APK is 85 MB instead of 204 MB; it now
  contains only the 64-bit ARM build.
- Mac releases also refresh the local note indexer and its Typst package.

### Fixed

- Existing `@` and `[[` matches appear before the new-page option, so Enter
  links the matching note instead of creating a stray page.
- Calendar event links resolve after creation, and long chip titles wrap
  without overlapping lines.

## 0.10.2+122

### Fixed

- **`@` and `[[` ignore accents.** Typing `@eti` now finds "Ética"; before,
  a class or note with an accented name only matched when typed with the
  accent.

## 0.10.1+121

### Fixed

- **Vault images stay out of the Android gallery.** TyLog writes a `.nomedia`
  file at the vault root and asks Android to rescan the folder, so screenshots
  and attachments already listed in the gallery disappear from it. iOS needs
  nothing: the Photos app never reads an app's files.

## 0.10.0+120

### Added

- **Sign in with browser.** The Connect Nextcloud screen can open your
  server's login page and receive an app password by itself (Login Flow v2).
- **Large files upload in pieces.** Files over 10 MB use chunked upload and
  resume after an interruption.

### Changed

- **One revision per editing session.** Repeated saves of a note update a
  single revision file instead of adding one per save.

### Fixed

- Sync bugs found by a new three-device soak test: stale or orphaned
  conflict records, leftovers after renames between Unicode forms, and
  entries for server files that no longer exist.

## 0.9.5+119

### Changed

- **Phones reuse the Mac's index without re-reading notes.** An index pass
  over 6,700 notes takes about 15 s on a P30 (was 42-58 s), and only notes
  edited on the phone are parsed there.
- **Deletes arrive faster** (12 s on a P30, was 31-41 s).

### Fixed

- Search opens while the index is rebuilding.
- Internal revision files no longer raise sync conflicts.

## 0.9.4+118

### Fixed

- Linux and Windows desktops publish the shared index too (0.9.3 limited it
  to macOS, which also broke the release build).

## 0.9.3+117

### Fixed

- **Sync kept working only by accident.** The 20-second check for server
  changes was blocked while the index scan ran (about 150 s on a phone), so
  a change could wait minutes. Indexing now runs separately (measured on a
  Galaxy A24: edits arrive in 0-7 s, deletes in about 40 s).
- Old conflicts on article job files resolve themselves and no longer make
  every check re-list folders.

## 0.9.2+116

### Changed

- **Sync is near-instant between open devices.** A change on the server now
  reaches a phone in seconds (measured on a Galaxy A24: edits 0-9 s, deletes
  11 s; before 44-104 s). Routine checks no longer rescan the whole vault or
  list the whole server.
- **One shared index.** Phones reuse the index the Mac publishes instead of
  computing and uploading their own 8 MB copy; stale index files from old
  installs are removed.

### Fixed

- Conflicts on machine-written article job files resolve by themselves.

## 0.9.1+115

### Changed

- **Faster sync between devices.** A saved note uploads about 3 seconds
  after you stop typing, without scanning the whole server first. While the
  app is open it checks for changes every 20 seconds with one request, and
  only re-lists folders that changed (one request instead of ~12,900 entries
  when nothing changed).

### Fixed

- **Notes lost to an interrupted save on Android are restored** from the
  hidden copy the save left behind.
- The Notes tab no longer has a screenshot filter; screenshots live in the
  Screenshots tab grid.

## 0.9.0+114

### Added

- **Classes and lab on any day.** The Today agenda follows the day you are
  viewing; an empty day shows the next class and jumps there on tap. The
  Journal lists each day's classes, lab sessions and consultations, plus a
  "Coming up" block for the next seven days.
- **Link a note to an upcoming class.** `@` finds classes and lab sessions
  from a week back to two weeks ahead; picking one creates the event note
  once and links it.
- **Screenshot categories.** Screenshots group by category with filter chips.

### Fixed

- **Search finds words inside screenshot text**, including partial words.
- **`@` popup:** "Create page" is first, and the popup sits below the line
  you are typing so the text stays visible.

## 0.8.6+113

### Fixed

- **Sync no longer re-downloads hundreds of files every time.** Compressed
  downloads stored a different version tag than the server listing reports,
  so each sync fetched the same ~350 files again (minutes on slower phones),
  delaying your edits. A repeat sync now transfers nothing.
- **An edit made while the keyboard was mid-word could wait forever to sync.**

### Changed

- **Screenshot cards are square images** with the time and app on a dark
  gradient at the bottom.

## 0.8.5+112

### Fixed

- **No gaps between screenshot rows**, and the Mac shows the same grid.

## 0.8.4+111

### Changed

- **Screenshot cards are square**, so more fit on screen.

## 0.8.3+110

### Fixed

- **Screenshot cards show a real title.** Untitled screenshots use the first
  sentence of their description; the time and app line has no stray dots.

## 0.8.2+109

### Fixed

- **The date in Today and Journal fits.** It reads "Mon 5 Oct" and shrinks
  to fit instead of "Mon, Octob…".
- **Screenshots are a grid of cards.** Image, a readable title, and time
  and app; status and rating are in the card's menu, and the filters sit in
  one scrolling row. Works with large system text.
- **Old sync conflicts on files that are no longer synced disappear.**

## 0.8.1+108

### Changed

- **Today shows one Agenda.** Today's classes, lab slots, consultations and
  tasks, with overdue tasks in a collapsed group and a link to all tasks.
  Agenda and Continue reading start collapsed, so your note comes first.

### Fixed

- **No more "Custom Typst" chip on every daily.** TyLog's own import line is
  hidden like the rest of the note header.
- **Opening the app no longer creates a conflict on today's note.** Today's
  note is written when you first type, and an untouched copy yields to the
  real one from your other device.
- **Finder's `.DS_Store` and similar files no longer sync.**

## 0.8.0+107

### Added

- **Idea hub ideas live in TyLog.** Student ideas from openlabtwin arrive as
  idea notes (AI title, summary, keywords, links to matching ideas) with a
  dated History; the day view shows what happened to ideas that day.
  Approve or archive in TyLog and the hub follows. Mark your own note as an
  Idea and the hub normalizes and matches it, writing the result back.
- **Consultations students book with you** appear in the agenda and the day
  view, each with a note ready for what you discussed.

## 0.7.0+106

### Added

- **Your classes and the lab schedule are in the agenda.** Settings ▸
  Calendars takes the IADE timetable (filtered by your group) and the lab
  calendar. Classes and lab slots show in Today, the journal day and the
  calendar, also offline. Open one, or link it with `@`, and TyLog creates
  a note for it to write what was asked or discussed; it is created once and
  reused, and a changed or cancelled lesson keeps your text.

## 0.6.0+105

### Added

- **Share a link to TyLog.** Android's share sheet offers TyLog: "Save as
  article" queues the link and the Mac worker turns it into an article note
  using the Studio model; it shows as "queued" in Articles until done. "Add
  to today" puts the link in today's note.

### Changed

- **The clock in the top bar always writes into today.** From any screen it
  opens today's note and starts a new "- HH:mm" line.
- **Today opens with Agenda and Tasks collapsed**, so your note comes first.

## 0.5.4+104

### Fixed

- **The Mac app no longer crashes when you quit.** Quitting could free the
  database while background work still held queries, which macOS reported
  as "TyLog quit unexpectedly". The app now saves, stops sync and indexing,
  and closes the database before it exits (at most three seconds).

## 0.5.3+103

### Changed

- **Tasks is an agenda, not a list of everything.** Open tasks are grouped
  into Overdue, Today, Upcoming by day, Later and No date (by project,
  collapsed); recently done tasks sit in a collapsed section. Filter by
  Open, Done or All, by project, or by text. Undated tasks from daily notes
  sit under "From journal", grouped by month, newest first.
- **The Voronoi map opens quickly.** Communities appear first; a cell's
  notes are laid out when you zoom into it, and very large cells show their
  biggest notes plus a "+N more" cell that opens the rest as a list.

## 0.5.1+101

### Fixed

- **Sync no longer stops at a compressed file.** Cloudflare sends small JSON
  files gzip-compressed; the download check compared the unpacked file with
  the compressed size and called it truncated, so every sync failed at the
  same file and never finished. Compressed downloads now pass.

## 0.5.0+100

Screenshot capture, in-app semantic search, a PDF reader, and a quieter sync.
Everything since `v0.4.4+99`, including the move to durable local storage.
No forced note re-index: database schema 9 adds its path index automatically.
Semantic search needs a one-time model download and an initial embedding pass.

### Added

- **Screenshots have their own shelf.** The `screenshot` kind has inbox,
  kept, acted and archived states, plus a rating. Library groups captures by
  source app or month; the day view shows thumbnails in capture-time order,
  and the calendar marks days with screenshots.
- **Screenshot OCR has settings.** Off, Watch, Schedule and Process now
  control the existing Mac OCR producer through a launch agent; Android sends
  a run request through the vault. The settings show the producer's last run,
  pending work, duplicates, sensitive skips and errors.
- **Time is a magic action.** `/time`, `/now` and `/current time` insert
  `HH:mm`; the day page also offers a quick `- HH:mm ` capture line. `/image`,
  `/photo` and `/picture` find the attachment action.
- **Semantic search runs in the app.** Maintenance ▸ Semantic search offers
  the model download, then indexes notes incrementally with visible progress.
  Search combines keyword and meaning-based matches, works while indexing,
  and opens cited notes or the matching passage in a version-checked PDF.
  Interrupted embedding work resumes rather than starting over.
- **PDFs open in a reader.** Text and image-only pages render in the app;
  protected files ask for a password and let you retry or cancel. Highlights
  survive reopening, sync as revisions, and travel in portable exports.
  Replacing or re-indexing a PDF reattaches matching highlights; ambiguous
  anchors are offered for review and reassignment.
- **The graph can be shared as SVG.** Export SVG sends the visible bounded
  graph through the platform share sheet.

### Fixed

- **Sync no longer deletes accented filenames on macOS.** Nextcloud's NFC
  spelling and a local NFD spelling could look like a rename, causing sync to
  write and then delete the same APFS file. Names now compare canonically
  while disk operations keep the real local spelling; ambiguous names stop
  visibly instead of being merged.
- **Server locks and temporary failures are retried.** HTTP 423 and 429,
  common 5xx failures and Cloudflare 520–530 responses get a bounded retry
  window instead of aborting immediately. Concurrent uploads also wait for
  their shared destination folder to finish being created.
- **Edits made outside TyLog are checked before a download.** A same-size,
  same-timestamp change could evade the cached listing and be overwritten.
  Sync now checks the actual bytes and preserves a conflict when needed.
- **Resolving a conflict waits for a running sync.** The row says it is
  waiting instead of refusing the tap while background polls hold the vault.
  Concurrent conflict-record writes no longer overwrite one another.
- **A failed save keeps the editor open.** Opening another note or switching
  vaults requires a successful save. Task, status and rating changes use the
  open buffer, so a later autosave cannot undo them; stale operations from a
  previous vault no longer publish into the newly selected one.
- **Search updates when indexing finishes.** An open search reruns against
  the new index, saved searches no longer overwrite each other or leave stale
  chips, and opening a result deleted since the search fails visibly.
- **Inserted images appear in preview and export immediately.** Asset loads
  belong to the note that requested them, and PDF export waits for its files.
  Reports load their selected notes and dependencies rather than the whole
  vault, and show preparation progress and failures.
- **Stopping indexing no longer strands the worker.** Closing or switching
  vaults completes outstanding work; late-stage cancellation is honoured.
  Failed syncs only refresh the index if local content changed, and startup
  no longer repeats a scan already completed by sync.
- **Long-note editing keeps pending changes and undo.** The editing window
  flushes before navigation, preserves focused undo, and resets its history
  when the source changes. Closing the PDF password dialog no longer crashes
  during its exit animation.

### Changed

- **Autosave sync is calmer.** Typing triggers at most one autosave sync every
  two minutes; closing a note or backgrounding still syncs immediately.
  Brief automatic-sync failures show "Offline — changes saved, will sync";
  repeated failures still surface an error.
- **Preview fits the screen.** Compiled Typst uses a continuous page that
  refits on resize or rotation, including plain daily notes without the TyLog
  template. The view-mode menu gives Edit, Read, Preview and Source their own
  icons.
- **PDF page size is an export setting.** Settings offers A4, Letter, A5 and
  Legal for both note sharing and report PDFs, independently of the preview.
- **Managed themes upgrade to v2.** Unmodified v1 copies upgrade automatically,
  including those missing the final blank line. Customized themes are kept;
  they need to adopt the preview/export inputs to follow the new layout.
- **Semantic indexing spends less time looking up paths.** Schema 9's path
  index replaces repeated full-table JSON scans; a 6,500-note resync fell from
  59 to 10 ms. Pending chunks are recounted every 16 batches, model sessions
  are reused, and a leaner tokenizer reduces memory use on Android.
- **Large vaults do less work on the screen thread.** Startup cache decoding
  moves off it, note lists and pickers use bounded pages, and keyword search
  uses incremental SQLite FTS. Long notes edit through a bounded window;
  graph layout is capped at 200 nodes and 500 edges and cached per mode.
- **Note edits have durable local revisions.** Creation and edits are recorded
  atomically in SQLite, with a persistent publication queue, conflict-aware
  revision receive, resumable imports and portable recovery snapshots.
- **Heading levels and saved-search deletion have tap controls.** Neither
  needs a long-press to be discovered.

## 0.4.3+98

An audit of the 0.4.x batch, several of whose findings were created by that
batch's own fixes interacting. No re-index.

### Fixed

- **"Keep Nextcloud's version" could delete the file it offered to keep.** A
  conflict whose remote was deleted keeps its last known content as evidence,
  and the dialog was showing that as a live side. When it happened to contain
  more than the local file, the dialog preselected it and promised "Keeping it
  loses nothing" — while resolving it deleted the local file. The record is now
  authoritative about which sides exist.
- **A conflict could be deleted while you were still holding an edit.** The
  self-heal that removes spurious conflicts compared two *frozen* copies rather
  than the file as it stands. Edit a note, have another device upload the older
  copy, and the conflict vanished with your edit never reaching the server.
- **Background sync stopped for the whole vault over one conflict.** The
  foreground stopped doing this in 0.4.0; the background service kept it — the
  unattended path, and the one that caused the original four-hour stall. It was
  self-perpetuating, because the repairs that clear such a conflict only run
  inside the sync it was blocking.
- **A bulk resolve could report successes it had not performed**, including
  "Resolved 3" over a vault with no connection configured. It now refuses
  visibly and counts only what actually landed.
- **A failed save is no longer discarded** when you keep typing. The write had
  not reached disk, but the error was dropped and the editor still showed a
  save as pending.
- **A note whose formatting could not be read no longer keeps old metadata
  under the new file's identity** — it described one version of a note while
  claiming to be another, was never re-read, and was shared with your other
  devices in that state.
- **Search stops disagreeing with the index it was built from.** Its documents
  are cached against note content, so a change to how tags are derived never
  reached them.
- Index sharing is more careful about provenance: entries whose origin cannot
  be vouched for no longer travel to other devices as though they were current,
  and stale shared indexes that could never be read are now cleaned up.
- The desktop CLI stopped rewriting both indexes on every run, and `tylog
  dedupe` now reads note metadata properly before deciding what to delete.
- Housekeeping no longer gives up after the first file it cannot touch, and the
  background service cleans up after itself rather than leaving it for the next
  time the app is opened.

## 0.4.2+97

Resolving a sync conflict stops being a guessing game. No re-index.

### Added

- **Resolve all.** A backlog of conflicts takes one choice applied to every
  file, reindexing once at the end rather than once per record. Nothing is
  preselected and the confirmation says plainly what is lost — a bulk
  keep-local can discard whatever the other side added to every file at once.
  Offered only for more than one conflict; a single conflict is a decision, not
  a chore. A batch that fails partway stops and reports what actually resolved.

### Fixed

- **A resolve says it is working.** It is a network write plus an index
  refresh, and for all of it the row stayed identical to one nobody had tapped.
  The row now shows its own progress, and the resolve reports as soon as the
  remote write and cleanup land instead of waiting on a full rescan plus a
  queued repeat — the ten minutes that made a working resolve look broken.
- **A moved remote is re-decided, not refused.** A conflict record freezes the
  remote ETag, so on a vault with a live producer it goes stale constantly, and
  every resolve threw "Nextcloud changed again". It now refreshes and compares
  the bytes you were actually shown: a file re-uploaded with identical content
  proceeds, and only genuinely different content stops — saying so, rather than
  telling you to go run a sync.
- **A failure is never invisible.** Two separate mechanisms hid sync errors:
  the status ranked "Syncing…" above them, and any pending conflict discarded
  them outright. Errors now have their own place on the Sync screen.
- **Conflict rows are keyed by file**, so a list that refreshes under your
  finger can no longer move a different record under the tap.
- **The search index is no longer rewritten when nothing changed** — ~43 MB
  encoded and ~12 MB written on every no-op scan, on two of the four paths that
  save it.

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
