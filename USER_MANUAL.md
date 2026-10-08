# TyLog v5 user handbook (0.12.0)

## Vault format

TyLog stores research content as valid Typst:

```text
daily/YYYY/MM/YYYY-MM-DD.typ
notes/
projects/
articles/
assets/
outputs/
_system/tylog.typ
_system/theme.typ
_system/export.typ
_system/bibliography.yml
_index/index.json
_index/search-index.json.gz
.tylog/settings.json
.tylog/sync_state.json
```

`_index` is rebuildable. `.tylog` contains operational state. Do not move an old vault into this layout: v5 refuses old schemas without modifying them. Create a new vault and preferably a new empty Nextcloud remote folder.

## Typst interface

```typst
#import "/_system/tylog.typ" as tylog

#show: tylog.note.with(
  id: "note-id",
  title: "Example",
  kind: "note",
  date: none,
  tags: ("research",),
  aliases: (),
  project: none,
  properties: (:),
)

#tylog.ref-note("other-id")[Visible title]
#tylog.tag("delivery")
#tylog.task(id: "task-id", text: "Write report", due: none, project: none)
#tylog.date-ref("2026-07-13")[13 July]
#tylog.attachment("/assets/file.pdf")[File]
```

Projects and articles are ordinary notes with `kind: "project"` or `kind: "article"`.

## Workspace

TyLog opens on Today. Today contains quick capture, due tasks, referenced dates, recent notes, backlinks, and inbox notes.

Primary areas are Today, Journal, Tasks, and Library. Library contains Notes, Projects, Articles, Calendar, Search, and Graph. Graph offers five views: Concept map, Focused, All files, Timeline, and Voronoi. Voronoi packs the vault into zoomable cells — community, then tag, then note — sized by note count; zooming or tapping a cell reveals the level below, and tapping a note cell opens the note. Android uses bottom navigation; macOS uses a navigation rail.

Android and macOS are the release platforms. The included iOS host supports development checks on iPad. A physical iPad run requires selecting an Apple development team in `ios/Runner.xcworkspace`, allowing Xcode to register and provision the device, and trusting the development certificate on the iPad. An iPad simulator does not require signing.

Journal lists existing journal pages only, newest first. A day with events has one collapsed Agenda line; expand it to see the events. Events alone do not add empty days or a Coming up card.

Journal and opened notes show clean, styled blocks by default. Tap a line or block to edit only its exact Typst source; the rest of the document stays covered. Edits autosave atomically. The top view button cycles Editor → Preview → Source → Editor; Split editor remains available for source and output together.

Tapping a note link whose target does not exist offers to create that note (like Logseq/Obsidian). If two notes share the linked title, a picker lists both owners.

Search supports saved presets: run a query, press the Save chip, and it appears as a tappable chip on the Search screen. Presets are stored in `_system/saved-searches.json`, so they sync to every device. Long-press a chip to delete it.

## Tasks

At the start of a line, type `TODO `, `[] ` or `[ ] `, or choose `/todo`, to turn it into a task without a dialog. Enter starts the next task. Enter on an empty task returns to plain text. Backspace at the checkbox, including on an empty task (0.12.2), turns the task into plain text; one Undo restores its fields.

On a task line, use `/todo`, `/doing`, `/done` or `/cancel` to set its status. Ctrl/Cmd+Enter cycles Todo → Doing → Done → Todo. Tap the checkbox to toggle Done; long-press it to choose any of the four statuses. The glyphs are ☐ Todo, ◐ Doing, ☑ Done and ☒ Cancelled. Completing a repeating task records an occurrence and keeps the repeat active.

Use `/a` for high priority, `/b` for normal, `/c` for low, or `/urgent`. `/due` sets a due date; `/scheduled` and its alias `/deadline` set a scheduled date. In the date popup, type English (`tomorrow`, `fri`), Russian (`завтра`, `пт`) or Portuguese (`amanhã`, `sexta`) words. It also accepts `15.10`, `15 oct`, ISO dates, `+3d` and `in 2 weeks`, with an optional time such as `14:30`. Pick a suggestion or press Enter; the calendar icon opens the grid picker. `/repeat` offers daily, weekly, monthly and weekdays.

Priority, due and scheduled dates, repeat and tracked time appear beside the task. Tap a priority, date or repeat chip to change it in the same popup. Doing starts the timer; leaving Doing stops it. Starting another task returns the previous one to Todo. The running pill shows the task and elapsed time; its Stop button returns the task to Todo.

Today, Tasks, Journal, Calendar, Search and saved queries use the same task row, with checkbox, long-press status menu and chips. Tap its text to open the note. Quick add on Today and Tasks appends a task to today's journal page. It takes text literally: date words there do not set dates. The All filter includes cancelled tasks and older completed tasks.

## Images

