# Logseq OG (file-based, pre-2.0) — Primary-Source Feature & Maintenance Audit

**Scope.** This document covers Logseq's original, file-based, markdown/org-mode product — retroactively named **"Logseq OG"** after Logseq split its codebase in 2026 — as distinct from the **Logseq 2.0** SQLite/DB-first rewrite. Research was conducted in **August 2026** against primary sources only: the `logseq/logseq` and `logseq/og` GitHub repositories (code, README, releases, issues), `docs.logseq.com` / the `logseq/docs` repository, `blog.logseq.com`, and official forum/announcement pages published by the Logseq team on `logseq.io` and `discuss.logseq.com`. Where no primary source could be found after a genuine search, this is stated explicitly rather than filled in from secondary sources.

**Important context found during research:** Logseq announced in 2026 that it is splitting into two products. The file-based, Markdown/Org-mode app is now maintained separately as **"Logseq OG"** at `github.com/logseq/og`, receiving security fixes and Electron/dependency upgrades but no new features, while the "Logseq" name and product roadmap now belong to the new local-SQLite, DB-first rewrite at `github.com/logseq/logseq`. Because `logseq/og` was forked from `logseq/logseq` at the point of the split, most of Logseq's historical documentation (in `logseq/docs`, and much of `docs.logseq.com`) still describes the shared, pre-split feature set and is treated here as describing Logseq OG except where a source explicitly marks a feature as DB-version-only (e.g. RTC sync, typed properties/classes, dashboard queries) — those are called out as **absent in OG**.

---

## 1. Note model (pages, blocks, properties, tags, namespaces, aliases)

Every page and every outline block can carry `key:: value` properties. Page properties live in the first block of a page (the "frontmatter" block); block properties live in any other block. Property names are case-insensitive, lower-cased, and `_` is auto-renamed to `-`. Property values can contain plain text, `[[page links]]`, and `#tags`; wrapping a value in quotes suppresses link parsing. Built-in properties like `tags` and `alias` also accept comma-separated lists (`tags:: motor, steering wheel`) which are auto-converted to page references. Namespaces are page titles containing `/` (e.g. `Logseq/Features`), stored on disk with an encoded filename (`Logseq___Features.md` in the modern `:triple-lowbar` format, or percent-encoded `Logseq%2FFeatures.md` in the legacy format). Aliases are declared with `alias:: PKM` in a page's first block, redirecting `[[PKM]]` references to that page.

- Properties: `logseq/docs:pages/Properties.md` — https://raw.githubusercontent.com/logseq/docs/master/pages/Properties.md
- Built-in properties list: `logseq/docs:pages/Built-in Properties.md`, which also points to the canonical source `logseq/graph_parser/property.cljs` — https://github.com/logseq/logseq/blob/master/deps/graph-parser/src/logseq/graph_parser/property.cljs
- Filename encoding / namespaces: `logseq/docs:pages/Filename format.md` — https://raw.githubusercontent.com/logseq/docs/master/pages/Filename%20format.md
- Aliases: `logseq/docs:pages/Aliases and external links.md`
- The dedicated `logseq/docs:pages/Namespaces.md` and `logseq/docs:pages/Tags.md` pages are themselves unfinished TODO stubs in the official docs repo ("TODO Document this feature") — noted here as an honest primary-source gap, not filled in from secondary sources.

## 2. Editor (outliner, markdown/org-mode dual support, WYSIWYG-ish editing, math/katex, tables)

Logseq OG is a block-based outliner where every line is a block that can be collapsed, indented, and re-parented; the same graph can mix Markdown and Org-mode files, both parsed by Logseq's own parser library, `mldoc`. Editing is a live-preview ("WYSIWYG-ish") textarea that renders formatting (bold, links, embeds) around the cursor while a block is not focused. Inline and block math is supported via KaTeX syntax (`$...$` / `$$...$$`), including chemistry via the mhchem package. Tables are a "versioned component": version 1 is the original plain markdown table; a version-2 beta adds per-table props (`logseq.table.hover`, `.compact`, `.stripes`, `.borders`, `.max-width`, `.color`) settable inline or via `config.edn`.

- Markdown syntax: `logseq/docs:pages/Markdown.md`
- Org-mode syntax and parser: `logseq/docs:pages/Org Mode.org` — both explicitly say "parsed by https://github.com/logseq/mldoc"
- Math/KaTeX: `logseq/docs:pages/Math Block.md`
- Tables: `logseq/docs:pages/Tables.md`

