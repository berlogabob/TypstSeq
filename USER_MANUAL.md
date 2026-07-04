# TyLog user handbook

This handbook covers TyLog `1.0.0+23` on Android, macOS, and Linux.

## 1. What TyLog stores

TyLog is file-first. A vault is a normal folder:

```text
TyLogVault/
  journal/                 daily notes: YYYY-MM-DD.typ
  pages/                   named notes
  assets/                  imported files
  .tylog/
    templates/             optional page templates
    tylog.typ              Typst helper functions
    settings.json          vault settings
    tags.json              canonical tag registry
    files.json             managed-file registry
    collections.json       publication collections
    index.json             rebuildable note index
    search-index.json.gz   rebuildable search cache
```

Back up or sync the whole vault. The `.typ` files and registry JSON files are the durable data. `index.json` and `search-index.json.gz` are caches.

## 2. Install and start

Install the Android APK from the project’s GitHub Releases page, or run the Flutter app on macOS/Linux. The hosted web build is only a product landing page.

On first start TyLog creates or opens a default vault and creates today’s journal note. Desktop selection order is:

1. `TYLOG_VAULT_DIR`, if set.
2. `~/Nextcloud/TyLogVault`, if `~/Nextcloud` exists.
3. The first macOS `~/Library/CloudStorage/*Nextcloud*/TyLogVault` folder.
4. The application documents directory.

The current vault path appears in **Settings → Local folder**.

## 3. Navigate the app

The main workspace has these views:

- **Journal** — distraction-reduced body editor for the current note.
- **Source** — the complete Typst source, including metadata.
- **Preview** — rendered Typst output.
- **Graph** — notes and resolved links around the current note.
- **Knowledge** — search, tags, files, problems, and collections.

All native layouts use the same workspace. Choose the folder button to switch or manage vaults, Search to open Knowledge, and the looped-arrow button to switch Source and Preview. Tap the cloud status icon for plain-language sync details and the latest transfer graph. The overflow menu contains Today, New page, Graph, backlinks, rebuild, direct sync, and Settings. The title gains `•` while unsaved edits exist; the status line reports saves, rebuilds, sync, and errors.

## 4. Write notes

### Daily journal

Choose **Today** to create or open `journal/YYYY-MM-DD.typ`. Type in Journal or Source view. Editing schedules an autosave after 700 ms; a save also rebuilds the index and search cache.

While the editor has focus, the formatting dock inserts headings, emphasis, math, links, functions/tags, and new blocks without switching keyboard layouts.

### Pages

Choose **New page**, enter a title, and optionally select a template. Pages are stored in `pages/`. Slashes in titles are replaced with hyphens.

Templates are ordinary `.typ` files placed in `.tylog/templates/`. If none exist, TyLog creates a blank page.

### Source and preview

Use the Source/Preview control to edit the complete file or compile it. Preview errors are shown without replacing the saved source.

A normal note begins with:

```typst
#import "/.tylog/tylog.typ": *

#note(
  id: "20260704-120000-example",
  title: "Example",
  tags: ("reference",),
)

= Example
```

IDs identify notes even if titles change. Edit structured fields through **Context → Edit metadata** when possible.

PKMS v4 uses a real Typst module namespace:

```typst
#import "/.tylog/tylog.typ" as pkm
#pkm.link("note-id", display: "Linked note")
#pkm.tag("topic")
#pkm.property("status", "active")
#pkm.task(
  id: "task-id",
  text: "Write the report",
  priority: "high",
  due: "2026-07-05T09:00:00Z",
  recurrence: "RRULE:FREQ=WEEKLY;BYDAY=MO",
)
```

Use **Knowledge → Problems → Migrate vault to PKMS v4** to back up and rewrite older global helper calls. **Knowledge → Tasks** lists indexed tasks. Enable operating-system reminders in Settings. On macOS/Linux, **Typst help** and **Explain error** query a local TypstRAG checkout discovered through `TYPST_RAG_DIR` or a sibling `TypstRAG` folder.

## 5. Link and organize knowledge

### Note links

Create a visible link with:

```typst
#wikilink("Page title")
```

Selecting an outgoing unresolved link creates its page. TyLog resolves links against IDs, paths, titles, and aliases. Ambiguous links remain unresolved and appear in Problems instead of choosing silently.

The metadata editor can also store linked note IDs. The Context panel lists outgoing links, managed files, and backlinks.

### Tags

Inline tags use `#tag("slug")`. Canonical tags are managed in **Knowledge → Tags**.

- Create or edit a slug, title, type, and aliases.
- Merge rewrites affected note headers, inline tags, and file metadata; TyLog creates a backup under `.tylog/backups/` first.
- A tag cannot be deleted while notes or files use it.

`journal` is always recognized. Other tags should have a canonical registry entry.

### Search

Open **Search** in the workspace app bar. Search covers note IDs, titles, aliases, tags, source text, and managed-file metadata. Filters can restrict results by tag, file kind, or file status. Exact IDs and titles rank first. Use the Knowledge overflow menu for Tags, Files, Problems, and Collections; active sync conflicts appear as the first filter.

### Graph

Open Graph, select a node, then choose **Open**. Pan and zoom normally; **Fit graph** restores the complete view. For vaults over 100 notes, TyLog shows up to 100 notes within two link hops of the current note.

## 6. Manage files

Open **Knowledge → Files → Import file**. TyLog copies the file into `assets/`, chooses a unique name and ID, and adds it to `.tylog/files.json`.

