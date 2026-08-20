# Logseq 2.0 "DB version" — feature-surface competitive audit (as of Aug 2026)

Scope: what changed in the **feature surface** of Logseq's new database-backed
product vs. the classic file-based product ("Logseq OG"), for a competitive
audit against TyLog. Desktop beta **2.0.1** shipped 2026-07-13; this document
reflects the state of `logseq/logseq` master and the `2.0.1` tag as researched
2026-08-20.

Method: primary sources only — the `logseq/logseq` GitHub repo (master +
`2.0.1` tag), its `docs/` tree and ADRs, the sibling `logseq/docs` repo
(`db-version.md`, `db-version-changes.md`, `og_import_graph_cases.md`), the
`logseq/db-test` and `logseq/marketplace` repos, GitHub Releases, and official
posts on logseq.io and discuss.logseq.com. Community forum/Reddit claims are
explicitly labeled **COMMUNITY SENTIMENT** with an attributed source; nothing
here is invented or inferred without a cited basis.

Storage internals (SQLite `kvs` schema, transit encoding, EDN export, schema
version 65.33, datascript fork) are **not** re-derived here — see the sibling
doc: [`docs/research-logseq-db-format.md`](./research-logseq-db-format.md).
Facts from that doc are linked, not re-researched.

## TL;DR

