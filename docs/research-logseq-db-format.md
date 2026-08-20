# Logseq DB-version graph storage format (as of 2026-08)

Research for a third-party importer. All claims traced to primary sources: the
`logseq/logseq` repo (master, mid-Aug 2026, and the released `2.0.1` beta tag of
2026-07-13), the `@logseq/cli` npm package README, and `logseq/nbb-logseq`.
Repo paths below are in https://github.com/logseq/logseq unless stated otherwise.

Status context: the DB version shipped as the "Logseq 2.0 Beta (DB version)"
desktop release 2.0.1 on 2026-07-13; the file-based product is being renamed
"Logseq OG" ([release notes](https://github.com/logseq/logseq/releases/tag/2.0.1)).

## TL;DR for an importer

A DB graph is a datascript (CLJS Datalog) database persisted through
datascript's `IStorage` protocol into a single SQLite table `kvs
(addr INTEGER PRIMARY KEY, content TEXT, addresses JSON)`. `content` rows are
**transit-JSON-encoded datascript index-tree nodes**, not rows-per-datom — you
cannot usefully read the data with plain SQL. The sanctioned machine
interchange is the EDN "graph" export (CLI `graph export --type edn`, in-app
"Export EDN"), which embeds the schema version and is designed "to be simple,
reliable and for machines". Couple to that, not to the SQLite layout.

## 1. On-disk location and SQLite schema

### Locations per platform

- **Desktop (2.0 beta, Electron) and CLI**: disk SQLite under `~/logseq/graphs/`
  is the source of truth; "OPFS periodic export is not part of the desktop
  primary write path". Graph layout:
  `~/logseq/graphs/<graph-name>/db.sqlite` plus `search-db.sqlite`,
  `client-ops-db.sqlite` (sync ops), `backup/<backup-name>/db.sqlite`, and
  `assets/<block-uuid>.<ext>`. Graph dir names are the user-facing graph name
  (no `logseq_db_` prefix), URI-encoded.
  Sources: [docs/cli/logseq-cli.md](https://github.com/logseq/logseq/blob/master/docs/cli/logseq-cli.md)
  ("Disk SQLite under `~/logseq/graphs` is the source of truth", backup-scope
  note naming all three sqlite files, `upsert asset` copying into `assets/`) —
  same text is present in the shipped tag
  [2.0.1/docs/cli/logseq-cli.md](https://github.com/logseq/logseq/blob/2.0.1/docs/cli/logseq-cli.md);
  default dir constant `(defonce default-graphs-dir "~/logseq/graphs")` in
  [deps/common/src/logseq/common/config.cljs](https://github.com/logseq/logseq/blob/master/deps/common/src/logseq/common/config.cljs)
  (overridable via `$LOGSEQ_GRAPHS_DIR`, see `get-default-graphs-dir` in
  [deps/common/src/logseq/common/graph.cljs](https://github.com/logseq/logseq/blob/master/deps/common/src/logseq/common/graph.cljs));
  path assembly `<graphs-dir>/<encoded-name>/db.sqlite` in `get-db-full-path`,
  [deps/db/src/logseq/db/common/sqlite.cljs](https://github.com/logseq/logseq/blob/master/deps/db/src/logseq/db/common/sqlite.cljs);
  dir-name encoding in
  [deps/common/src/logseq/common/graph_dir.cljs](https://github.com/logseq/logseq/blob/master/deps/common/src/logseq/common/graph_dir.cljs).
  Desktop and CLI share a per-graph `db-worker-node` daemon guarded by a lock
  file (single-writer; `owner-source` cli/electron) — do not write to a live
  graph's db.sqlite from outside.
- **Web app / in-browser (and WebView-based mobile builds)**: SQLite WASM
  (`@sqlite.org/sqlite-wasm`) over an OPFS SAHPool VFS; each graph is an OPFS
  directory named `.logseq-pool-<pool-name>` with logical DB path `/db.sqlite`
  (client-ops at `client-ops/db.sqlite`). Sources:
  [src/main/frontend/worker/platform/browser.cljs](https://github.com/logseq/logseq/blob/master/src/main/frontend/worker/platform/browser.cljs)
  (`installOpfsSAHPoolVfs`, `.logseq-pool-` prefix);
  [src/main/frontend/worker/db_core.cljs](https://github.com/logseq/logseq/blob/master/src/main/frontend/worker/db_core.cljs)
  (`(def repo-path "/db.sqlite")`, `client-ops/db.sqlite`). The worker has
  exactly two storage platforms — browser (OPFS) and node (`node:sqlite`
  `DatabaseSync`):
  [src/main/frontend/worker/platform/node.cljs](https://github.com/logseq/logseq/blob/master/src/main/frontend/worker/platform/node.cljs).
  Pre-2.0 desktop betas kept the live graph in Electron's OPFS with periodic
  disk export (that is the "OPFS periodic export" the CLI doc says is no longer
  the desktop write path).

Graph name prefix: DB graph repo names carry `logseq_db_`
(`(defonce db-version-prefix "logseq_db_")`,
[deps/common/src/logseq/common/config.cljs](https://github.com/logseq/logseq/blob/master/deps/common/src/logseq/common/config.cljs)).

### db.sqlite schema: the kvs table

One table:

```sql
create table if not exists kvs (addr INTEGER primary key, content TEXT, addresses JSON)
```

— `create-kvs-table!` in
[deps/db/src/logseq/db/common/sqlite.cljs](https://github.com/logseq/logseq/blob/master/deps/db/src/logseq/db/common/sqlite.cljs).

How datoms are stored: datascript persists its immutable index trees through
the `datascript.storage/IStorage` protocol; each `kvs` row is one storage node.

- `content` = transit-JSON string of the node data
  (`sqlite-util/write-transit-str` / `read-transit-str`).
- `addresses` = JSON array of the node's child addresses, split out of the
  transit blob into a real JSON column so SQLite can walk the tree
  (`json_each(kvs.addresses)`) for GC.
- `addr 0` = DB meta: a transit map holding the root addresses of the `:eavt`,
  `:aevt`, `:avet` indexes (plus schema); `addr 1` = the "tail" (recent datoms
  buffer, a datascript storage performance detail). All other rows are
  persistent-sorted-set branch/leaf nodes whose leaves contain the datoms.

Sources: storage impl (`-store`/`-restore`, transit encode/decode, `:addresses`
split) in
[deps/db/src/logseq/db/common/sqlite_cli.cljs](https://github.com/logseq/logseq/blob/master/deps/db/src/logseq/db/common/sqlite_cli.cljs);
addr 0/1 semantics and the GC walk in
[deps/db/src/logseq/db/sqlite/gc.cljs](https://github.com/logseq/logseq/blob/master/deps/db/src/logseq/db/sqlite/gc.cljs)
(comment: "Datascript sets 0 as the address to store the db's meta, including
addresses for :eavt, :avet, and aevt index. 1: ... tail").

Transit encoding details: writer = transit `:json` with
`datascript.transit/write-handlers` merged with `cljs-bean` handlers plus
custom handlers for datascript `Entity` ("datascript/Entity"), `ExceptionInfo`
("error") and `js/Error`; reader mirrors these
([deps/db/src/logseq/db/sqlite/util.cljs](https://github.com/logseq/logseq/blob/master/deps/db/src/logseq/db/sqlite/util.cljs)).
So content strings contain transit tags like `#datascript/Datom`, keywords,
uuids — a generic transit reader needs datascript-transit's handlers.

Important: Logseq pins a **fork** of datascript
(`datascript/datascript {:git/url "https://github.com/logseq/datascript" :sha "3f141af9..."}`)
plus `datascript-transit 0.3.0`
([deps/db/deps.edn](https://github.com/logseq/logseq/blob/master/deps/db/deps.edn)).
Upstream datascript's storage may not be byte-compatible.

### Side tables / side files

`db.sqlite` itself has only `kvs`. Full-text search lives in a separate
`search-db.sqlite` per graph with:

- `blocks (id TEXT PRIMARY KEY, title TEXT NOT NULL, page TEXT)` — id/page are
  block/page uuids;
- `blocks_fts` — `fts5(id, title, page, tokenize="trigram")` virtual table,
  kept in sync by AFTER INSERT/UPDATE/DELETE triggers on `blocks`;
- index `blocks_title_nocase_idx`.

Source:
[src/main/frontend/worker/search.cljs](https://github.com/logseq/logseq/blob/master/src/main/frontend/worker/search.cljs).
It is derived data (rebuildable, excluded from backups per
docs/cli/logseq-cli.md) — an importer can ignore it. `client-ops-db.sqlite`
holds pending sync operations (also a kvs-style datascript store; see
docs/adr/0015-client-ops-and-sync-meta-in-client-sqlite.md) — ignore it too.

## 2. Official export paths

In-app "Export graph" for DB graphs offers
([src/main/frontend/components/export.cljs](https://github.com/logseq/logseq/blob/master/src/main/frontend/components/export.cljs)):

- **SQLite copy** (`export-repo-as-sqlite-db!`) — raw db.sqlite snapshot.
- **Zip** — db.sqlite + assets zipped
  ([src/main/frontend/handler/export.cljs](https://github.com/logseq/logseq/blob/master/src/main/frontend/handler/export.cljs)).
- **EDN export** (`export-repo-as-db-edn!`) — see below.
- **Markdown export** (`export-repo-as-markdown!`) — zip of .md files; exists
  and is official, but lossy: the function carries a
  `"TODO: indent-style and remove-options"` note
  ([src/main/frontend/handler/export/text.cljs](https://github.com/logseq/logseq/blob/master/src/main/frontend/handler/export/text.cljs)),
  and markdown cannot represent DB-only constructs (typed properties as
  entities, classes/ontology, closed values, views). Not round-trippable.
- **Debug Transit export** (`export-repo-as-debug-transit!`) — raw datoms dump
  for debugging.
- **No JSON graph export** exists for DB graphs (the old file-graph JSON export
  is gone; `@logseq/cli --output json` formats query results, not a graph dump).

EDN export is the machine path. `logseq.db.sqlite.export` implements export
types `:block`, `:page`, `:graph-ontology`, `:graph`, `:graph-human`; the
docstring says ":graph is designed to be simple, reliable and for machines.
:graph-human is designed for humans to read, edit". `:graph` stamps
`::schema-version` and supports a `:datoms` graph-format (filtered `[e a v]`
triples). `:graph-human` options: `:include-timestamps?`,
`:exclude-namespaces`, `:exclude-built-in-pages?`, `:exclude-files?`.
Source:
[deps/db/src/logseq/db/sqlite/export.cljs](https://github.com/logseq/logseq/blob/master/deps/db/src/logseq/db/sqlite/export.cljs).

CLI equivalents (repo master + 2.0.1, new `logseq` CLI):
`graph export --type edn|sqlite --file <path>` (EDN accepts `--edn-options`
like `'{:export-type :graph-human :include-timestamps? true}'` and
`--pretty-print`; round-trippable via `graph import --type edn`)
([docs/cli/logseq-cli.md](https://github.com/logseq/logseq/blob/master/docs/cli/logseq-cli.md)).
The npm `@logseq/cli` (0.4.3, 2026-02-23, nbb-based, the currently published
package) has `export` (**Markdown**, local graph only), `export-edn`,
`import-edn`, `validate`
([npm @logseq/cli README](https://www.npmjs.com/package/@logseq/cli)).

## 3. Reading a DB graph outside Logseq

- **`@logseq/cli`** (npm, latest 0.4.3, published 2026-02-23; built on
  nbb-logseq). Commands: `list`, `show`, `search`, `query` (datalog or entity
  ids against a local graph, or simple/datalog queries against the running
  desktop app via its HTTP API server), `export` (Markdown), `export-edn`,
  `import-edn`, `append`, `mcp-server`, `validate`. Can open a graph by name
  from `~/logseq/graphs` or a raw `.sqlite` file path
  (`logseq mcp-server -g ~/Downloads/logseq_db_yep_....sqlite`). Reads
  everything (it uses deps/db + the datascript fork); local-graph writes are
  limited to `import-edn`. Source:
  [npm @logseq/cli README](https://www.npmjs.com/package/@logseq/cli).
  Note: the repo master replaced the nbb CLI with a new private OCaml/Melange
  `cli/` runtime (binary `logseq`, talks to a `db-worker-node` daemon; far
  richer: `list page/tag/property/task/node/asset`, `upsert *`, `move`,
  `remove`, `query`, `show`, `graph export/import/backup`, `sync *`, plus a
  built-in agent skill via `logseq skill show`) —
  [docs/cli/logseq-cli.md](https://github.com/logseq/logseq/blob/master/docs/cli/logseq-cli.md),
  [cli/package.json](https://github.com/logseq/logseq/blob/master/cli/package.json)
  (`"name": "logseq-cli", "private": true`). Expect the published package to
  switch to this at/after 2.0 stable.
- **nbb-logseq** (https://github.com/logseq/nbb-logseq): nbb (Node CLJS
  scripting) bundled with datascript + datascript-transit; Logseq's `deps/db`
  is explicitly "compatible ... with nbb-logseq to provide ... commandline
  functionality"
  ([deps/db/README.md](https://github.com/logseq/logseq/blob/master/deps/db/README.md)).
  The turnkey reader is
  `logseq.db.common.sqlite-cli/open-db!` (better-sqlite3 → datascript conn via
  `d/restore-conn`) in
  [deps/db/src/logseq/db/common/sqlite_cli.cljs](https://github.com/logseq/logseq/blob/master/deps/db/src/logseq/db/common/sqlite_cli.cljs).
  This gives full datalog access to any (non-live) db.sqlite.
- **Plain JS**: `transit-js` + datascript-transit handlers can decode
  individual `kvs.content` strings (the new CLI itself depends on `transit-js`),
  but reconstructing the database means reimplementing the fork's
  persistent-sorted-set node walk — doable (walk from addr 0 roots via the
  `addresses` column) but coupled to fork internals.
- **Rust/Python**: no reader of the kvs/transit format found in official
  sources or the ecosystem as of 2026-08; community tools (e.g.
  [kerim/logseq-http-server](https://github.com/kerim/logseq-http-server),
  Python) wrap `@logseq/cli` or the desktop HTTP API rather than parse the
  SQLite. A from-scratch reader must implement: transit-JSON, datascript-fork
  storage-node layout, and the 65.x attribute semantics.
- **Desktop HTTP API server**: the in-app graph is queryable over the local
  HTTP API (token-gated), used by `@logseq/cli -a` and MCP
  ([npm @logseq/cli README](https://www.npmjs.com/package/@logseq/cli)).

## 4. Format stability / versioning

- Version marker inside the graph: entity `:logseq.kv/schema-version` with
  `:kv/value {:major M :minor m}`; also `:logseq.kv/graph-initial-schema-version`,
  `:logseq.kv/db-type "db"`, `:logseq.kv/graph-created-by-commit` (kv-pair
  convention: `sqlite-util/kv` in
  [deps/db/src/logseq/db/sqlite/util.cljs](https://github.com/logseq/logseq/blob/master/deps/db/src/logseq/db/sqlite/util.cljs);
  values visible in the CLI `show` example on the
  [npm README](https://www.npmjs.com/package/@logseq/cli)).
- Current version: `(def version (parse-schema-version "65.33"))` in
  [deps/db/src/logseq/db/frontend/schema.cljs](https://github.com/logseq/logseq/blob/master/deps/db/src/logseq/db/frontend/schema.cljs).
- Migration mechanism: `schema-version->updates` in
  [src/main/frontend/worker/db/migrate.cljs](https://github.com/logseq/logseq/blob/master/src/main/frontend/worker/db/migrate.cljs)
  — an ordered vector of `["65.x" {:properties [...] :classes [...] :fix fn}]`
  tuples replayed on open when the stored version is older; each release that
  touches the model bumps `db-schema/version`.
- Churn rate: 65.7 was current in Jul 2025 (npm CLI example) and 65.33 in
  Aug 2026 — 26 minor migrations in ~13 months, i.e. roughly monthly. The
  major has stayed at 65 through the beta, but nothing prevents a major bump
  at 2.0 stable. The new CLI additionally refuses to talk to a `db-worker-node`
  whose revision string differs from its own (docs/cli/logseq-cli.md,
  "revision mismatch") — the vendor treats the layer below EDN as
  version-locked internals.
- Risk assessment for an importer: the SQLite layer couples you to (a) a
  datascript **fork's** storage-node format, (b) Logseq's transit handler set,
  and (c) 65.x attribute semantics that shift monthly. The EDN `:graph` export
  is explicitly the machine-stable surface, embeds `::schema-version`, and has
  a supported round-trip (`graph import --type edn`). Prefer: EDN export ≫
  reading via nbb-logseq/deps/db (tracks the fork for you) ≫ raw SQLite
  parsing (last resort).

## 5. DB data model vs file-based Logseq (what an importer must map)

Datascript schema (attributes) in
[deps/db/src/logseq/db/frontend/schema.cljs](https://github.com/logseq/logseq/blob/master/deps/db/src/logseq/db/frontend/schema.cljs).
Everything — pages, blocks, tags/classes, properties, property values — is a
"node" entity with `:block/uuid`.

- **Block tree**: `:block/parent` (ref) + `:block/order` (indexed string,
  fractional-indexing keys like `"a0"`, `"aF"` generated by
  `logseq/clj-fractional-indexing`;
  [deps/db/src/logseq/db/common/order.cljs](https://github.com/logseq/logseq/blob/master/deps/db/src/logseq/db/common/order.cljs)).
  Siblings sort lexicographically by `:block/order` — there is no explicit
  `:block/left` chain anymore. `:block/page` points at the containing page;
  pages have `:block/name` (lowercased) + `:block/title`.
- **Block text**: `:block/title` holds the content; internal refs are stored as
  `[[<uuid>]]` (tag refs as `#[[<uuid>]]`) and must be resolved through
  `:block/refs` / the referenced entity's title
  ([deps/db/src/logseq/db/frontend/content.cljs](https://github.com/logseq/logseq/blob/master/deps/db/src/logseq/db/frontend/content.cljs)).
  No `id::`/`property::` text lives in content — the file-graph
  properties-in-text syntax is gone.
- **Properties are first-class entities**: each property is a page-like entity
  tagged `:logseq.class/Property`, identified by a `:db/ident` (user properties
  under the `user.property` namespace — `create-user-property-ident-from-name`,
  [deps/db/src/logseq/db/frontend/property.cljs](https://github.com/logseq/logseq/blob/master/deps/db/src/logseq/db/frontend/property.cljs)),
  with `:logseq.property/type` (user types: `:default :number :date :datetime
  :checkbox :url :node :asset` —
  [deps/db/src/logseq/db/frontend/property/type.cljs](https://github.com/logseq/logseq/blob/master/deps/db/src/logseq/db/frontend/property/type.cljs))
  and `:db/cardinality`. The property's ident **is** the datascript attribute
  on the blocks that use it; ref-typed property values are themselves entities
  (property-value blocks with `:logseq.property/value`), including closed
  values. See `build-new-property` in
  [deps/db/src/logseq/db/sqlite/util.cljs](https://github.com/logseq/logseq/blob/master/deps/db/src/logseq/db/sqlite/util.cljs).
- **Classes/tags**: tags are classes. A tag entity is tagged
  `:logseq.class/Tag` and joins a hierarchy via
  `:logseq.property.class/extends` (default parent `:logseq.class/Root`).
  Blocks/pages carry classes in `:block/tags` (many, ref). Built-in classes
  include `Root, Tag, Property, Page, Journal, Whiteboard, Task, Query, Card,
  Asset, Code-block, Quote-block, Math-block, Pdf-annotation, Template,
  Comment(s)` —
  [deps/db/src/logseq/db/frontend/class.cljs](https://github.com/logseq/logseq/blob/master/deps/db/src/logseq/db/frontend/class.cljs).
  For a markdown-like tree: `#Tag` on a node ≈ membership in that class; class
  pages may define expected properties.
- **Journals**: journal pages are pages tagged `:logseq.class/Journal`
  (extends `:logseq.class/Page`) with `:block/journal-day` as an integer
  yyyyMMdd (the EDN export maps it to `:build/journal`;
  [deps/db/src/logseq/db/sqlite/export.cljs](https://github.com/logseq/logseq/blob/master/deps/db/src/logseq/db/sqlite/export.cljs),
  class def in class.cljs).
- **Tasks**: no `TODO`/`DOING` markers in text; a task is a node tagged
  `#Task` (`:logseq.class/Task`) with status/priority/scheduled/deadline as
  properties (CLI `list task --status --priority`, docs/cli/logseq-cli.md).
- **Assets**: entities tagged `:logseq.class/Asset` with type/size/checksum
  properties; the binary lives at `assets/<block-uuid>.<ext>` in the graph dir
  (docs/cli/logseq-cli.md, `upsert asset`).
- **Timestamps**: `:block/created-at` / `:block/updated-at` (epoch ms) on all
  nodes.
- **Graph-level kvs**: `:logseq.kv/*` entities (schema version, graph uuid,
  import markers) — filter them out when importing; the EDN datom export does
  ([graph-datom-export-excluded-kvs in export.cljs](https://github.com/logseq/logseq/blob/master/deps/db/src/logseq/db/sqlite/export.cljs)).

### Practical mapping recipe (EDN `:graph` export → markdown-like block tree)

Pages = `:pages-and-blocks` entries (with `:build/journal` for journals);
blocks nest as vectors ordered by `:block/order`; resolve `[[uuid]]` refs to
titles/links; flatten each node's property map (`:user.property/*`,
`:logseq.property/*`) to `key:: value` lines or frontmatter; render
`:block/tags` classes as `#Tag`; task properties → markers if desired.
Ontology comes from the export's `:classes` and `:properties` maps.

## Sources not already linked inline

- Logseq 2.0 beta announcement/release: https://github.com/logseq/logseq/releases/tag/2.0.1
- nbb-logseq README: https://github.com/logseq/nbb-logseq/blob/main/README.md
- @logseq/cli on npm (v0.4.3, 2026-02-23): https://www.npmjs.com/package/@logseq/cli
- datascript fork pin: https://github.com/logseq/logseq/blob/master/deps/db/deps.edn
