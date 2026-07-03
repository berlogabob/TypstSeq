# TyLog MVP Plan

Status legend:
- [ ] not started
- [~] in progress
- [x] done
- [!] blocked / decision needed

Last updated: 2026-07-02 — MVP release v1.0.0+6
Mode: Ponytail full — smallest useful app, file-first, no speculative platform.

## Current build status

- [x] Phase 0 — repo setup: Flutter app created, TyLog app labels set, macOS debug build produced.
- [x] Phase 1 — local vault creation: app-owned vault, `.tylog/`, helper Typst file, today note creation implemented and tested.
- [x] Phase 2 — clean journal editor: autosave, dirty state, safe temp-file write implemented and tested.
- [x] Phase 3 — scanner and index: regex scanner, backlinks, index JSON implemented and tested.
- [x] Phase 4 — navigation and page creation: outgoing links open existing notes or create missing pages; manual index rebuild added.
- [x] Phase 5 — Typst preview
- [x] Phase 6 — graph
- [x] Phase 6.5 — UX/UI layout pass: daily-first Material shell, mobile drawers, desktop collapsible side panels, clean journal/source/preview modes
- [x] Phase 7 — Android/desktop hardening: release signing and embedded Nextcloud WebDAV sync added
- [x] Phase 8 — Nextcloud workflow doc
- [x] Phase 9 — MVP cut

Evidence: `flutter analyze` no issues, `flutter test` 17 tests passed, `make release` produced GitHub release `v1.0.0+6` with APK asset `app-release.apk`. Nextcloud WebDAV write/read/delete was verified (`put 201`, `get_ok True`, `delete 204`). Previous MVP evidence: release APK built, `sample_vault/` added, and automated MVP smoke test covers today note, wikilink, PKM page, backlink persistence, index deletion, and rebuild.


## 0. Product thesis

TyLog is a local-first PKM journal app built around Typst files.

It should feel inspired by Logseq, Obsidian, and org-mode, but the first MVP is much smaller:

- daily journal page
- plain Typst notes
- wikilinks
- backlinks
- graph
- local folder vault
- Android + macOS + Linux via Flutter
- Nextcloud-friendly storage

Core rule: user data is plain files. Indexes are derived caches. If cache is deleted, the vault still works.

## 1. Non-goals for MVP

These are deliberately skipped until the small version proves useful.

- [ ] No database as source of truth
- [ ] No custom block database
- [ ] No realtime collaboration
- [ ] No plugin API
- [ ] No rich/WYSIWYG editor
- [ ] No AI features
- [ ] No full Obsidian clone
- [ ] No import/export wizard in MVP
- [ ] No git sync in MVP
- [ ] No multi-user sharing
- [ ] No encrypted vault in MVP
- [ ] No web app target in MVP

Reason: every item above can be added later without changing the basic file-vault model.

## 2. MVP success definition

MVP is done when this works on at least Android + one desktop platform:

- [ ] User opens or creates a vault folder
- [ ] App creates today's journal note
- [ ] User edits Typst source
- [ ] App saves the file safely
- [ ] App detects `#wikilink("Page")` links
- [ ] App shows backlinks for the current note
- [ ] App shows a basic graph of notes and links
- [ ] App renders a Typst preview for current note
- [ ] App rebuilds index from files on startup
- [ ] Vault can be synced by Nextcloud desktop/mobile sync without special server

## 3. Storage model

### 3.1 Vault layout

Use a folder, not one huge file.

```text
TyLogVault/
  journal/
    2026-07-01.typ
  pages/
    TyLog.typ
    PKM.typ
  assets/
  .tylog/
    settings.json
    index.json
    tylog.typ
```

### 3.2 Source of truth

- [ ] `.typ` files are source of truth
- [ ] `.tylog/index.json` is derived cache only
- [ ] `.tylog/settings.json` is vault settings
- [ ] `.tylog/tylog.typ` contains tiny Typst helpers
- [ ] attachments live in `assets/`

If `.tylog/index.json` is missing or corrupt, rebuild it.

### 3.3 Note format