## 3. References (wikilinks, block refs, embeds, transclusion)

`[[page name]]` creates a page (wiki)link; `((uuid))` creates a block reference to a specific block by its UUID, created by typing `((`, using the `/Block reference` command, or copying a block-ref via a keyboard shortcut. `{{embed [[page name]]}}` transcludes an entire page's content into the current block; `{{embed ((block-uuid))}}` transcludes a single block and its children. Labeled variants exist: `[display text]([[page name]])` and `[display text](((block-uuid)))`. Referenced blocks show a reference counter that expands all linked references grouped by page.

- `logseq/docs:pages/Markdown.md` (syntax table for all reference types)
- `logseq/docs:pages/Block Reference.md` — https://raw.githubusercontent.com/logseq/docs/master/pages/Block%20Reference.md

## 4. Tasks & scheduling

Tasks are just blocks with a workflow-marker keyword at the start. Two selectable marker flavors exist: `LATER → NOW → DONE` (default) and `TODO → DOING → DONE`, cycled with `Ctrl/Cmd+Enter` or typed directly (`/LATER`). Additional markers `CANCELED/CANCELLED`, `IN-PROGRESS`, and `WAIT/WAITING` can be typed manually. Three optional priorities, `[#A]`/`[#B]`/`[#C]`, attach via commands or by typing the bracket syntax after the marker. `SCHEDULED: <date>` and `DEADLINE: <date>` commands attach dates to any block (not just tasks), configurable to show upcoming items N days ahead via `:scheduled/future-days` in `config.edn`. Both support repeaters with three kinds: `.+` (repeats from last completion), `++` (keeps same weekday), `+` (repeats X units from original schedule) — e.g. `SCHEDULED: <2021-05-26 Wed 7:00 .+1d>`. A built-in time tracker / LOGBOOK-style clock feature exists and can be toggled off via a setting.

- `logseq/docs:pages/Tasks.md` — https://raw.githubusercontent.com/logseq/docs/master/pages/Tasks.md

## 5. Queries (simple, advanced datalog, dynamic tables)

Two query tiers exist. **Simple queries** (`{{query ...}}`) use a small filter DSL with boolean operators `and`/`or`/`not` and filters including `between` (journal date ranges with symbols like `today`, `-7d`), `page`, `property`, full-text query (desktop-only), `task`, `priority`, `page-property`, `page-tags`, `all-page-tags`, and `sort-by`. **Advanced queries** are raw Datalog against the in-memory Datascript database, written as an EDN map (`:title`, `:query`, `:inputs`, `:view`, `:result-transform`, `:collapsed?`, `:group-by-page?`, `:rules`, etc.), with special query inputs like `:current-page`, `:today`, and relative-date tokens (`:-7d`, `:+1m`). Results can render as dynamic tables via `query-table:: true` plus `query-properties`, `query-sort-by`, `query-sort-desc` block properties.

- Simple queries: `logseq/docs:pages/Queries.md`
- Advanced queries: `logseq/docs:pages/Advanced Queries.md` — explicitly states "Advanced queries are written with Datalog and query the Datascript database"
- Query-table properties: `logseq/docs:pages/Built-in Properties.md`

## 6. Knowledge graph & backlinks

A whole-graph force-directed **Graph view** is reachable from the profile menu. **Linked references** appear at the bottom of a page for every block/page that references it, grouped by page. **Unlinked references** — occurrences of a page's name in text that were never turned into `[[links]]` — are shown in a separate toggleable section at the bottom of a page.

- Graph view: `logseq/docs:pages/Knowledge Graph.md`
- Unlinked references: `logseq/docs:pages/Unlinked References.md`
- Linked references: `logseq/docs:pages/Linked References.md` — this doc page is itself an unfinished TODO stub in the official docs repo; the behavior is documented instead via the Block Reference and Knowledge Graph pages above.

## 7. Search & indexing

On open, Logseq OG parses every Markdown/Org file in the graph folder into an in-memory **Datascript** database (an immutable Datalog store) that backs both the outliner UI and queries; this is the "rebuild from files" architecture. Search (`Cmd/Ctrl-k`) covers pages, blocks, files, and commands, with a `/` filter prefix; block search only finds blocks inside pages (not, e.g., the sidebar). Desktop additionally has full-text search across multiple blocks with out-of-order term matching. Search is backed by a separate, rebuildable search index (`Rebuild search index` command) distinct from the Datascript graph DB.