File metadata includes title, kind, status, and tags. Reference a registered file from Typst with `#filelink("file-id")` or add its ID in the note metadata editor. Removing a registry entry does not promise to delete the physical asset; verify the asset folder before cleanup.

Registry and bibliography paths must remain relative to the vault. TyLog rejects unsafe paths and reports missing files.

## 7. Collections and PDF export

Open **Knowledge → Collections** to create an ordered publication:

1. Give the collection a title.
2. Enter note IDs in publication order.
3. Optionally enter a vault-relative `.bib` or YAML bibliography path.
4. Save, then use **Export PDF**.

TyLog compiles the selected notes through Typst and writes the exported document into the vault. Missing note IDs or bibliography files appear in Problems and should be fixed before export.

## 8. Problems and migration

**Knowledge → Problems** reports invalid registries, duplicate note IDs or aliases, unknown tags or files, unsafe paths, missing assets, collection errors, sync conflicts, and unverified legacy metadata.

Use the action shown for each problem. Important behavior:

- Invalid registry JSON blocks edits to that registry; repair the file rather than overwriting it with an empty registry.
- **Migrate legacy note headers** backs up notes before replacing legacy metadata calls with the current literal format.
- A custom `.tylog/tylog.typ` is preserved and reported as unverifiable. A recognized old stock helper is upgraded automatically.
- Rebuild can be cancelled. The last valid index remains available.

## 9. Vault management

Open **Settings → Vaults**.

- **Add or create vault** chooses a writable existing or empty folder.
- Select a vault to switch; dirty content is saved first.
- **Forget vault** removes it from TyLog but keeps every file.
- **Delete vault and files** permanently removes the directory. TyLog requires two confirmations, including typing the vault name, and does not allow deleting the only registered vault.

Never use permanent deletion as a way to disconnect a vault; use Forget.

## 10. Nextcloud sync

TyLog supports two distinct workflows.

### Desktop-managed folder

Place the vault inside a folder managed by the Nextcloud desktop client. TyLog recognizes common Nextcloud locations and leaves transfer to the desktop client. After external edits, choose **Rebuild index**.

### Embedded WebDAV

Open **Settings → Nextcloud settings** and enter:

- server URL, such as `https://cloud.example.com`
- login
- password or app password

If the URL is a server root, TyLog uses `remote.php/dav/files/<login>/TyLogVault/`. A full WebDAV files URL is also accepted.

Sync runs after a save, when the app starts or resumes, every 25 seconds while idle, and when **Sync** is pressed. Derived index/search caches are not authoritative sync content.

Credentials are currently stored by the application as local JSON, not in an OS secure credential store. Prefer a revocable Nextcloud app password and protect the device account.

### Conflicts

When both local and remote copies changed, TyLog preserves a conflict copy rather than silently overwriting either version. Open **Knowledge → Problems**, select the sync conflict, compare **This device** and **Nextcloud copy**, edit the final version if needed, and choose **Save resolution**.

Do not edit the same note on two offline devices if you can avoid it. TyLog resolves conflicts interactively; it does not perform automatic text merges.

## 11. External editing and backups

You may edit `.typ` files with any text editor. Keep paths under `journal/` or `pages/`, retain unique note IDs, and use **Rebuild index** after external changes.

### Import an existing Typst folder

1. Put page notes in `pages/` and dated notes in `journal/`; keep referenced files in `assets/`.
2. Open **Settings → Vaults → Add or create vault** and choose that folder.
3. Choose **Rebuild index**, then inspect **Knowledge → Problems** for duplicate IDs, aliases, or missing files.

TyLog reads the original `.typ` files directly. No conversion or import copy is required.

Recommended backup:

1. Close or pause editing.
2. Copy the complete vault folder.
3. Verify that `journal/`, `pages/`, `assets/`, and `.tylog/*.json` are present.

Safe to delete and rebuild:

- `.tylog/index.json`
- `.tylog/search-index.json.gz`

Do not casually delete:

- notes under `journal/` or `pages/`
- `assets/`
- `.tylog/tags.json`, `files.json`, or `collections.json`
- `.tylog/tylog.typ`
- `.tylog/backups/` until a migration or merge is verified

## 12. Troubleshooting

### A note or backlink is missing

Choose **Rebuild index**. Then inspect Knowledge → Problems for invalid Typst metadata, duplicate IDs, or ambiguous links.

### Preview fails

Switch to Source and read the displayed Typst error. Confirm the helper import is `/.tylog/tylog.typ` and that referenced assets or bibliography files exist.

### Search is stale

Rebuild the index. If necessary, close TyLog, delete `.tylog/search-index.json.gz`, and reopen; it is a disposable cache.

### Registry edits are blocked

Open the named JSON file under `.tylog/`, repair its JSON syntax or restore it from backup, then rebuild. TyLog intentionally avoids overwriting malformed durable metadata.

### Sync does not start

Verify all three Nextcloud fields are present, the server uses HTTPS, the app password is valid, and `TyLogVault` is writable. Press Sync and read the status message.

### A conflict remains after resolution

Return to Problems and use the conflict action again. If stale conflict/cache files remain after the content is resolved, use the offered cache-cleaning action; do not delete the primary note.

### The app opens the wrong vault

Open Settings → Vaults and select the intended entry. On a new desktop installation, also check `TYLOG_VAULT_DIR` and the automatic Nextcloud paths described in section 2.

## 13. Current limits

TyLog has no WYSIWYG editor, realtime collaboration, automatic conflict merge, plugin API, encryption layer, or full browser client. The native app is intentionally a small file-based system; use ordinary filesystem backup and access controls around the vault.