Minimum valid note:

```typst
#import "/.tylog/tylog.typ": *

#note(
  title: "2026-07-01",
  date: "2026-07-01",
  tags: ("journal",),
)

= 2026-07-01

Write here. Link to #wikilink("PKM").
```

### 3.4 Helper package MVP

`.tylog/tylog.typ` should stay tiny:

```typst
#let note(title: none, date: none, tags: (), aliases: ()) = {
  metadata((
    title: title,
    date: date,
    tags: tags,
    aliases: aliases,
  )) <tylog-note>
}

#let wikilink(target, display: none) = {
  metadata((target: target, display: display)) <tylog-link>
  if display == none { target } else { display }
}

#let tag(name) = {
  metadata(name) <tylog-tag>
  [#name]
}
```

Ponytail note: do not implement a large Typst package until the simple helper fails.

## 4. Sync model

### 4.1 MVP sync

Use existing filesystem sync first.

- [ ] macOS/Linux: user selects a folder already synced by Nextcloud Desktop
- [ ] Android: user selects local app folder or SAF-accessible synced folder if possible
- [ ] App does not own sync protocol in first MVP

Reason: Nextcloud already syncs files. TyLog should not become a sync product before it is a useful notes app.

### 4.2 Later sync option

Add direct WebDAV only when folder sync is not enough.

Candidate packages:
- `nextcloud`
- `webdav_client`
- `file_picker`
- `path_provider`

Direct WebDAV requirements before implementation:
- [ ] conflict file policy defined
- [ ] safe upload/download temp files
- [ ] never overwrite newer remote/local file silently
- [ ] visible sync status

## 5. Flutter technical baseline

### 5.1 App stack

Use boring Flutter.

- [ ] Flutter stable
- [ ] Riverpod for app state if needed
- [ ] GoRouter only if navigation grows beyond 2-3 screens
- [ ] `file_picker` for folder selection where supported
- [ ] `path_provider` for app-owned default vault
- [ ] `typst_flutter` for Typst render preview
- [ ] one graph package only after simple custom painter is insufficient

Ponytail default: start with fewer dependencies. Add package only when code proves it needs it.

### 5.2 Candidate dependencies

Initial dependency candidates:

```yaml
dependencies:
  flutter:
    sdk: flutter
  path_provider: ^2.1.6
  file_picker: ^11.0.2
  typst_flutter: ^2.2.1
```

Delay these:

```yaml
# Add later only if needed.
flutter_riverpod: any
flutter_graph_view: any
nextcloud: any
```

## 6. App screens

### 6.1 MVP screens

- [ ] Home / Journal screen
- [ ] Editor screen
- [ ] Backlinks panel
- [ ] Graph screen
- [ ] Settings screen

### 6.2 Home / Journal

Must do:
- [ ] show today's date
- [ ] create/open `journal/YYYY-MM-DD.typ`
- [ ] list recent journal notes
- [ ] button: New page
- [ ] button: Graph
- [ ] button: Settings

Skip:
- calendar heatmap
- timeline filters
- templates beyond default note

### 6.3 Editor

Must do:
- [ ] load `.typ` file
- [ ] edit plain text
- [x] save manually
- [ ] autosave after debounce only after manual save is reliable
- [x] show dirty state
- [ ] show parse/index errors without losing text
- [ ] toggle source / preview

Skip:
- WYSIWYG
- syntax highlighting at first if plain TextField is enough
- multiple tabs
- collaborative cursor

### 6.4 Backlinks panel

Must do:
- [ ] current note title/path
- [ ] outgoing links
- [ ] incoming backlinks
- [ ] tap backlink opens source note

Backlink source for MVP:
- derived by scanning every `.typ` file for `#wikilink("...")`

Skip:
- block-level backlink context
- transclusion
- unlinked mentions

### 6.5 Graph screen

Must do:
- [ ] nodes = notes
- [ ] edges = wikilinks
- [x] tap node opens note
- [ ] current note highlighted

First graph can be crude:
- circular layout
- straight lines
- no physics

