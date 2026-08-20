# TyLog feature inventory (v0.3.0+92, 2026-08-20)

Ground truth for the PKMS competitive audit (`docs/audit-pkms-comparison.md`).
Gathered by codebase exploration over `lib/`, `packages/`, `docs/`, `spec/`.
TyLog is a deliberately scoped Typst-first workspace prioritizing local-first
data ownership, plaintext storage, and depth over breadth.

## Note model

| Feature | Description | Where | Maturity |
|---|---|---|---|
| Typst file storage | Notes are .typ files with valid Typst syntax | daily/, notes/, projects/, articles/ | Shipped |
| Note kinds | note, daily, project, article, research; extensible (person, place, organization) | spec/tylog-format-v1.md, scanner.dart | Shipped |
| Tags | Freeform tags + synonym normalization (_system/tag-synonyms.json) | packages/tylog_core/src/scanner.dart | Shipped |
| Aliases | Alternative display names | NoteRef.aliases | Shipped |
| Properties | Custom key-value metadata | NoteRef.properties, property_select_chip.dart | Shipped |
| Daily/journal notes | daily/YYYY/MM/YYYY-MM-DD.typ | journal_feed.dart, month_calendar.dart | Shipped |
| Note dates, project refs | Temporal + project context fields | NoteRef.date, NoteRef.project | Shipped |

## Editor

| Feature | Description | Where | Maturity |
|---|---|---|---|
| Block-level editing | Edit individual blocks without full source | controlled_editor.dart, TyLogReadView | Shipped |
| Preview/Source/Split | Three editor modes | editor_panel.dart, work_surface.dart | Shipped |
| Magic (/) actions | 20+ quick-insert commands | app_mobile.dart applyMagic(), MagicAction | Shipped |
| Rich formatting | Bold/italic/strike/underline/mono/highlight (4 colors) via Typst | app_mobile.dart | Shipped |
| Headings, tables, equations | Via magic menu; LaTeX-style math | MagicAction.* | Shipped |
| Wikilinks + autocomplete | [[Note\|Display]] → #tylog.ref-note(); note/project/person suggestions | editor_autocomplete.dart | Shipped |
| Autosave + history | Atomic per-note saves; 100-entry session undo/redo | controlled_editor.dart | Shipped |
| Citations | From _system/bibliography.yml (BibTeX/BibLaTeX) | bibliography.dart | Shipped |
| Attachments, reports | File/image refs; filtered note reports (date/status/tag/kind) | MagicAction.attachment, report.dart | Shipped |
| ABSENT: markdown storage, arbitrary WYSIWYG, vault-level undo | Intentional (bulk changes snapshot to .tylog/undo/) | — | N/A |

## Tasks

| Feature | Description | Where | Maturity |
|---|---|---|---|
| Statuses, priorities | todo/doing/done/cancelled; low/normal/high/urgent | TaskRef, scanner.dart | Shipped |
| Due + scheduled dates | ISO 8601, separate fields | TaskRef.due/.scheduled | Shipped |
| Reminders | Local notifications | task_scheduler.dart | Shipped |
| Recurrence | RRULE via rrule package | TaskRef.recurrence | Shipped |
| Time tracking | Clocked sessions with runaway filtering | TaskRef.clocked, ClockEntry | Shipped |
| Tags, project, assignees, dependencies, completion history, custom properties | Full task data model | TaskRef | Shipped |
| Task views | Library > Tasks, Today agenda, status/priority filters | work_surface.dart | Shipped |

## Knowledge graph / linking

| Feature | Description | Where | Maturity |
|---|---|---|---|
| Backlinks + forward links | Reverse link index; outgoing per note | VaultIndex.backlinksByTarget, linked_references.dart | Shipped |
| Five graph modes | Concept map, Focused (1-hop), All files (LOD), Timeline, Voronoi treemap | graph.dart, voronoi_view.dart | Shipped |
| Community detection | Louvain-like clustering | computeCommunities | Shipped |
| Edge types | link/citation/tag/read with toggles | GraphEdgeKind | Shipped |
| Auto-related sections | LLM-generated or title/tag/citation-matched ("Relink vault") | app_mobile.dart stripAutoRelated() | Shipped |
| ABSENT: block refs/transclusion | Note-level references only, by design | — | N/A |

