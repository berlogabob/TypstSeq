# TyLog v5 user handbook

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

Journal and opened notes show clean, styled blocks by default. Tap a line or block to edit only its exact Typst source; the rest of the document stays covered. Edits autosave atomically. The top view button cycles Editor → Preview → Source → Editor; Split editor remains available for source and output together.

Tapping a note link whose target does not exist offers to create that note (like Logseq/Obsidian). If two notes share the linked title, a picker lists both owners.

Search supports saved presets: run a query, press the Save chip, and it appears as a tappable chip on the Search screen. Presets are stored in `_system/saved-searches.json`, so they sync to every device. Long-press a chip to delete it.

## Import a Logseq or Obsidian vault

Settings → "Import Logseq/Obsidian vault" converts a whole vault folder into TyLog notes. The dialect is auto-detected (`.obsidian/` → Obsidian, `logseq/` or `journals/` → Logseq; otherwise TyLog asks). Pages become `notes/`, journals become `daily/YYYY/MM/`, Logseq TODO bullets become real TyLog tasks, wikilinks become note references (`[[Target|Alias]]` keeps the alias as display text), and referenced images/files are copied into `assets/logseq/` or `assets/obsidian/`. A report lists conversions, skipped empty files, copied assets, and unresolved links — those become create-on-tap targets. On Android, pick the source folder when prompted; access is one-shot and not retained.

## Magic

The persistent Magic button and `/` palette can insert or transform:

- note link/create, tag, task, date, and project
- citation and attachment
- heading, bold, italic, table, and equation
- filtered report

Date and file actions use native pickers. Citations come from `_system/bibliography.yml`. Generated text is escaped Typst.

Reports filter project, date range, kind, tags, article status, and task status. Their reproducible source is stored under `outputs/`; PDF export writes a sibling `.pdf`. Both are syncable.

## Nextcloud

Desktop-managed Nextcloud folders continue to work. Embedded WebDAV is configured from Settings > Sync with server URL, login, and an app password.

On first launch, Android requires a user-selected device folder and retains access through Android's Storage Access Framework. The selected folder is the authoritative vault and remains outside TyLog's private app container. Existing private vaults are copied and hash-verified before switching; the original is retained as a recovery backup. Nextcloud setup also asks for the remote folder, and nested paths such as `Research/TyLog` are created one segment at a time. Server, login, password, and folder drafts are saved in TyLog's private app storage as they are entered, so switching to a password manager does not clear the form.

TyLog syncs durable v5 roots: `daily`, `notes`, `projects`, `articles`, `assets`, `outputs`, and `_system` (which includes saved searches in `_system/saved-searches.json`). It excludes `_index`, `.tylog` operational state, temporary files, and conflict snapshots. Autosave completes before sync. Checksums, conditional uploads/deletions, atomic transfers, polling, and repair are retained.

The Sync dashboard shows the complete bounded diagnostic log, transfer/deletion totals, storage access, and unresolved conflicts. Text conflicts support editing a final version. Binary and delete-versus-edit conflicts offer explicit device/Nextcloud choices. Sync never overwrites a version whose remote ETag changed during resolution.

## Backup and troubleshooting

Back up the complete vault. The authoritative data is the Typst content, assets, system files, and output sources/PDFs. `_index` can be deleted and rebuilt.

If metadata, search, or backlinks appear stale, choose Rebuild index. If Preview fails, switch to Source and fix the reported Typst range. If folder permission is revoked, reselect the vault when prompted. If sync fails, open the Sync dashboard, inspect the failed stage, and verify HTTPS, credentials, and remote folder permissions.

If an iPad run reports that no development certificates are available, open `ios/Runner.xcworkspace`, select Runner > Signing & Capabilities, sign in to Xcode, and choose a team. Then rerun `flutter run -d <device-id>`. This is host signing configuration, not a vault or application-data error.

Open implementation and device checks are recorded in [GitHub issue #42](https://github.com/berlogabob/TypstSeq/issues/42), labeled `status:check-needed`.

TyLog deliberately has no arbitrary-Typst WYSIWYG, realtime collaboration, automatic conflict merging, AI/RAG, or plugin API.