Ponytail: use CustomPainter first. Add graph package only when the simple painter becomes painful.

### 6.6 Settings

Must do:
- [ ] show vault path
- [ ] create/select vault
- [x] rebuild index button
- [ ] show app version

Skip:
- theme editor
- plugin settings
- account system

## 7. Indexing

### 7.1 Indexed data

`NoteIndex` fields:

- path
- title
- date
- tags
- aliases
- outgoingLinks
- modifiedAt

`VaultIndex` fields:

- notes map
- backlinks map
- builtAt
- version

### 7.2 Scanner MVP

Use simple text scanning first.

Patterns:
- `#note(...)` enough to get title/date/tags when simple
- `#wikilink("Target")`
- `#wikilink("Target", display: "Text")`
- `#tag("name")`

Known ceiling:
- scanner is not a full Typst parser
- upgrade path: use `typst query` / typst metadata when native integration is stable enough on all platforms

Required marker in code when implemented:

```dart
// ponytail: regex scanner, replace with Typst metadata query when syntax coverage hurts real notes.
```

### 7.3 Rebuild policy

- [ ] on startup, scan vault if `index.json` missing
- [ ] scan changed file after save
- [ ] manual rebuild button
- [ ] never block editing because index failed

### 7.4 Index tests

Minimum runnable checks:
- [x] scanner extracts one wikilink
- [x] scanner extracts multiple wikilinks
- [x] backlink map reverses links correctly
- [x] bad Typst text does not crash scanner

No test framework bloat beyond default Flutter test.

## 8. File safety

Must not lose notes.

- [ ] write through temp file then rename where platform supports it
- [ ] keep text in memory if save fails
- [x] show save error
- [ ] never delete user notes from index rebuild
- [ ] ignore `.tylog/` during note scan except settings/index
- [ ] ignore hidden files by default
- [ ] handle duplicate page titles deterministically

Duplicate title policy MVP:
- if two notes resolve to same title, link target picks exact filename stem first
- otherwise show ambiguous link state later
- do not invent hidden IDs yet

## 9. Link resolution

MVP target resolution order:

1. exact note title
2. exact filename stem
3. alias
4. unresolved

When creating a link to missing page:
- [x] tap unresolved link offers create page
- [x] creates `pages/Target.typ`

Filename sanitizer:
- replace `/` and path separators with `-`
- trim whitespace
- reject empty name

## 10. Typst preview

Use `typst_flutter` if it works on target platforms.

Must do:
- [ ] render current note preview
- [ ] show compile errors
- [ ] do not block editing while preview compiles
- [ ] preview can be manually refreshed first

Skip initially:
- live preview on every keystroke
- PDF export
- custom fonts
- bibliography

Fallback if `typst_flutter` blocks MVP:
- [ ] keep source editor + index features
- [ ] mark preview blocked
- [ ] desktop can shell out to `typst` later, Android cannot rely on shell

## 11. Android constraints

Need verify early.

- [ ] Can create app-owned vault
- [ ] Can pick folder with Storage Access Framework or practical alternative
- [ ] Can read/write `.typ` files repeatedly
- [ ] Can Typst render via `typst_flutter`
- [ ] Can external Nextcloud app sync chosen folder, or document workaround

Ponytail path:
- App-owned local vault first
- Folder picker second
- Direct WebDAV later only if Android folder sync is bad

## 12. Desktop constraints

- [ ] macOS build runs
- [ ] Linux build runs
- [ ] folder picker works
- [ ] Typst preview works
- [ ] files remain normal `.typ` files editable outside app

## 13. Implementation phases

## Phase 0 — repo setup

Goal: empty Flutter app named TyLog running on desktop/mobile.

Checklist:
- [x] create Flutter app `tylog`
- [ ] commit clean generated baseline
- [x] set app name TyLog
- [x] add minimal lint config
- [x] run default tests
- [x] run on macOS or Linux
- [x] run on Android emulator/device

Done when:
- [x] `flutter test` passes
- [x] app opens with title TyLog

Skip:
- custom architecture folders
- theme system
- CI

## Phase 1 — local vault creation