- Logseq forked itself in mid-2026: the markdown/file product is now **Logseq
  OG** (its own repo, `github.com/logseq/og`, security-fixes-only going
  forward), and "Logseq" now means the SQLite/datascript **DB version**, which
  is where all new feature work happens
  ([split announcement](https://logseq.io/p/e3YDyX5AYr)).
- The DB version unifies pages and blocks into "nodes," makes properties and
  tags first-class typed entities, and replaces TODO/DOING text markers and
  `{{query}}` macros with a Task class and a visual query/view builder —
  a genuine data-model upgrade, not just a storage swap
  ([docs/db-version.md](https://github.com/logseq/docs/blob/master/db-version.md)).
- Two headline features were **cut** at 2.0.1: whiteboards (removed outright,
  "hopefully" a future plugin) and, in effect, native canvas/Excalidraw
  ([db-version-changes.md](https://github.com/logseq/docs/blob/master/db-version-changes.md)).
  Flashcards were reimplemented (old SRS data not imported) and PDF annotation
  changed shape; both still have open bugs as of Aug 2026
  ([db-test issues](https://github.com/logseq/db-test/issues)).
- Sync is being rebuilt as real-time collaboration (RTC) with a dedicated
  `client-ops-db.sqlite` and optional-but-default E2EE
  ([ADR 0003](https://github.com/logseq/logseq/blob/master/docs/adr/0003-optional-sync-graph-encryption.md)),
  and is still beta/invite-gated for RTC as of Aug 2026 (community reports).
- The team's direct answer to the plaintext-lock-in complaint, shipped
  2026-05/06, is the **Markdown Mirror**: a one-way, Electron-only, debounced
  markdown projection of the DB graph onto disk, explicitly *not* a full
  export and *not* editable externally
  ([ADR 0016](https://github.com/logseq/logseq/blob/master/docs/adr/0016-markdown-mirror.md)).
- Plugin API and marketplace compatibility for DB graphs are real but
  immature: a `supportsDB`/`supportsDBOnly` manifest flag exists in the
  marketplace repo, but multiple plugin-API calls have open bugs in
  `db-test` as of Aug 2026.
- Only **one** 2.0.x release exists on GitHub Releases as of 2026-08-20 —
  `2.0.1` (2026-07-13) — with a `nightly` unstable channel (latest
  `20260819`) carrying ongoing DB-version work; there is no 2.0.2 yet.

---

## 1. Note model (nodes, typed properties, classes/tags, closed values)

The storage-level model (everything is a `:block/uuid` "node"; properties as
first-class `:logseq.class/Property` entities; classes via
`:logseq.class/Tag` + `:logseq.property.class/extends`) is covered in the
sibling doc's [§5](./research-logseq-db-format.md#5-db-data-model-vs-file-based-logseq-what-an-importer-must-map)
— reference that for the datascript-level facts.

User-facing additions not in the storage doc:

- "A node is a new term for a page or block because the two now behave
  similarly" — blocks can become pages by adding the `#Page` tag, and pages
  are disambiguated by tag rather than forced-unique names (e.g. "Apple
  #Company" and "Apple #Fruit" can coexist)
  ([docs/db-version.md](https://github.com/logseq/docs/blob/master/db-version.md)).
- Property schema editing is in-app: six user-facing property types (Text,
  Number, Date, DateTime, Checkbox, URL — plus Node/ref and Asset per the
  storage-doc's `:logseq.property/type` enum), each configurable with a
  default value and a **choices** list — this is the closed-values UX: a
  property can be restricted to a picker of pre-defined values, surfaced as
  chips/dropdown rather than free text
  ([docs/db-version.md](https://github.com/logseq/docs/blob/master/db-version.md)).
- Tags carry **Tag Properties** that every tagged node inherits ("Tags can
  have Tag Properties which are properties that all nodes inherit from a
  tag"), i.e. class-level default schema; tags support multiple parents via
  an "Extends" property and bidirectional properties
  ([docs/db-version.md](https://github.com/logseq/docs/blob/master/db-version.md)).
- Page-level properties are now set by editing the page **title** block
  rather than the first block of the page; block properties are edited
  inline in block content
  ([db-version-changes.md](https://github.com/logseq/docs/blob/master/db-version-changes.md)).

## 2. Editor (property UI, tag-as-class UX, tables/views)

- Inline tagging changed interaction: typing `#` and pressing Enter now opens
  "a powerful tags feature" (tag creation/search modal) instead of instantly
  inserting a tag; inline tag *entry* now requires `Cmd-Enter`, and tags
  render to the block's right rather than inline
  ([db-version-changes.md](https://github.com/logseq/docs/blob/master/db-version-changes.md)).
- Tables were rebuilt on shadcn (a React/Radix component set) with inline
  spreadsheet-style cell editing, replacing the old markdown-table rendering
  ([db-version-changes.md](https://github.com/logseq/docs/blob/master/db-version-changes.md)).
- `/` slash commands were consolidated — "Advanced Commands" merged into the
  standard command list — and markdown syntax is no longer shown/editable as
  raw text in the block (e.g. heading level is set via a right-click menu, not
  by typing `#`s)
  ([db-version-changes.md](https://github.com/logseq/docs/blob/master/db-version-changes.md)).
- New **Views** mechanism sits over any tag/class collection with three
  layouts — Table, List, Gallery (community FAQ additionally lists Kanban and
  Calendar view types; only Table/List/Gallery are documented in the primary
  `db-version.md`) — each with filter/sort/group and bulk multi-select
  actions (retag, bulk property edit, bulk delete)
  ([docs/db-version.md](https://github.com/logseq/docs/blob/master/db-version.md)).
- Templates are now created via a `#Template` tag rather than a
  property-based marker
  ([db-version-changes.md](https://github.com/logseq/docs/blob/master/db-version-changes.md)).
- Org-mode file format support was dropped outright ("Org mode files are no
  longer supported") and the built-in Zotero integration was removed
  ([db-version-changes.md](https://github.com/logseq/docs/blob/master/db-version-changes.md)).

## 3. References (block refs, embeds)

- References are unified: both page and block references use `[[ ]]` syntax
  now; the old block-embed parenthetical syntax `(( ))` is gone, and node
  embedding uses the same `/Node` embed command for both blocks and pages
  ([db-version-changes.md](https://github.com/logseq/docs/blob/master/db-version-changes.md)).
- Namespace references (`[[foo/bar/baz]]`) still work for hierarchical page
  creation, but the created page's **stored name no longer embeds the
  namespace path** — this is presented as a fix (renaming a parent no longer
  cascades and breaks children) but is a real behavioral change from OG,
  where the full path was literally the page name. Namespace structure is now
  edited explicitly via a "Library" page, and the old `{{namespace}}` query
  macro is deprecated in favor of it
  ([db-version-changes.md](https://github.com/logseq/docs/blob/master/db-version-changes.md)).
- At the storage layer, refs resolve through `:block/refs` / entity title per
  [the sibling doc](./research-logseq-db-format.md#5-db-data-model-vs-file-based-logseq-what-an-importer-must-map),
  not raw text pattern matching — this is why old regex-based ref parsing
  from OG can't carry over.

## 4. Tasks & scheduling

Confirmed at the storage layer (Task class, status/priority/scheduled/
deadline as properties, no TODO/DOING text markers) in
[the sibling doc](./research-logseq-db-format.md#5-db-data-model-vs-file-based-logseq-what-an-importer-must-map).
User-facing:

- Tasks are created via commands (`/todo`, etc.) rather than typing marker
  text; "Logbook timestamps have been replaced with Status change history" —
  i.e. task-state transitions are now tracked as structured property history
  rather than a `:LOGBOOK:` text block
  ([db-version-changes.md](https://github.com/logseq/docs/blob/master/db-version-changes.md)).
- **Repeaters exist and are documented in detail**, adapted from org-mode's
  three repeater-cookie semantics, keyed on a new
  `:logseq.property.repeat/repeat-type` property:
  - `.+` — next occurrence = completion date + one interval (habit-style,
    resets from when you actually finished it).
  - `++` — next occurrence = original scheduled date + intervals, advanced
    until it's in the future (keeps a fixed weekday/anchor; this is the
    **default** for tasks without an explicit cookie).
  - `+` — next occurrence = original date + exactly one interval, can stack
    into overdue (fixed-date obligations like rent).
  Implementation lives in `src/main/frontend/worker/commands.cljs`.
  ([docs/recurring-tasks.md](https://github.com/logseq/logseq/blob/master/docs/recurring-tasks.md)).
- The 2026-05-16 team update reports "Task repeater cookies (`.+`, `++`, `+`)
  now behave according to documentation specifications," implying repeaters
  were buggy pre-May-2026 and were stabilized before the 2.0.1 beta cut
  ([discuss.logseq.com, "What's New with Logseq DB — May 16th 2026"](https://discuss.logseq.com/t/whats-new-with-logseq-db-may-16th-2026/35020)).

## 5. Queries

- The `{{query}}` inline macro and old advanced-query block syntax are gone
  as the primary UX. **Simple queries** are now created via a `/Query`
  slash command that opens a visual query builder; the builder writes text
  using internal entity IDs, supports a custom title, and — notably — "runs
  against all nodes instead of forcing the user to choose between blocks or
  pages" (a real semantic upgrade over OG's block-vs-page split)
  ([db-version-changes.md](https://github.com/logseq/docs/blob/master/db-version-changes.md)).
- Filter renames reflect the property model: `(page-tags)` → `(tags)`,
  `(page-property)` → `(property)`, `(priority A)` → `(priority high)`;
  `all-page-tags` and `sort-by` filters are removed (sorting now happens via
  the Table view instead of a query filter)
  ([db-version-changes.md](https://github.com/logseq/docs/blob/master/db-version-changes.md)).
- **Advanced queries** still exist as a feature but are edited as
  syntax-highlighted code blocks and require rewriting against the new
  schema: `:block/marker`→`:logseq.property/status`,
  `:block/priority`→`:logseq.property/priority`,
  `:block/deadline`/`:block/scheduled`→ property equivalents,
  `:block/content`/`:block/original-name`→`:block/title`; `:block/journal?`,
  `:block/left`, `:block/path-refs` are removed attributes; `:title`,
  `:group-by-page?`, `:collapsed?` options are deprecated
  ([db-version-changes.md](https://github.com/logseq/docs/blob/master/db-version-changes.md)).
- The new **Views** mechanism (§2) is effectively "queries as a first-class
  UI object over a tag/class," layered on top of query results with Table/
  List/Gallery rendering and bulk actions
  ([docs/db-version.md](https://github.com/logseq/docs/blob/master/db-version.md)).

## 6. Knowledge graph & backlinks

- Backlink/linked-reference mechanics inherit directly from the unified
  `[[ ]]`-reference model (§3) — no separate primary-source doc describes a
  behavioral change to the backlinks panel itself beyond that unification.
- The graph *visualization* was rebuilt: "Graph View V2 — A complete rebuild
  addressing performance issues... renders faster, scales better, and is
  easier to move around in," plus the ability to zoom into a task node from
  the graph
  ([discuss.logseq.com, "What's New with Logseq DB — May 16th 2026"](https://discuss.logseq.com/t/whats-new-with-logseq-db-may-16th-2026/35020)).
- The public roadmap separately lists "new graph visualization with improved
  performance" as an ongoing roadmap item, consistent with Graph View V2
  being iterative rather than finished
  ([logseq.io public roadmap](https://logseq.io/p/NX4mc_ggEV)).
- No primary source found describing algorithmic changes to backlink
  discovery itself (e.g. ranking, unlinked-reference detection) beyond the
  reference-model unification — absent as of Aug 2026.

## 7. Search & indexing

Per the sibling doc: a per-graph `search-db.sqlite` with an `fts5` trigram
index over `blocks(id, title, page)`, kept live via AFTER INSERT/UPDATE/
DELETE triggers, derived/rebuildable data excluded from backups — see
[§1 "Side tables / side files"](./research-logseq-db-format.md#side-tables--side-files)
of the sibling doc. Not re-derived here.

User-facing addition: the search modal now shows recently-updated pages by
default when opened with no query, and supports creating a new tag directly
from the search modal
([db-version-changes.md](https://github.com/logseq/docs/blob/master/db-version-changes.md)).
The "All Pages" screen was renamed "Pages" and gained a table/list view
toggle ([db-version-changes.md](https://github.com/logseq/docs/blob/master/db-version-changes.md)).

## 8. Sync & collaboration

- The DB version's sync is being rebuilt as **RTC (Real-Time Collaboration)**,
  not the old file-diff sync. Client-side sync state is tracked in a
  dedicated `client-ops-db.sqlite` per graph (see the sibling doc's
  [§1](./research-logseq-db-format.md#side-tables--side-files)), backed by
  ADRs describing a Node.js sync-server adapter
  ([ADR 0001](https://github.com/logseq/logseq/blob/master/docs/adr/0001-nodejs-db-sync-server-adapter.md)),
  a `sync_meta`/`client_ops` split with `(created_at, id)`-ordered pending
  uploads
  ([ADR 0015](https://github.com/logseq/logseq/blob/master/docs/adr/0015-client-ops-and-sync-meta-in-client-sqlite.md)),
  entity-checksum reconciliation, and op-driven client rebase for conflicts
  (`ADR 0006`, `ADR 0010` — titles only, not deep-read here:
  [docs/adr/](https://github.com/logseq/logseq/tree/master/docs/adr)).
- **Encryption**: E2EE is the *default*, but is explicitly made **optional at
  graph-creation time**, and that choice is then immutable for the graph's
  lifetime — "The selected mode is stored as graph metadata and treated as
  immutable for that graph after creation." The stated rationale for allowing
  plaintext sync is self-hosted/trusted-infrastructure use and third-party
  tool integration that needs direct storage access
  ([ADR 0003](https://github.com/logseq/logseq/blob/master/docs/adr/0003-optional-sync-graph-encryption.md)).
  A `:logseq.kv/graph-rtc-e2ee?` graph-level flag records the mode.
- **Self-hosting**: the ADRs and repo confirm a self-hostable sync-server
  adapter exists ([ADR 0001](https://github.com/logseq/logseq/blob/master/docs/adr/0001-nodejs-db-sync-server-adapter.md));
  the official public roadmap separately lists "self-hosted sync" as a
  roadmap line item, and a forum thread specifically about self-hosting sync
  exists
  ([discuss.logseq.com, "Logseq Sync Self-Hosted possibility"](https://discuss.logseq.com/t/logseq-sync-self-hosted-possibility/34114)) —
  the team-vs-community split of that thread was not verified line-by-line
  here, so treat self-hosting maturity claims from it as **COMMUNITY
  SENTIMENT** unless corroborated by the ADR.
- **Status as of Aug 2026**: the official roadmap and the split announcement
  both describe DB-graph sync as beta/rolling-out — the split post says "Logseq
  Sync" for DB graphs is invite-based and encrypts "locally on your device"
  before upload, each device keeping "a local copy of your graph" (local-first
  posture retained)
  ([logseq.io, "Big update: Logseq is splitting into two versions"](https://logseq.io/p/e3YDyX5AYr)).
  The May 2026 team update lists concrete sync reliability fixes shipped —
  "RSA key caching, websocket recovery, and better handling of encrypted
  graphs and multi-device conflicts"
  ([discuss.logseq.com, May 16 2026 update](https://discuss.logseq.com/t/whats-new-with-logseq-db-may-16th-2026/35020)) —
  consistent with sync still being actively stabilized post-2.0.1.
- **Pricing**: no primary-source pricing figure for DB-graph Sync/RTC or the
  mentioned "Logseq Pro" was found on logseq.io or in the repo as of Aug
  2026 — the only concrete numbers found (Backer/Sponsor Open Collective
  tiers) come from third-party pricing-aggregator blogs, not Logseq itself;
  **no primary source found** for current DB-version sync pricing.
- **Multi-user/RTC status**: "Real Time Collaboration (RTC)" is named
  explicitly as a roadmap/beta item alongside the DB version and a new mobile
  app; the primary roadmap doc lists "conflict resolution when multiple
  clients edit same content" and "recycle to restore deleted pages" as
  in-progress, not shipped-and-final, items
  ([logseq.io public roadmap](https://logseq.io/p/NX4mc_ggEV)).

## 9. Import/export

Export mechanics (SQLite copy, zip, EDN `:graph`/`:graph-human`, lossy
markdown export, debug transit, no JSON graph export) are covered in the
sibling doc's [§2](./research-logseq-db-format.md#2-official-export-paths) —
reference that; this section adds fidelity/known-issue detail.

- **File-graph → DB migration ("DB Graph Importer")**: automatically detects
  property types during migration and offers choices for how to handle tags;
  documented limitation — "blocks with multiple code snippets, embeds, or
  quotes only import the first instance"
  ([docs/db-version.md](https://github.com/logseq/docs/blob/master/db-version.md)).
- A dedicated audit doc, `docs/og_import_graph_cases.md`, catalogs
  `logseq/db-test` issues labeled `import` as of June 2026 across seven
  problem categories — block-identity conflicts, forward references (a block
  referencing a target defined in a later-imported file), journal-filename
  legacy references, mixed deadline/scheduled timestamp formats, linked
  external PDFs and missing local assets, and parser edge cases (empty files,
  huge flat blocks, self-referencing blocks) — with 17 regression tests
  covering them
  ([docs/og_import_graph_cases.md](https://github.com/logseq/logseq/blob/master/docs/og_import_graph_cases.md)).
- Concrete import-fidelity bugs open in `db-test` as of Aug 2026: PDF
  annotations on linked (non-asset) PDFs are silently dropped on MD→DB import
  (open, [#923](https://github.com/logseq/db-test/issues/923)); embedded
  asset alt text is lost on file→DB import (open,
  [#1081](https://github.com/logseq/db-test/issues/1081)); pasting large
  markdown content can set an invalid `:block/pre-block?` flag that later
  breaks RTC sync (open,
  [#775](https://github.com/logseq/db-test/issues/775)); EDN import can error
  when importing a tag already created by a page import (open,
  [#958](https://github.com/logseq/db-test/issues/958)).
- **The Markdown Mirror** (new, shipped ~May/June 2026) is the closest thing
  to an "export" that stays live — see §10, since its real purpose is
  answering the lock-in complaint rather than being a data-interchange
  format; ADR 0016 is explicit that it is **not** "a complete database
  export despite including property drawers"
  ([ADR 0016](https://github.com/logseq/logseq/blob/master/docs/adr/0016-markdown-mirror.md)).

## 10. Storage format & data ownership

Source-of-truth facts (`~/logseq/graphs/<name>/db.sqlite`, single-writer lock,
etc.) are in the sibling doc's
[§1](./research-logseq-db-format.md#on-disk-location-and-sqlite-schema) —
not re-derived.

- **COMMUNITY SENTIMENT** (per a WebSearch synthesis of discuss.logseq.com
  threads, attribution to specific individual posters not independently
  re-verified here): users describe the SQLite move as a step away from
  "portable plain-text files," worry the two graph formats (OG vs DB) are
  not interoperable, and characterize even a working export/import path as a
  "soft lock-in" because it requires a deliberate manual step rather than
  being the native format. Treat this framing as forum sentiment, not an
  official Logseq claim.
- **Official response — the split announcement**: the team frames DB graphs
  as still "local-first" — the SQLite file lives "exclusively on your local
  device, just like the file version," and even with Sync enabled, data is
  "encrypted locally on your device" before upload, with each device keeping
  its own local copy
  ([logseq.io, "Big update: Logseq is splitting into two versions"](https://logseq.io/p/e3YDyX5AYr)).
- **Official response — the Markdown Mirror feature (the concrete product
  answer to the plaintext complaint)**: an Electron-only setting that
  renders each page to a `.md` file under `mirror/markdown/{journals,pages}/`
  inside the graph folder, incrementally, "to provide desktop users with
  readable Markdown files inside their graph directory for external tool
  integration, backup, indexing, and inspection outside Logseq itself." It
  is explicitly **one-way**: "Editing files in `mirror/markdown/` does not
  update the graph" — the SQLite DB remains sole source of truth, mirror
  files are debounced/lagging and get overwritten on next edit, ambiguous
  refs are unresolved in the mirrored text, and it is unavailable on
  browser/mobile builds
  ([ADR 0016](https://github.com/logseq/logseq/blob/master/docs/adr/0016-markdown-mirror.md)).
  The roadmap separately still lists "enabling reliable two-way sync with
  Markdown files" and "treating each Markdown file as a single block in the
  database" as *future*, unshipped exploration
  ([logseq.io split announcement](https://logseq.io/p/e3YDyX5AYr)).
  The team's own May 2026 update lists "Two-way markdown mirror editing" as
  still "Coming Soon," i.e. not shipped as of 2.0.1
  ([discuss.logseq.com, May 16 2026 update](https://discuss.logseq.com/t/whats-new-with-logseq-db-may-16th-2026/35020)).
  There is also at least one open regression on the mirror itself:
  "Failed to regenerate Markdown Mirror: Error: Maximum call stack size
  exceeded" (closed after fix,
  [db-test #978](https://github.com/logseq/db-test/issues/978)), evidence
  the feature is young and was actively being hardened around the 2.0.1 cut.
- **Synthesis** (mine, not sourced to one document): the practical honest
  answer to "do I still own my files" is: no, not natively — SQLite is the
  live source of truth and the file version is now a second, frozen product
  (Logseq OG) — but Logseq shipped a concrete (if one-way, desktop-only,
  lossy-on-ambiguous-refs) mitigation within months of the 2.0 beta, which is
  more than a purely rhetorical response to the controversy.

## 11. Plugins/extensibility

- **Plugin API status**: exists and is actively used for DB graphs via the
  `@logseq/libs` SDK (npm, "0.2.\* SDK for plugin development," version
  0.2.11 cited by a forum responder) plus a parallel CLJS SDK
  ([docs/db-version.md](https://github.com/logseq/docs/blob/master/db-version.md);
  forum thread [discuss.logseq.com, "Logseq DB plugins"](https://discuss.logseq.com/t/logseq-db-plugins/34717) —
  responder's staff status not confirmed, treat the SDK-version claim as
  corroborated by npm but the framing/tone as community).
- **Marketplace compatibility mechanism**: the `logseq/marketplace` package
  manifest format has explicit boolean flags `supportsDB` and
  `supportsDBOnly` ("Whether the plugin supports database graph" /
  "Whether the plugin only supports database graph," both default `false`)
  ([logseq/marketplace README](https://github.com/logseq/marketplace/blob/master/README.md)) —
  i.e. DB-graph support is opt-in per plugin, not automatic, and most of the
  marketplace's several-hundred plugins were written for the file version and
  are not DB-compatible by default. `db-version.md` claims "Over 65 plugins
  support DB graphs" as of its April 2026 snapshot
  ([docs/db-version.md](https://github.com/logseq/docs/blob/master/db-version.md)) —
  a small fraction of the marketplace catalog.
- **"Famously incomplete at beta"**: confirmed by open `db-test` issues
  specifically in the plugin surface as of Aug 2026: `addPropertyValueChoices`
  "silently fails: worker-side assert requires cljs uuids that JS callers
  cannot supply" (open,
  [#1032](https://github.com/logseq/db-test/issues/1032)); `appendBlockInPage`
  cannot add properties and `upsertBlockProperty` is "limited to
  plugin-defined string properties" (open,
  [#294](https://github.com/logseq/db-test/issues/294)); the `name` option in
  `logseq.Editor.upsertProperty` not working (open,
  [#987](https://github.com/logseq/db-test/issues/987)); HTTP-API property
  writes landing under the wrong namespace vs. documented
  `:plugin.property._api` (open,
  [#1051](https://github.com/logseq/db-test/issues/1051)); custom block
  renderers, improved plugin discovery (search by description), and plugin
  thumbnail icons were only added in the May 2026 update, i.e. post-beta
  polish, not day-one
  ([discuss.logseq.com, May 16 2026 update](https://discuss.logseq.com/t/whats-new-with-logseq-db-may-16th-2026/35020)).
  For security, "only plugins configured with no 'effect' are usable" for
  web-accessible plugins
  ([db-version-changes.md](https://github.com/logseq/docs/blob/master/db-version-changes.md)).
- **CLI/MCP as new extensibility surface**: per the sibling doc, a new
  private OCaml/Melange `cli/` (binary `logseq`) ships `mcp-server` and
  `skill show` subcommands, i.e. Logseq is positioning a local CLI + MCP
  server as first-class extensibility alongside (eventually replacing) the
  JS/CLJS in-app plugin API — see
  [sibling doc §3](./research-logseq-db-format.md#3-reading-a-db-graph-outside-logseq).
  `db-version.md` corroborates an MCP server offering "batch creates/edits,
  search, tag/property/page management, and validation"
  ([docs/db-version.md](https://github.com/logseq/docs/blob/master/db-version.md)).

## 12. Whiteboards, flashcards/SRS, PDF annotation

The row most likely to have real gaps — confirmed:

- **Whiteboards: removed.** "Whiteboards have been removed as a feature and
  will hopefully be available as a plugin"; the built-in `/draw` command is
  similarly gone, "hopefully" to become a plugin. This applies to DB graphs;
  whiteboards still function in the frozen Logseq OG/markdown product
  ([db-version-changes.md](https://github.com/logseq/docs/blob/master/db-version-changes.md)).
  A built-in `Whiteboard` class name still exists in the datascript schema
  per the sibling doc's class list, but the feature/UI built on it is absent
  in the DB version as shipped.
- **Flashcards: reimplemented, not migrated, still buggy.** "Flashcard
  reimplementation: new algorithm incompatible with previous versions; no
  property/SRS data imported" from OG graphs
  ([db-version-changes.md](https://github.com/logseq/docs/blob/master/db-version-changes.md)).
  `db-version.md` describes Cards as a tag-driven system using a spaced-
  repetition algorithm ([docs/db-version.md](https://github.com/logseq/docs/blob/master/db-version.md)).
  Multiple flashcard bugs remain open in `db-test` as of Aug 2026: deleting a
  `#card` tag while viewing the flashcard crashes Logseq (open,
  [#1088](https://github.com/logseq/db-test/issues/1088)); unable to filter
  flashcards to review (open,
  [#495](https://github.com/logseq/db-test/issues/495)); adding a "State"
  property to a non-node-typed tag "breaks flashcards and sends answering
  into a loop" (open,
  [#524](https://github.com/logseq/db-test/issues/524)). Separately, a
  pre-DB-version issue on the main repo records that the file-version SRS
  algorithm was acknowledged faulty and the team's fix path was to correct it
  only in the DB version rather than backport
  ([logseq/logseq #8890](https://github.com/logseq/logseq/issues/8890)).
- **PDF annotation: changed shape, partially working, import-lossy.**
  Annotations are now tagged entities ("annotation tags") displayed by
  default beneath the asset block rather than requiring a separate PDF-viewer
  view, "allow[ing] annotations to be viewed across pdfs and to have custom
  views" ([db-version-changes.md](https://github.com/logseq/docs/blob/master/db-version-changes.md)).
  Import fidelity is a known weak point: annotations on linked (non-asset)
  PDFs are silently dropped on MD-graph import (open,
  [db-test #923](https://github.com/logseq/db-test/issues/923)); importing a
  legacy graph with PDF annotations could previously fail outright with
  "Cannot store nil as a value" (closed/fixed,
  [db-test #1008](https://github.com/logseq/db-test/issues/1008)); "PDF
  Highlights not working correctly" and "PDF highlighting not working
  anymore" were both filed and since closed
  ([db-test #650](https://github.com/logseq/db-test/issues/650),
  [#529](https://github.com/logseq/db-test/issues/529)) — i.e. PDF
  annotation round-tripped through multiple broken states before
  stabilizing, and cross-graph-type import remains lossy as of Aug 2026.

## 13. Calendar/journals

Storage facts (journal pages tagged `:logseq.class/Journal`,
`:block/journal-day` as integer `yyyyMMdd`) are in the sibling doc's
[§5](./research-logseq-db-format.md#5-db-data-model-vs-file-based-logseq-what-an-importer-must-map).
UX additions:

- Journal pages are created automatically and accept natural-language date
  input for navigation/creation ("Today," "Next Friday")
  ([docs/db-version.md](https://github.com/logseq/docs/blob/master/db-version.md)).
- No primary source describes a changed calendar-grid UI for DB graphs beyond
  this; `db-version-changes.md` explicitly notes "No specific changes
  detailed beyond unified node system" for journals in its diff-from-OG
  framing.

## 14. Platforms

- **Desktop**: Electron, current shipping beta channel is `2.0.1`
  (2026-07-13); a rolling `nightly` build channel also exists (latest tag
  `20260819`, per GitHub Releases) for pre-release DB-version work
  ([github.com/logseq/logseq/releases](https://github.com/logseq/logseq/releases)).
- **Web app**: browser/WebView builds run on SQLite WASM over OPFS (per the
  sibling doc's [§1](./research-logseq-db-format.md#on-disk-location-and-sqlite-schema)),
  confirmed as a currently-live storage platform (`browser.cljs`), not a
  future plan.
- **Mobile — DB-graph support is pending/partial, not fully shipped**:
  - iOS: an **invite-only** native app exists with a mobile-first five-tab
    UI (Home, Graphs, Capture, Go To, Search), voice capture, and
    external-app share integration
    ([docs/db-version.md](https://github.com/logseq/docs/blob/master/db-version.md)).
  - Android: "New native implementation under development. Alpha testing not
    yet opened" as of the doc's snapshot
    ([docs/db-version.md](https://github.com/logseq/docs/blob/master/db-version.md)).
  - The public roadmap corroborates this is still in motion: "Android native
    experience" is an assigned, in-progress roadmap item, and general "Native
    mobile apps" are listed as a future goal rather than done
    ([logseq.io public roadmap](https://logseq.io/p/NX4mc_ggEV)).
  - `docs/db-version.md` itself notes mobile apps "lack complete desktop
    feature parity" as a known limitation.
  - Net: as of Aug 2026, DB-graph mobile access is real but explicitly
    beta/invite-gated (iOS) or pre-alpha (Android) — not a mainstream
    shipped mobile experience yet.

## 15. Publishing

Publishing for DB graphs exists as a paid, Sync-gated feature, contrary to
the row's "likely absent" prior:

- **Logseq Publish** requires a Sync account and is paid; it produces
  password-protectable, read-only pages hosted at `logseq.io`, with
  Cloudflare-backed public routes for cross-graph discovery: `/tag/TAG`,
  `/u/USER`, `/graph/GRAPH-UUID`; a self-hosting path (via Cloudflare setup)
  is also documented
  ([docs/db-version.md](https://github.com/logseq/docs/blob/master/db-version.md)).
- The official public roadmap listed "Page publishing" with a target of "end
  of 2025," i.e. this shipped ahead of the July 2026 desktop beta as a Sync-
  tier feature rather than being introduced with 2.0.1
  ([logseq.io public roadmap](https://logseq.io/p/NX4mc_ggEV)).
- The May 2026 team update reports a **privacy fix** — "Protected pages now
  stay hidden from public listings, with configurable self-hosted publish
  server support" — implying Publish had a real privacy bug (previously
  password-protected pages could still surface in public listings) that was
  patched shortly before the 2.0.1 desktop beta
  ([discuss.logseq.com, May 16 2026 update](https://discuss.logseq.com/t/whats-new-with-logseq-db-may-16th-2026/35020)).
- No equivalent publishing story exists for Logseq OG/file graphs in any
  source found — Publish is DB-graph/Sync-only.

## 16. Licensing / governance / maintenance

- **License**: `logseq/logseq` remains **AGPL-3.0**, confirmed both via
  GitHub's license API detection and the repo's own `LICENSE.md`
  ([github.com/logseq/logseq](https://github.com/logseq/logseq),
  license badge references
  [`LICENSE.md`](https://github.com/logseq/logseq/blob/master/LICENSE.md)).
  No license change accompanied the DB pivot.
- **The fork/split is real and structural, not just marketing**: a separate
  repository `logseq/og` ("Logseq og (file version)") exists, created
  2025-12-25 — i.e. the OG split was being prepared on GitHub roughly seven
  months before the 2.0.1 DB beta shipped
  ([github.com/logseq/og](https://github.com/logseq/og)). The official
  announcement states Logseq OG will get "security fixes and patches" and
  "Electron and dependency upgrades" but not new features going forward, with
  all future feature investment going to the DB version
  ([logseq.io, "Big update: Logseq is splitting into two versions"](https://logseq.io/p/e3YDyX5AYr)).
  A dedicated `logseq/db-test` repository ("Used for Database version test")
  hosts the DB-version issue tracker separately from the main repo
  ([github.com/logseq/db-test](https://github.com/logseq/db-test)).
- **Release cadence**: checked the full GitHub Releases history via the API
  (`gh api repos/logseq/logseq/releases`). The pre-2.0 file-version product
  shipped **very frequently** — roughly 90+ tagged "Beta Testing" desktop
  releases from `0.3.8` (2021-09-11) through `0.10.15` (2025-12-01), often
  multiple per month in the 0.6–0.9 era. Then a long gap: nothing tagged
  between `0.10.15` (2025-12-01) and `2.0.1` (2026-07-13) — over seven
  months with **zero** tagged desktop releases while the DB rewrite was
  finished. Since `2.0.1`, as of 2026-08-20 (five-plus weeks later) there is
  **exactly one** tagged 2.0.x release — no `2.0.2` yet — with a separate
  `nightly` unstable channel (latest `20260819`) absorbing ongoing changes
  instead of dot releases
  ([github.com/logseq/logseq/releases](https://github.com/logseq/logseq/releases)).
  Read together with the frequent-but-small forum "What's New with Logseq
  DB" posts (e.g. April 26 and May 16, 2026 —
  [discuss.logseq.com](https://discuss.logseq.com/t/whats-new-with-logseq-db-may-16th-2026/35020)),
  the team is shipping continuously to the nightly/forum-announcement
  cadence but has been conservative about cutting a second tagged desktop
  beta release in the five weeks after 2.0.1.
- **Team focus shift**: corroborated directly by the split announcement's
  framing that maintaining two architectures meant "every feature, bug fix,
  and UX improvement must be built twice, resulting in slower development,"
  and that the split's purpose is to let the team commit fully to the DB
  version's roadmap
  ([logseq.io, "Big update: Logseq is splitting into two versions"](https://logseq.io/p/e3YDyX5AYr)).

---

## Pros / Cons of the DB architecture

Each point is grounded in a primary source; synthesis-only points are labeled.

### Strengths

- **Typed, first-class data model.** Properties, classes, and tags are real
  datascript entities with declared types and closed-value choices, not
  regex-parsed `key:: value` text — enables the visual query/table/gallery
  Views layer and bulk operations that were structurally impossible on
  free-text properties
  ([docs/db-version.md](https://github.com/logseq/docs/blob/master/db-version.md); §1, §5 above).
- **Performance at scale.** The team's own framing: "The application
  performance is better — loading faster, handling larger graphs and large
  tables" ([db-version-changes.md](https://github.com/logseq/docs/blob/master/db-version-changes.md)),
  and the roadmap cites 50k-page large-graph support as a sync/DB target
  ([logseq.io split announcement](https://logseq.io/p/e3YDyX5AYr)) — directly
  answering OG's well-known large-graph slowness (**synthesis**: consistent
  with, though not itself proof of, community reports of multi-minute OG
  load times on large graphs).
- **Real sync/collaboration substrate.** A structured op-log
  (`client_ops`/`sync_meta` in `client-ops-db.sqlite`) with checksums and
  ordered pending-upload replay is a materially more sync-able foundation
  than diffing markdown files
  ([ADR 0015](https://github.com/logseq/logseq/blob/master/docs/adr/0015-client-ops-and-sync-meta-in-client-sqlite.md)).
- **No parse fragility.** Content lives as datoms, not as markdown text that
  must be re-parsed on every read/write — the whole class of "regex missed
  an edge case in `key:: value` parsing" bugs the sibling doc's importer
  concerns are built around simply doesn't apply inside Logseq itself
  (**synthesis**, following from the sibling doc's data model description).
- **Concrete, if partial, answer to lock-in.** The Markdown Mirror ships a
  real (if one-way, desktop-only) live markdown projection within months of
  the beta, rather than leaving the plaintext complaint unaddressed
  ([ADR 0016](https://github.com/logseq/logseq/blob/master/docs/adr/0016-markdown-mirror.md)).

### Weaknesses

- **Data-lock-in perception is real and team-acknowledged as a tradeoff.**
  SQLite is the sole live source of truth; the sanctioned interchange format
  (EDN) requires an explicit export step and specialized tooling to read
  (see sibling doc §3/§4) — a materially higher barrier than "open the
  folder in any text editor," which is what OG offered natively.
- **Markdown export is lossy by design, not just by bug.** The in-app
  markdown export carries a literal `"TODO: indent-style and
  remove-options"` in its own source and cannot represent DB-only constructs
  (typed properties as entities, class/ontology, closed values, Views) — see
  sibling doc [§2](./research-logseq-db-format.md#2-official-export-paths).
  The Markdown Mirror is explicitly *not* a substitute: it drops ambiguous
  refs, excludes property pages, and is one-way
  ([ADR 0016](https://github.com/logseq/logseq/blob/master/docs/adr/0016-markdown-mirror.md)).
- **Plugin ecosystem regression at beta.** Marketplace compatibility is
  opt-in per plugin (`supportsDB` flag,
  [logseq/marketplace README](https://github.com/logseq/marketplace/blob/master/README.md)),
  and `db-version.md`'s own count — "Over 65 plugins support DB graphs" — is
  a small fraction of the multi-hundred-plugin marketplace
  ([docs/db-version.md](https://github.com/logseq/docs/blob/master/db-version.md)).
  Multiple plugin-API calls (`addPropertyValueChoices`, `upsertBlockProperty`,
  `upsertProperty`, HTTP-API property namespacing) have open correctness bugs
  in `db-test` as of Aug 2026 (§11 above, with issue links).
- **Feature regressions at 2.0.1, not just format changes.** Whiteboards were
  removed outright rather than migrated; flashcards were reimplemented with
  no data migration from OG graphs (old SRS history is not imported); PDF
  annotation import from legacy graphs is lossy for linked (non-asset) PDFs
  (§12 above, with issue links) — these are real feature debt, not merely
  "different UX."
- **Fork/community friction is structural, team-acknowledged, and
  resource-splitting.** The team's own words: two architectures meant "every
  feature, bug fix, and UX improvement must be built twice" — the fix
  (splitting into Logseq OG vs Logseq) is itself evidence the community was
  split enough by architecture that the team judged serving both
  simultaneously unsustainable
  ([logseq.io split announcement](https://logseq.io/p/e3YDyX5AYr)). The
  eight-plus-month gap in the desktop release history between `0.10.15`
  (2025-12-01) and `2.0.1` (2026-07-13) — during which OG effectively froze —
  is itself the visible cost users paid for the rewrite (§16 above).

---

## Rows with the thinnest primary-source coverage

Flagged honestly rather than overstated:

- **§6 (knowledge graph/backlinks)**: solid on the graph-*visualization*
  rebuild (Graph View V2), but no primary source found describing any
  algorithmic change to backlink discovery/ranking itself.
- **§8 (sync pricing)**: no primary-source figure found for DB-version
  Sync/RTC/"Logseq Pro" pricing; only third-party aggregator blogs had
  numbers, which were deliberately excluded per the sourcing rules.
- **§13 (journals)**: thin by nature — the primary sources themselves say
  there's little beyond the unified node system to report for journals in
  the DB version.