- Search: `logseq/docs:pages/Search.md`
- Datascript as the query engine/backing DB: `logseq/docs:pages/Advanced Queries.md` ("query the Datascript database"); Datascript is also listed as a core dependency in the `logseq/og` README credits section — https://raw.githubusercontent.com/logseq/og/master/README.md
- Frontend source directories consistent with this architecture (`/db`, `/persist_db`, `/search`, `/worker`) are visible in the repo tree: https://github.com/logseq/og/tree/master/src/main/frontend

## 8. Sync & collaboration

**Logseq Sync** is a paid, end-to-end-encrypted cloud sync add-on (in BETA at time of the cited doc), available to Open Collective backers contributing $5–$15/month, syncing up to 10 graphs across Desktop/Android/iOS. Each graph — including file names and paths — is encrypted client-side with a password using the `age` encryption tool; encrypted blobs are stored on AWS. Logseq Sync explicitly should not be combined with git or other third-party sync (iCloud/Syncthing/Dropbox) for the same graph. Separately, because graphs are just folders of plain-text files, any third-party file-sync tool (iCloud, Dropbox, Syncthing) works as a DIY sync mechanism, with the caveat that only one device should actively edit at a time to avoid conflicts. A built-in **Git Auto-Commit** feature can commit (but not push) local changes to a git repo at a configurable interval (1–600s) for version history/backup, independent of any sync mechanism. Real-time multi-user collaboration (RTC) is a DB-version-only feature and is **absent in OG** — the OG-era docs explicitly note "This isn't supported yet" for using Sync with other users.

- Logseq Sync: `logseq/docs:pages/Logseq Sync.md` — https://raw.githubusercontent.com/logseq/docs/master/pages/Logseq%20Sync.md
- File-sync-as-DIY-sync and single-writer caveat: `logseq/docs:pages/How to sync your Logseq graph across devices.md`
- Git Auto-Commit: `logseq/docs:pages/Git Auto-Commit.md`
- RTC as DB-version-only: `logseq/og:README.md` ("The DB version also has a new sync approach, RTC...") — https://raw.githubusercontent.com/logseq/og/master/README.md

## 9. Import/export

**Export**: supports whole-graph export (EDN, JSON, Standard Markdown, OPML, **Roam JSON**, HTML) and single-page/block/selection export (Text, OPML, HTML, PNG), each with format-specific options (strip brackets/emphasis/tags, block-depth limit, indentation style, include/exclude properties). Note block properties are explicitly dropped from "Standard Markdown" graph exports.

- `logseq/docs:pages/Export.md` — https://raw.githubusercontent.com/logseq/docs/master/pages/Export.md

**Import**: the official `logseq/docs:pages/Import.md` page is an unfinished stub ("TODO Document feature"), so Logseq's own docs do not spell out the Roam Research import flow in detail. Community/secondary sources (nesslabs.com, hub.logseq.com) describe a Roam JSON-export importer, but per this audit's sourcing rules that is **unverified against a primary source** beyond the fact that "Roam JSON" is a listed graph-export *output* format (see Export.md above), which implies round-trip compatibility exists at the format level. The presence of a Roam-format export option is primary-sourced; a dedicated Roam *importer* UI is referenced only secondarily and is flagged here as **unverified — no primary source found** for its exact mechanics.

**logseq-publish static export**: see row 15.

## 10. Storage format & data ownership

Every page is one plain-text file (`.md` by default, `.org` if configured) inside a `pages/` (and `journals/`) folder on local disk; namespace pages are encoded into filenames (row 1). No proprietary database sits between the user and their notes — the Datascript DB (row 7) is a disposable in-memory index rebuilt from the files, not the source of truth. The OG-era README is explicit that this brings a tradeoff: "When using file graphs, **data corruption is possible** as some file content can be duplicated. We only recommend using it with file graphs if you make regular backups with git."

- `logseq/og:README.md` — https://raw.githubusercontent.com/logseq/og/master/README.md
- Filename encoding mechanics: `logseq/docs:pages/Filename format.md`

## 11. Plugins/extensibility