Goal: TyLog can create/open local vault and create today note.

Checklist:
- [x] implement vault path setting
- [x] create default vault structure
- [x] write `.tylog/settings.json`
- [x] write `.tylog/tylog.typ`
- [x] create `journal/YYYY-MM-DD.typ`
- [x] list journal files
- [x] open today note

Done when:
- [ ] deleting app and reopening existing vault still finds notes
- [ ] created files are readable in external editor

## Phase 2 — plain editor

Goal: edit and save Typst source.

Checklist:
- [x] load note text
- [x] edit note text
- [x] save note text
- [x] show dirty state
- [x] show save error
- [x] preserve unsaved text on failed save
- [x] add smallest save test around file service

Done when:
- [x] type text, save, close app, reopen, text remains

Skip:
- syntax highlighting
- autosave until manual save is boringly reliable

## Phase 3 — scanner and index

Goal: build links/backlinks from files.

Checklist:
- [x] implement note scanner
- [x] implement vault scan
- [x] write `.tylog/index.json`
- [x] load index on startup
- [x] rebuild index button
- [x] update one note in index after save
- [x] tests for links/backlinks

Done when:
- [ ] note A links to note B
- [ ] note B shows A as backlink
- [ ] deleting index and rebuilding restores same backlinks

## Phase 4 — navigation and page creation

Goal: links become useful.

Checklist:
- [x] tap outgoing link opens existing note
- [x] unresolved link can create page
- [x] page files go under `pages/`
- [ ] duplicate title behavior is deterministic
- [x] recent notes list updates

Done when:
- [ ] from today's journal, create/open `PKM.typ` through wikilink flow

## Phase 5 — Typst preview

Goal: current note can render.

Checklist:
- [x] add `typst_flutter`
- [x] render note preview
- [x] display compile error
- [x] source/preview toggle
- [x] verify Android
- [ ] verify desktop

Done when:
- [x] valid Typst note renders
- [x] invalid Typst note shows error without losing editor text

## Phase 6 — graph

Goal: graph gives useful map of notes.

Checklist:
- [x] build graph model from index
- [x] draw nodes/edges with CustomPainter
- [x] circular or simple deterministic layout
- [x] tap node opens note
- [x] highlight current note

Done when:
- [ ] 5 linked notes show visible graph and navigation works

Skip:
- force physics
- clustering
- minimap
- graph package unless CustomPainter fails

## Phase 7 — Android/desktop hardening

Goal: real device sanity.

Checklist:
- [x] test app-owned vault on Android
- [ ] test folder selection on Android
- [x] test macOS folder vault
- [ ] test Linux folder vault if available
- [x] test non-ASCII filenames
- [x] test spaces in filenames
- [x] test 100 notes scan time
- [x] test external edit then rebuild index

Done when:
- [x] one Android + one desktop workflow is stable

## Phase 8 — Nextcloud workflow doc

Goal: user can sync without TyLog owning sync yet.

Checklist:
- [x] document desktop Nextcloud folder workflow
- [x] document Android tested workflow or limitation
- [x] document conflict behavior
- [x] document what files are safe to delete/regenerate

Done when:
- [x] same vault can be edited on desktop and Android through synced folder or clear manual workaround

## Phase 9 — MVP cut

Goal: usable first release.

Checklist:
- [x] create sample vault
- [x] run full smoke test
- [x] ensure no test notes in app data
- [x] update README
- [x] tag MVP build — `v1.0.0+6`

Manual smoke test:
- [x] create vault
- [x] open today
- [x] type text
- [x] add `#wikilink("PKM")`
- [x] save
- [x] create PKM page from link
- [x] go back to today
- [x] open PKM backlinks, see today
- [x] open graph, see both notes and edge
- [x] render preview
- [x] close/reopen app, data remains
- [x] delete `.tylog/index.json`, rebuild, backlinks return

## 14. Minimal code structure

Start with few files. Split only when files get annoying.

```text
lib/
  main.dart
  vault.dart          # file operations + vault layout
  scanner.dart        # note scanner + backlinks
  models.dart         # small data classes
  screens.dart        # UI screens until it becomes too large
```

