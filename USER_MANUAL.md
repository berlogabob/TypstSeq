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

Primary areas are Today, Journal, Tasks, and Library. Library contains Notes, Projects, Articles, Calendar, Search, and Graph. Android uses bottom navigation; macOS uses a navigation rail.

Android and macOS are the release platforms. The included iOS host supports development checks on iPad. A physical iPad run requires selecting an Apple development team in `ios/Runner.xcworkspace`, allowing Xcode to register and provision the device, and trusting the development certificate on the iPad. An iPad simulator does not require signing.

Edits autosave atomically. Source shows exact Typst. Preview renders exact output. Split mode places them together. Normal mode presents supported content as editable blocks; unsupported Typst is preserved in a source block and can be edited at its exact range.

## Magic

The persistent Magic button and `/` palette can insert or transform:

- note link/create, tag, task, date, and project
- citation and attachment
- heading, bold, italic, table, and equation
- filtered report

Date and file actions use native pickers. Citations come from `_system/bibliography.yml`. Generated text is escaped Typst.

Reports filter project, date range, kind, tags, article status, and task status. Their reproducible source is stored under `outputs/`; PDF export writes a sibling `.pdf`. Both are syncable.

## Nextcloud

Desktop-managed Nextcloud folders continue to work. Embedded WebDAV is configured in Settings with server URL, login, and an app password.

On first launch, Android asks whether to use private app storage, a chosen device folder, or Nextcloud. Nextcloud setup also asks for the remote folder; nested paths such as `Research/TyLog` are supported. Server, login, password, and folder drafts are saved in TyLog's private app storage as they are entered, so switching to a password manager does not clear the form.

TyLog syncs durable v5 roots: `daily`, `notes`, `projects`, `articles`, `assets`, `outputs`, and `_system`. It excludes `_index`, `.tylog` operational state, temporary files, and conflict caches. Autosave completes before sync. Checksums, atomic transfers, polling, repair, and conflict copies are retained.

When both copies changed, open Problems, select the conflict, compare device and Nextcloud versions, edit the final text, and save the resolution.

## Backup and troubleshooting

Back up the complete vault. The authoritative data is the Typst content, assets, system files, and output sources/PDFs. `_index` can be deleted and rebuilt.

If metadata, search, or backlinks appear stale, choose Rebuild index. If Preview fails, switch to Source and fix the reported Typst range. If sync fails, verify HTTPS, credentials, remote folder permissions, and that the remote folder was created for v5.

If an iPad run reports that no development certificates are available, open `ios/Runner.xcworkspace`, select Runner > Signing & Capabilities, sign in to Xcode, and choose a team. Then rerun `flutter run -d <device-id>`. This is host signing configuration, not a vault or application-data error.

Open implementation and device checks are recorded in [GitHub issue #42](https://github.com/berlogabob/TypstSeq/issues/42), labeled `status:check-needed`.

TyLog deliberately has no arbitrary-Typst WYSIWYG, realtime collaboration, automatic conflict merging, AI/RAG, or plugin API.