An attached image splits the paragraph at the cursor and sits on its own line. Tap it for S (33%), M (60%) or Full (100%) width, left/centre/right alignment, move up/down and delete. Size and alignment are saved as Typst and appear in the PDF. Existing images keep their source until changed; images inside list items stay inline.

Crop offers free, 1:1, 4:3 and 16:9 selections. It saves a new PNG beside the original and updates the image reference. The original file is kept.

## Import a Logseq or Obsidian vault

Settings → "Import Logseq/Obsidian vault" converts a whole vault folder into TyLog notes. The dialect is auto-detected (`.obsidian/` → Obsidian, `logseq/` or `journals/` → Logseq; otherwise TyLog asks). Pages become `notes/`, journals become `daily/YYYY/MM/`, Logseq TODO bullets become real TyLog tasks, wikilinks become note references (`[[Target|Alias]]` keeps the alias as display text), and referenced images/files are copied into `assets/logseq/` or `assets/obsidian/`. A report lists conversions, skipped empty files, copied assets, and unresolved links — those become create-on-tap targets. On Android, pick the source folder when prompted; access is one-shot and not retained.

## Magic

The persistent Magic button and `/` palette can insert or transform:

- note link/create, tag, task, date, and project
- citation and attachment
- heading, bold, italic, table, and equation
- filtered report

General date and file actions use native pickers; task dates also accept typed words. Citations come from `_system/bibliography.yml`. Generated text is escaped Typst.

Reports filter project, date range, kind, tags, article status, and task status. Their reproducible source is stored under `outputs/`; PDF export writes a sibling `.pdf`. Both are syncable.

## Nextcloud

Desktop-managed Nextcloud folders continue to work. Embedded WebDAV is configured from Settings > Sync with server URL, login, and an app password.

On first launch, Android requires a user-selected device folder and retains access through Android's Storage Access Framework. The selected folder is the authoritative vault and remains outside TyLog's private app container. Existing private vaults are copied and hash-verified before switching; the original is retained as a recovery backup. Nextcloud setup also asks for the remote folder, and nested paths such as `Research/TyLog` are created one segment at a time. Server, login, password, and folder drafts are saved in TyLog's private app storage as they are entered, so switching to a password manager does not clear the form.

TyLog syncs durable v5 roots: `daily`, `notes`, `projects`, `articles`, `assets`, `outputs`, and `_system` (which includes saved searches in `_system/saved-searches.json`). It excludes `_index`, `.tylog` operational state, temporary files, and conflict snapshots. Autosave completes before sync. Since 0.12.1, typing during an upload does not create a conflict against this device's own earlier revision. Checksums, conditional uploads/deletions, atomic transfers, polling, and repair are retained.

Uploads count as confirmed only after the server lists the file again. A missing unconfirmed upload is retried, and incomplete folder listings are rejected. Before sync replaces or deletes unconfirmed local content, it keeps a local copy under `.tylog/undo/sync-…`, except system files and revision records. Sync copies are kept for 30 days and are not synced.

The Sync dashboard shows the complete bounded diagnostic log, transfer/deletion totals, storage access, and unresolved conflicts. Text conflicts support editing a final version. Binary and delete-versus-edit conflicts offer explicit device/Nextcloud choices. Sync never overwrites a version whose remote ETag changed during resolution.

## Backup and troubleshooting

Back up the complete vault. The authoritative data is the Typst content, assets, system files, and output sources/PDFs. `_index` can be deleted and rebuilt.

If text looks lost, back up the vault and `.tylog/undo` before further edits or sync. Check the note in Source, then inspect the local undo copies and Sync dashboard conflicts. Sync copies keep the original vault path under `.tylog/undo/sync-…`; copy recovered text into the note after reviewing it. Headerless journal pages are repaired with their text kept and an undo copy taken first. These copies are a safety net, not a complete version history.

A failed database/index save leaves your note file on disk and reports an error; retry the save or rebuild the index. If metadata, search, or backlinks appear stale, choose Rebuild index. If Preview fails, switch to Source and fix the reported Typst range. If folder permission is revoked, reselect the vault when prompted. If sync fails, open the Sync dashboard, inspect the failed stage, and verify HTTPS, credentials, and remote folder permissions.

If an iPad run reports that no development certificates are available, open `ios/Runner.xcworkspace`, select Runner > Signing & Capabilities, sign in to Xcode, and choose a team. Then rerun `flutter run -d <device-id>`. This is host signing configuration, not a vault or application-data error.

Open implementation and device checks are recorded in [GitHub issue #42](https://github.com/berlogabob/TypstSeq/issues/42), labeled `status:check-needed`.

TyLog deliberately has no arbitrary-Typst WYSIWYG, realtime collaboration, automatic conflict merging, AI/RAG, or plugin API.