Split later if needed:

```text
lib/screens/
lib/widgets/
lib/services/
```

Ponytail: no feature-folder architecture before there are enough features to organize.

## 15. Core data models draft

```dart
class NoteRef {
  final String path;
  final String title;
  final String? date;
  final List<String> tags;
  final List<String> aliases;
  final List<String> outgoingLinks;
}

class VaultIndex {
  final Map<String, NoteRef> notesByPath;
  final Map<String, List<String>> backlinksByTarget;
}
```

Keep paths vault-relative in app state.

## 16. Risk register

### Risk: Android folder access is painful

Status: [ ] untested

Mitigation:
- app-owned vault first
- document Nextcloud workaround
- add direct WebDAV only if required

### Risk: `typst_flutter` fails on a target

Status: [ ] untested

Mitigation:
- source editor/index/backlinks still useful
- preview can be marked experimental
- no architecture depends on preview

### Risk: regex scanner misses complex Typst

Status: [ ] accepted for MVP

Mitigation:
- document simple supported syntax
- upgrade to Typst metadata query when needed

### Risk: file conflicts from Nextcloud

Status: [ ] accepted for MVP

Mitigation:
- one note per file reduces conflicts
- never auto-delete conflict files
- later conflict viewer if needed

### Risk: graph becomes slow

Status: [ ] accepted for MVP

Mitigation:
- test 100 notes
- add filtering/layout package only after real slowdown

## 17. Decisions log

- [x] App name: TyLog
- [x] Primary framework: Flutter
- [x] Primary format: Typst `.typ`
- [x] Source of truth: plain files
- [x] One giant live file: rejected
- [x] Database as source of truth: rejected for MVP
- [x] Sync strategy MVP: external Nextcloud/filesystem sync
- [x] First graph: simple derived graph
- [x] First editor: plain source editor
- [ ] Direct WebDAV sync: later decision
- [ ] Git sync: later decision
- [ ] Syntax highlighting: later decision

## 18. Open questions

Answer only when they block implementation.

- [ ] Should default vault live in app documents or user-selected folder?
- [ ] On Android, which Nextcloud sync path is actually usable?
- [ ] Should journal note title be `YYYY-MM-DD` or localized human date?
- [ ] Should page filenames preserve spaces or use slug names?
- [ ] Should tags be only `#tag("x")` or also parsed from plain `#x` text?

Default answers until proven wrong:
- app documents default vault
- `YYYY-MM-DD` journal title
- preserve spaces in filenames, sanitize only path separators
- only parse explicit `#tag("x")` first

## 19. Fast-win backlog

### #20 — `<>` raw/preview loop

Goal: one obvious editor control for source/preview without a new editor model.

Checklist:
- [ ] Replace separate Source + Preview desktop actions with one `<>` action cycling `journal -> preview -> source -> journal`.
- [ ] Keep Graph as separate mode; graph is navigation, not editor loop.
- [ ] In preview mode, show current note source in the editor area until inline preview is actually cheap; current line raw+styled preview is deferred.
- [ ] Add one widget test that taps `<>` and verifies source/preview/source loop.

Done when:
- [ ] Phone and desktop expose the same `<>` loop affordance.
- [ ] `flutter test` passes.

Skipped for fast win: per-line mixed raw+render preview. Add when the simple mode loop is useful and line mapping is worth the complexity.

### #21 — New note/page

Goal: create a non-journal page directly.

Checklist:
- [ ] Add `New page` button in the pages panel/FAB menu.
- [ ] Prompt for title with a plain `AlertDialog` + `TextField`.
- [ ] Reuse `Vault.page(title)` and `_openNote(file)`; no new note type.
- [ ] Rebuild index after create and show created path in status.
- [ ] Add one vault/widget check for direct page creation path.

Done when:
- [ ] User can create `pages/Title.typ` without writing a wikilink first.
- [ ] Duplicate existing title opens existing page, does not overwrite content.
- [ ] `flutter test` passes.