A desktop-only plugin API lets third-party JS/TS plugins extend the app; plugins (and themes, which are distributed as a plugin type) are browsed and installed from an in-app **Marketplace** dashboard (`tp` shortcut) backed by `github.com/logseq/marketplace`, or side-loaded via "Load unpacked plugin." Plugin updates are checked every 12 hours. Plugin API docs live at `plugins-doc.logseq.com`. Theming can also be done without plugins via `logseq/custom.css` (per-graph, loaded at startup — the docs explicitly warn about self-maintaining any custom CSS for stability/security) and `logseq/custom.js`. Graph-level behavior is configured via `logseq/config.edn`, documented informally via a template file in the source tree rather than a full reference page. Plugins are explicitly **desktop-only** — "not available for mobile or the browser."

- `logseq/docs:pages/Plugins.md`, `logseq/docs:pages/Marketplace.md`, `logseq/docs:pages/custom.css.md`, `logseq/docs:pages/config edn file.md`
- config.edn reference source: `logseq/logseq:deps/common/resources/templates/config.edn` — https://github.com/logseq/logseq/blob/master/deps/common/resources/templates/config.edn
- Marketplace repo: https://github.com/logseq/marketplace

## 12. Whiteboards, flashcards/SRS, PDF annotation

**Whiteboards**: a toggleable spatial-canvas feature ("free for everyone") built on "a fork of tldraw," reachable from a dedicated left-sidebar section. Each whiteboard is stored as its own `.edn` file in a `whiteboards/` folder inside the graph — deletable directly from the filesystem. The canvas supports drag-and-drop page/block embeds ("portals"), images/PDFs/videos, YouTube/Tweet-aware object embeds, freeform drawing/shapes, and a toolbar (Select, Move, Portal, Pencil, Highlight, Eraser, Connector, Text, Shapes).

**Flashcards/SRS**: any block tagged `#card` or `[[card]]` becomes a flashcard (can include Clozes). Cards are reviewed via a dedicated "Flashcards" sidebar tab (`t c` shortcut) or scoped with `{{cards [[Page]]}}` / `{{cards (not [[Page]])}}` queries. Scheduling state is stored as ordinary block properties on the card block itself: `card-last-interval`, `card-repeats`, `card-ease-factor`, `card-next-schedule`, `card-last-reviewed`, `card-last-score` — an SM-2-family (SuperMemo-derived) spaced-repetition scheduler, evidenced by the ease-factor/interval property shape and an explicit doc link to SuperMemo's SM5 algorithm page; the docs do not name the exact algorithm variant in prose, so "SM-2-family" is an inference from the property names and cited link, not a verbatim primary-source label.

**PDF annotation**: desktop-only. PDFs are dragged into a block or uploaded via `/upload an asset`, stored inside the graph's `assets/` folder (with no automated cleanup if unlinked). Users can highlight selected text or drag-select an area, each with a chosen color; highlights can be pasted as a reference into any block. Three PDF-viewer dark-mode themes and an outline/TOC view are supported.

- Whiteboards: `logseq/docs:pages/Whiteboard.md` — https://raw.githubusercontent.com/logseq/docs/master/pages/Whiteboard.md
- Flashcards: `logseq/docs:pages/Flashcards.md` — https://raw.githubusercontent.com/logseq/docs/master/pages/Flashcards.md (links to SuperMemo's SM5 page and "Augmenting Long-term Memory")
- `logseq/docs:pages/Spaced Repetition.md` is a stub that only quotes Wikipedia's definition of spaced repetition — the algorithm itself is not documented in prose by Logseq; flagged as a primary-source gap.
- PDF highlights: `logseq/docs:pages/PDF highlights.md`

## 13. Calendar/journals

The dedicated `logseq/docs:pages/Journals page.md` doc is an unfinished TODO stub in the official docs repo, so Logseq's own documentation does not spell out journal-page mechanics in prose beyond referencing an external "Getting started with the Journals page" tutorial page (also present in the docs repo but not fetched in full here). What is directly confirmed from primary sources: journal pages are a first-class page type distinguishable from regular pages in Datalog queries (the `between` simple-query filter explicitly operates "only on blocks on the journal pages," and advanced queries have dedicated relative-date inputs like `:today`, `:-7d`, `:+1m` "useful for querying journal pages"), and a `setting/enable journals` toggle exists to turn the feature off entirely. Per-day settings such as journal page title/file format live in `config.edn` (not itself examined page-by-page here).

- `logseq/docs:pages/Queries.md` (`between` filter description) and `logseq/docs:pages/Advanced Queries.md` (relative-date inputs)
- `logseq/docs:pages/setting___enable journals.md` (existence of the toggle, filename indicates a settings-reference stub page)
- `logseq/docs:pages/Journals page.md` — TODO stub, flagged as a primary-source documentation gap.