## Search & indexing

| Feature | Description | Where | Maturity |
|---|---|---|---|
| Full-text search | Tokenized, gzipped JSON index (_index/search-index.json.gz) | search_index.dart | Shipped |
| Worker-isolate indexing | Background indexing off the UI isolate | vault_worker.dart | Shipped |
| Saved searches | Named presets with tag/status filters | saved_searches.dart | Shipped |
| Search filters | kind/tags/status/date/article-status | knowledge_screen.dart | Shipped |
| Fallback parser + validation | Safe parse when Typst fails; problem reporting | scanner.dart, validation.dart | Shipped |
| ABSENT: query language | No {{query}}/datalog/SQL; saved searches + report blocks instead | — | N/A |

## Sync

| Feature | Description | Where | Maturity |
|---|---|---|---|
| Nextcloud WebDAV sync | Polling, conditional transfers, SHA-256 change detection | nextcloud_sync.dart, path_sync.dart | Shipped |
| Conflict resolution | Manual: text edit, binary choice, delete-vs-edit; snapshots; pending conflict suspends auto-sync | nextcloud_sync/conflicts.dart | Shipped |
| ETag safety, atomic writes | Never overwrite on remote change; temp/flush/rename | nextcloud_sync.dart, vault_storage.dart | Shipped |
| Sync dashboard | Diagnostics, transfer totals | sync_dashboard.dart | Shipped |
| Android SAF | Persistent folder access | vault_registry.dart | Shipped |
| ABSENT: 3-way merge, E2EE sync, version history, multi-user | Manual resolution; plaintext over HTTPS | — | N/A |

## Import / export

| Feature | Description | Where | Maturity |
|---|---|---|---|
| Logseq + Obsidian vault import | Auto-detect; pages→notes, journals→daily, TODO→tasks, wikilinks, assets, import report | vault_import_flow.dart, tylog_import_core | Shipped |
| Logseq DB (2.0) import | Via EDN export, transpile to file pipeline | docs/superpowers/plans/2026-08-20-logseq-db-import.md | Planned |
| Markdown article import | Single articles | markdown_article_import.dart | Shipped |
| PDF export | Any note/report via typst compile; .typ + .pdf siblings in outputs/ | report.dart | Shipped |
| Bibliography | BibTeX/BibLaTeX | bibliography.dart | Shipped |
| ABSENT: HTML export | PDF only | — | N/A |

## Library / articles

| Feature | Description | Where | Maturity |
|---|---|---|---|
| Article pipeline | Status stages unread→skimmed→read→extracted→cited; ratings; reading log to daily notes | vault.dart, app_mobile.dart _logReading | Shipped |
| Reading mode | Adjustable typography, night mode (per-device prefs) | reading_mode.dart | Shipped |
| External LLM producer | article-pipeline repo writes Typst articles into the vault | docs/tylog-ecosystem.md | Shipped (external) |
| ABSENT: Zotero integration | Static .yml only | — | N/A |

## Calendar

Month grid with journal/task markers, date references as calendar entries, task dues, recurring tasks, native date picker (calendar_tab.dart, month_calendar.dart, VaultIndex.calendar). Shipped.

## Platforms & storage

Android (release-grade, real-vault tested on Huawei P30), macOS (release, auto-updater), iOS host for dev, Linux CI-only. Multi-vault, SAF, plaintext storage by design; age-encrypted backup designed (docs/age-encrypted-backup.md); background sync service (WorkManager). ABSENT: in-app encryption, E2EE.

## PDF / typesetting (TyLog's unique axis)

Typst-native notes compile directly to typeset PDF; reproducible reports (.typ + .pdf); themable (_system/theme.typ, export.typ); native math; bibliography/citations. No markdown app matches this without export toolchains.

## Extensibility

Custom properties and note kinds only. ABSENT by choice: plugin API, query blocks, flashcards/SRS, whiteboards, kanban, real-time collaboration, in-app AI/RAG.

## Notable Logseq features TyLog lacks (for the audit's gap list)

Block refs/{{embed}}, plugin ecosystem, query language, SRS/flashcards, whiteboards, kanban, RTC/multi-user, sharing/permissions, version history, 3-way merge, encrypted sync, HTML publish, favorites/pins, recycle-bin UI, PDF annotation.