Skipped for fast win: templates, note/page taxonomy, folder picker. Add when direct pages are used enough to need choices.

## 20. Build order snapshot

Current progress:

- [x] Phase 0 — repo setup
- [x] Phase 1 — local vault creation
- [x] Phase 2 — plain editor
- [x] Phase 3 — scanner and index
- [x] Phase 4 — navigation and page creation
- [x] Phase 5 — Typst preview
- [x] Phase 6 — graph
- [x] Phase 7 — Android/desktop hardening
- [x] Phase 8 — Nextcloud workflow doc
- [x] Phase 9 — MVP cut

Next action:
- [x] release MVP `v1.0.0+6`
- [ ] collect real-device feedback before adding more features

## 21. PKMS v2 schema contract (issue #28)

This is the canonical contract for PKMS work tracked by #22.

### 21.1 Note metadata

Required:
- `id` (stable string id, unique in vault)
- `title` (human readable)
- `tags` (list of canonical tag slugs)
- `links` (list of note targets by id/alias/title token)

Optional:
- `aliases` (list of alternate lookup strings)
- `files` (list of file registry ids)

Example:

```typst
#note(
  id: "20260703-pkms-schema",
  title: "PKMS schema contract",
  tags: ("pkms", "architecture"),
  aliases: ("pkms-contract",),
  links: ("20260703-link-resolution",),
  files: ("typst-docs-ref",),
)
```

### 21.2 File registry metadata

Required:
- `id` (stable key)
- `path` (vault-relative file path)
- `kind` (file kind, e.g. `pdf`, `image`, `audio`)
- `status` (lifecycle, e.g. `raw`, `reference`, `archived`)
- `tags` (list of canonical tag slugs)

Optional:
- `notes` (list of note ids that reference this file)

Example:

```yaml
files:
  typst-docs-ref:
    path: assets/references/typst-reference.pdf
    kind: pdf
    status: reference
    tags: [pkms, typst]
    notes: [20260703-pkms-schema]
```

### 21.3 Tag registry metadata

Required:
- `slug` (canonical tag key)
- `title` (display name)
- `type` (classification: `topic`, `status`, `project`, `file-kind`)

Optional:
- `aliases` (alternate forms)

Example:

```yaml
tags:
  pkms:
    title: PKMS
    type: topic
    aliases: [knowledge-system]
```

### 21.4 Link resolution order

Resolution order (first match wins):
1. exact note `id`
2. exact note alias
3. exact note title
4. exact filename stem
5. unresolved

Examples:
- `#wikilink("20260703-pkms-schema")` -> resolves by exact id.
- `#wikilink("pkms-contract")` -> resolves by alias to `20260703-pkms-schema`.
- `#wikilink("Overview")` where multiple notes share title -> unresolved as ambiguous, no implicit pick.

## 22. PKMS smoke/release gate (issue #32)

Release gate is pass/fail, not "looks fine":

1. Create/open a root note with `id`, `tags`, `links`, and `files`.
2. Resolve link to child note by id/alias path.
3. Rebuild index twice; resulting `.tylog/index.json` must be deterministic.
4. Backlink map must include `child <- root`.
5. Validator summary must report counts for unknown tags, duplicate aliases, missing files.

Current measurable threshold:
- Scale sanity: rebuild on 160 generated notes within 5 seconds in test environment.
- Determinism: two consecutive rebuilds must produce byte-identical `index.json`.

## 23. Android two-way sync contract (issue #24 / #23)

Near-realtime means "open-app near-realtime", not CRDT live editing.

Sync triggers:
- app startup
- app resume
- manual Sync button
- local-save debounce
- open-app polling (conservative interval)

Per-file decision states:
- `upload` (local changed, remote not changed/missing)
- `download` (remote changed, local not changed/missing)
- `conflict` (both changed since last cursor)
- `skip` (no relevant changes)

Safety rules:
- no silent overwrite on both-changed: store remote conflict copy locally.
- keep plain files as source of truth.
- keep sync cursor in `.tylog/sync_state.json` and diagnostics in `.tylog/sync_trace.jsonl`.