## 14. Platforms & mobile quality

Logseq OG ships as an Electron desktop app (Windows/macOS/Linux, with a Linux install script) and mobile apps for Android and iOS, all built from the same file-based codebase/graph format, per the `logseq/og` README and its release list (e.g. "Desktop/Android APP 1.0.0"). Mobile quality has been a persistent, officially tracked pain point: the `logseq/logseq` GitHub issue tracker (the pre-split, shared-codebase repo, which mobile issues were filed against before the 2026 split) contains numerous maintainer-triaged reports, including app-restart/RAM pressure on Android (issue #5638), long/repeated loading screens on iOS (#10028) and Android (#10119), the iOS app freezing (#9615), the Android app freezing when opening search (#10771), and slow syncing causing disruption (#10999). These are cited as evidence of documented, officially-tracked mobile pain points rather than as maintainer statements acknowledging the problems in prose.

- Releases (desktop + Android under one artifact): https://github.com/logseq/og/releases
- Mobile issues (official tracker, `logseq/logseq`):
  - https://github.com/logseq/logseq/issues/5638 ("App restarting regularly. Not enough RAM to keep it in background")
  - https://github.com/logseq/logseq/issues/10028 ("iOS app 'loading...' screen appears 6-8 times before I can use the app")
  - https://github.com/logseq/logseq/issues/10119 ("Opening the Android app (almost) always takes a long time")
  - https://github.com/logseq/logseq/issues/9615 ("iOS app keeps freezing")
  - https://github.com/logseq/logseq/issues/10771 ("opening search on Android client freezes app")
  - https://github.com/logseq/logseq/issues/10999 ("Slow syncing leading to disruption")

## 15. Publishing/typesetting

**logseq-publish**: a graph can be exported as a static, read-only single-page app via "Export public graph pages as html" (desktop-only). Publishing is controlled per-page via a `public` property (or a graph-wide "public by default" setting with per-page opt-out), and the exported bundle can read the graph's `config.edn`, `custom.css`, `custom.js`, and `export.css`. Most read-only features (search, page/block links) work in a published app; anything requiring editing, or desktop-only features like plugins/themes-as-plugins, does not — the docs give a `custom.css @import` workaround for applying a theme to a published site. Publishing/export tooling itself is decoupled into a companion GitHub Action/CLI, `logseq/publish-spa`. No PDF-export quality claims are made in the official docs beyond PNG image export of a page/selection/whiteboard; a dedicated "export whole graph to PDF" feature is **absent** from the primary sources found — publishing targets HTML/SPA output, not PDF.

- `logseq/docs:pages/Publishing.md`, `logseq/docs:pages/Publish Web.md`, `logseq/docs:pages/Publishing (Desktop App Only).md`
- Publish action/CLI: https://github.com/logseq/publish-spa
- Export formats (no PDF listed): `logseq/docs:pages/Export.md`

## 16. Licensing, governance, maintenance

Both `logseq/logseq` (current DB-version repo) and `logseq/og` (file-version repo) ship a `LICENSE.md` containing the **GNU Affero General Public License v3.0 (AGPL-3.0)** verbatim.

Logseq the company was founded in 2020 by Tienson Qin (CEO), ZhiYuan Chen, and Huang Peng, and raised a $4.1M seed round in May 2022 led by Patrick Collison (Stripe), Nat Friedman (ex-GitHub), and Tobias Lütke (Shopify), with participation from Sriram Krishnan (a16z), Craft Ventures, Matrix Partners China, Day One Ventures, Charlie Cheever, and Dave Winer; the team was nine people at the time of that post. The project also runs an Open Collective for community sponsorship/backing, separate from the equity raise, which directly funds the Logseq Sync beta (row 8).

**The 2026 split, in the maintainers' own words** (official announcement page, published on Logseq's own site at logseq.io): Logseq is dividing into two products — **Logseq OG**, the Markdown/file-based graph app moved to its own repo at `github.com/logseq/og`, and **Logseq**, the new local-SQLite database app which keeps the name and the forward roadmap. The stated reason: maintaining two distinct architectures inside one app meant "every feature, bug fix, and UX improvement must be built twice," slowing development. For Logseq OG specifically, the announcement commits to **"security fixes and patches"** and **"Electron and dependency upgrades"** — i.e. stability/reliability maintenance, explicitly **not** new feature development — with no forced migration: existing Markdown users can keep using OG indefinitely, and both apps can be run side by side.

**What that maintenance has looked like in practice, checked directly against the repo (as of this research, August 2026):** `logseq/og` was created 2025-12-25 as the fork point; its only tagged release is `1.0.0` on 2026-04-15; the most recent commits are dated **2026-05-28**, and are exactly the kind of maintenance promised — "Upgrade Electron to 41.7.1" and "fix: upgrade dugite 2.7.1 → 3.2.2 to resolve CVE-2023-5678" — alongside a batch of rebranding commits (custom URL scheme/deeplink changed to `logseq-og`, app-menu title changed to "Logseq OG", separate mobile app identifiers). The repo has had **no commits and no new release for roughly three months** at the time of this research (last push 2026-05-28), while `logseq/logseq` (the DB version) has nightly builds as recently as 2026-08-19 and shipped its `2.0.1` beta on 2026-07-13. This is a directly observable, primary-source data point for how "maintenance-only" is playing out in practice, worth flagging for the competitive audit: the promise (security/Electron patches, no new features) has been kept in kind but the observed cadence has gone quiet for months, not because of new source we could find describing a wind-down, but because there's simply no recent activity to show — noted here as an observation from repo data rather than an official statement of reduced commitment.

- License: https://raw.githubusercontent.com/logseq/og/master/LICENSE.md (and equivalently `logseq/logseq:LICENSE.md`)
- Company/funding: `blog.logseq.com` — https://blog.logseq.com/logseq-raises-4-1m-to-accelerate-growth-of-the-new-world-knowledge-graph/
- Split announcement (official, published on logseq.io): https://logseq.io/page/b2ad9ce1-9cb7-4436-8083-54cb4516d324/df4dc09d-0a12-4c87-904e-22a9bf4c350a — "Big update: Logseq is splitting into two versions"
- `logseq/og` repo metadata (created/pushed dates, release list, commit log) via the GitHub API: https://github.com/logseq/og, https://github.com/logseq/og/releases, https://github.com/logseq/og/commits
- `logseq/logseq` nightly/beta release cadence for comparison: https://github.com/logseq/logseq/releases
- Official "why the database version" statement, including the (pre-split) commitment to keep supporting file-based graphs: https://discuss.logseq.com/t/why-the-database-version-and-how-its-going/26744

---

## Implementation stack summary

- **Frontend**: ClojureScript. The `logseq/og` README credits "Clojure & ClojureScript — A dynamic, functional, general-purpose programming language" as a foundational dependency, and the repo's `src/main/frontend/` tree (handler, components, format, worker, etc.) is ClojureScript source. — https://raw.githubusercontent.com/logseq/og/master/README.md, https://github.com/logseq/og/tree/master/src/main/frontend
- **In-memory DB rebuilt from files**: **DataScript** — "An immutable database and Datalog query-engine for Clojure, ClojureScript and JS" — is listed as a core dependency, and the Advanced Queries docs confirm queries run directly against "the Datascript database." The repo has `/db`, `/persist_db`, and `/worker` directories consistent with parsing files into this DB (worker isolate) rather than a persistent server-side store. — same README; `logseq/docs:pages/Advanced Queries.md`
- **Document parsing**: a separate OCaml/Angstrom-based parser library, **mldoc**, parses both Markdown and Org-mode into Logseq's internal AST — explicitly credited in the README and cited directly in the Markdown.md and Org Mode.org doc pages. — https://github.com/logseq/mldoc, `logseq/docs:pages/Markdown.md`, `logseq/docs:pages/Org Mode.org`
- **Git support**: **isomorphic-git**, "A pure JavaScript implementation of Git for NodeJS and web browsers," is credited as powering the Git Auto-Commit feature. — `logseq/og:README.md`
- **Desktop shell**: **Electron** — confirmed directly by the maintenance commit "Upgrade Electron to 41.7.1" in the `logseq/og` commit log, and by the split announcement's promise of "Electron and dependency upgrades" for OG. — https://github.com/logseq/og/commits, split announcement (row 16)
- **Mobile shell**: primary sources found do **not** name a specific mobile shell technology (e.g. Capacitor) for the file-based OG mobile apps — the `logseq/og` repo does contain a `/mobile` directory and mobile-specific commits (separate app identifiers, deeplink scheme), but no doc or README text was found stating the mobile wrapper framework by name. Flagged as **unverified — no primary source found** rather than assumed to be Capacitor.
- **Plugin runtime**: a JS/TS plugin API (desktop-only), documented separately at `plugins-doc.logseq.com` and distributed via the `logseq/marketplace` repo. — `logseq/docs:pages/Plugins.md`

## Honest pros/cons of the file-based architecture

**Strengths, per primary sources:**
- **Data ownership / no lock-in**: every page is a plain `.md`/`.org` file on local disk; the Datascript DB is explicitly a rebuildable index, not the source of truth. The `logseq/og` README states the goal of user control directly, linking to the FSF's definition of free software. — https://raw.githubusercontent.com/logseq/og/master/README.md
- **Interoperability**: graphs can be created from pre-existing Markdown files, and export supports OPML, HTML, Roam JSON, and "Standard Markdown" for use in other tools. — `logseq/docs:pages/Export.md`
- **Sync-tool agnosticism / git-friendliness**: any file-sync tool works because the data is just files, and a built-in Git Auto-Commit feature turns any graph into a versioned git repo on a timer. — `logseq/docs:pages/Git Auto-Commit.md`, `logseq/docs:pages/How to sync your Logseq graph across devices.md`

**Weaknesses, per primary/maintainer sources:**
- **File corruption risk on concurrent/multi-device use**: the OG README itself warns "data corruption is possible as some file content can be duplicated," recommending regular git backups for file graphs — a maintainer-acknowledged weakness, not a third-party complaint. — https://raw.githubusercontent.com/logseq/og/master/README.md
- **Single-writer constraint**: official docs state only one device should actively edit a graph at a time when relying on generic file sync, requiring manual re-indexing after switching devices. — `logseq/docs:pages/How to sync your Logseq graph across devices.md`
- **Performance degradation on large graphs**, since the whole graph is parsed into an in-memory Datascript DB at startup: officially tracked GitHub issues document freezes/lockups on large graphs and pages — e.g. a graph of 18,500 interlinked pages freezing the graph view (#8398), an import of ~4,000 org journals with tens of thousands of blocks locking up indefinitely (#8544), 10–20 second UI freezes editing large files (#6002), and app launch failures once a graph exceeds ~300MB / 30,000 files (#11236).
  - https://github.com/logseq/logseq/issues/8398, https://github.com/logseq/logseq/issues/8544, https://github.com/logseq/logseq/issues/6002, https://github.com/logseq/logseq/issues/11236, https://github.com/logseq/logseq/issues/8137
- **`key:: value` properties live inside the text body**, not as structured metadata in a separate layer — this is the row-1/row-10 architecture itself (properties are literally text lines inside a block, delimited by newlines, per `logseq/docs:pages/Properties.md`: "a property value can't have newlines" is called out as a direct consequence of this embedding). The maintainers' own rationale for building the DB version cites this class of limitation in general terms — poor performance with large graphs, unreliable undo, lack of real structure for collaboration — as motivation for moving away from the file/property-in-text model. — `logseq/docs:pages/Properties.md`; https://discuss.logseq.com/t/why-the-database-version-and-how-its-going/26744
- **Markdown/Org parse fragility surfaces at the filename layer too**: Logseq had to ship a breaking, opt-in filename-format migration (`:legacy` → `:triple-lowbar`) specifically because encoding page titles (namespaces, special characters) into cross-platform-safe filenames was ambiguous and error-prone under the original scheme — an architecture-level cost of the one-file-per-page model that a DB does not have. — `logseq/docs:pages/Filename format.md`
- **Mobile quality**: see row 14 — multiple officially tracked, unresolved issues around freezing, slow loading, and background-memory eviction on both Android and iOS predate and are independent of the 2.0 split.
- **Maintenance-only status going forward**: by the maintainers' own commitment (row 16), OG will not receive new features, only security/Electron patches — a structural, permanent ceiling on the file-based product's capability relative to the DB version, confirmed by the observed ~3-month commit gap since the last Electron/CVE patch as of this research.

---

*Rows/claims marked "unverified — no primary source found" or "absent" in this document: row 9 (Roam import mechanics beyond the Roam-JSON export format), row 13 (journal-page mechanics beyond the query-input evidence — the official doc page is an unfinished stub), row 14/Implementation-stack (mobile shell framework name), row 5/13 boundary (RTC collaboration is confirmed absent in OG, being DB-version-only).*
