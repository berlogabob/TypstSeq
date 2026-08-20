// PKMS competitive audit: Logseq OG vs Logseq 2.0 DB vs Tine vs TyLog.
// Source of truth: docs/audit-pkms-comparison.md
// Compile: typst compile --font-path docs/fonts --ignore-system-fonts \
//   docs/audit-pkms-comparison.typ docs/audit-pkms-comparison.pdf
#import "lib.typ": *

#show: report.with((
  title: "PKMS Competitive Audit",
  author: ("TyLog",),
  footer: "TyLog · PKMS competitive audit",
  lang: "en",
))

#title-block(
  "PKMS Competitive Audit",
  subtitle: "Logseq OG · Logseq 2.0 DB · Tine · TyLog",
  meta-line: [Prepared 2026-08-20 · synthesis + 4 research legs · 12/12 adversarial spot-checks confirmed],
  standfirst: [The Logseq ecosystem split in 2026 into three diverging worlds, and none
  occupies TyLog's ground. *Logseq OG* is officially maintenance-only and observably idle.
  *Logseq 2.0 DB* is a real data-model upgrade shipped with beta regressions and a
  one-way, desktop-only lock-in answer. *Tine* is a two-month-old solo rewrite, fast and
  file-compatible but unproven. TyLog is the only one with typed, compilable plaintext
  as its storage layer, native typeset-PDF output, and release-grade Android sync safety —
  at the cost of no block references, no query language, and no plugin ecosystem.],
)

#kpi-row((
  ("4", "Solutions compared", "OG, DB, Tine, TyLog"),
  ("16", "Feature rows scored", "matrix, next page"),
  ("12 / 12", "Spot-checked claims", "confirmed, 0 contradictions"),
  ("7", "Ranked TyLog gaps", "see closing section"),
))

#callout(
  title: "Verdict",
  tone: "info",
)[TyLog does not compete with any of the three on their own ground — outliner depth,
query power, plugin ecosystems. It competes on a different axis none of them hold:
plaintext that is simultaneously structured data and a compilable typesetting program,
paired with the field's most trustworthy mobile story. The strategic opening is real
but narrow: OG's stranded users are an import target TyLog already partly serves, and
the field's shared weak point — mobile reliability — is TyLog's strongest claim.]

#pagebreak()

#set page(flipped: true, margin: (top: 1.5cm, bottom: 1.5cm, x: 1.4cm))

== Feature matrix

#text(size: 8.5pt, fill: muted)[Legend: #text(fill: ok)[✓] full · #text(fill: warn)[◑] partial or scoped · #text(fill: bad)[✗] absent · #text(fill: muted)[⊘] deliberately out of scope. TyLog evidence = file paths in `docs/research-tylog-features.md`.]
#v(0.4em)

#data-table(
  ([Row], [Logseq OG (file)], [Logseq 2.0 DB], [Tine], [TyLog]),
  (
    ([*1 · Note model*], [✓ blocks + `key::` text props, namespaces, aliases; regex-parsed], [✓ "nodes"; typed first-class properties, classes w/ inheritance, closed values], [✓ OG model reimplemented, file-compatible], [✓ whole-note Typst files; typed-ish props, tags+synonyms, aliases]),
    ([*2 · Editor*], [✓ outliner, live-preview, KaTeX, md/org], [✓ outliner; shadcn tables/views; org-mode dropped], [✓ outliner parity + sheets/kanban, split panes], [◑ block-level edit, preview/source/split, magic actions; not an outliner]),
    ([*3 · Block refs / transclusion*], [✓ `((uuid))`, `{{embed}}`], [✓ unified `[[ ]]` refs + node embeds], [✓ `((id))`, `{{embed}}` parity], [✗ note-level refs only, by design]),
    ([*4 · Tasks & scheduling*], [✓ markers, priorities, SCHEDULED/DEADLINE, org repeaters, LOGBOOK], [✓ Task class, status history, repeater cookies], [✓ OG parity + task carry-forward], [✓ statuses/priorities/due+scheduled + RRULE recurrence, reminders, time tracking, deps]),
    ([*5 · Queries*], [✓ `{{query}}` DSL + raw Datalog], [✓ visual query builder + rewritten advanced queries + Views], [◑ common-case DSL + visual builder; no raw Datalog], [◑ saved searches + report-block filters; no query language, by design]),
    ([*6 · Graph & backlinks*], [✓ graph view, linked+unlinked refs], [✓ Graph View V2, rebuilt for performance], [✗ no graph view yet; linked/unlinked refs ✓], [✓ backlinks + 5 graph modes, community detection, LLM relink]),
    ([*7 · Search & indexing*], [◑ Datascript rebuilt from files at startup; slow at scale], [✓ fts5 trigram search-db, incremental], [✓ Rust full-text, regex syntax, search-as-workspace], [✓ worker-isolate gzipped index; roughly 17 min first index of 1,700 files on old Android hardware, then incremental]),
    ([*8 · Sync & collaboration*], [◑ paid E2EE Sync (beta) or DIY file sync; single-writer; no RTC], [◑ RTC rebuild, E2EE default; invite-gated beta], [◑ no own backend; watcher + Syncthing-conflict merge UI], [✓ Nextcloud WebDAV, ETag safety, manual conflict UI, background service; no E2EE/RTC]),
    ([*9 · Import / export*], [✓ EDN/JSON/OPML/Roam/HTML export; md corruption risk acknowledged], [◑ OG→DB migrator (lossy edges); EDN export; md export lossy by design], [◑ no import needed (same files); static HTML publish, per-page PDF], [✓ Logseq+Obsidian import shipped, DB-EDN import planned; PDF export; no HTML]),
    ([*10 · Storage & data ownership*], [✓ plain md/org files are source of truth], [✗ SQLite is source of truth; Markdown Mirror is one-way, desktop-only], [✓ byte-compatible Logseq md files], [✓ plaintext Typst files; disposable JSON indexes; every note compiles]),
    ([*11 · Plugins / extensibility*], [✓ JS plugin API + marketplace (desktop-only)], [◑ opt-in `supportsDB` (roughly 65 plugins); API bugs open; new CLI+MCP surface], [◑ own sandboxed WASM API; no Logseq-plugin compatibility], [✗ none, by design; custom kinds/properties only; external article-pipeline as producer]),
    ([*12 · Whiteboards / SRS / PDF annotation*], [✓ / ✓ / ✓ — all native], [✗ removed / ◑ reimplemented, no data migration / ◑ lossy import], [⊘ external SVG round-trip / ✗ / ✓ native, a differentiator], [⊘ / ⊘ / ✗]),
    ([*13 · Calendar / journals*], [✓ journals (docs are stubs)], [✓ journal class, natural-language date input], [✓ journals + agenda, calendar markers, templates], [✓ month grid with markers, date refs, task dues]),
    ([*14 · Platforms & mobile*], [◑ Electron + Android/iOS; officially tracked freezes, RAM evictions], [◑ desktop beta + web (OPFS); iOS invite-only, Android pre-alpha], [◑ Linux-first desktop; Android sideloaded APK; no iOS], [✓ Android release-grade, real-vault tested; macOS release; iOS dev-only]),
    ([*15 · Publishing / typesetting*], [◑ static SPA publish; no PDF], [◑ paid Sync-gated Publish at logseq.io], [◑ static HTML + per-page PDF], [✓ native Typst→PDF: typeset notes, reproducible .typ + .pdf reports, bibliography/citations, math]),
    ([*16 · License / governance / momentum*], [AGPL; maintenance-only, idle roughly 3 months], [AGPL; company-backed, nightly cadence, one tagged 2.0.x release], [AGPL; solo maintainer, no external code PRs, near-daily releases, 2 months old], [Proprietary/private; single developer, active]),
  ),
  widths: (2.7cm, 1fr, 1fr, 1fr, 1fr),
)

#set page(flipped: false, margin: (top: 2.1cm, bottom: 2.1cm, x: 2.2cm))

#pagebreak()

== How each is implemented

#let implementation-card(name, stack, body) = block(
  width: 100%,
  fill: surface,
  stroke: 0.6pt + hairline,
  radius: radius-md,
  inset: 11pt,
)[
  #text(size: 10pt, weight: 700, fill: brand)[#name]
  #h(0.45em)
  #pill(stack, tone: "neutral")
  #v(0.45em)
  #text(size: 8.35pt)[#body]
]

#grid(
  columns: (1fr, 1fr),
  gutter: 11pt,
  row-gutter: 11pt,
  implementation-card(
    "Logseq OG",
    "CLJS · Electron · mldoc · Datascript",
    [The OCaml `mldoc` parser reads Markdown/Org into an in-memory Datascript database rebuilt from files at startup. Files remain the source of truth and the database is disposable. That buys ownership and git-ability, but costs startup/scale performance, leaves `key::` properties parse-fragile, and carries an explicit corruption warning from the maintainers.],
  ),
  implementation-card(
    "Logseq 2.0 DB",
    "CLJS · SQLite · fts5 · RTC side DB",
    [Datascript now persists into SQLite: transit-encoded forked-Datascript index nodes in a `kvs` table, plus fts5 search and `client-ops` RTC stores. Typed entity properties, classes, tasks, views, and bulk operations eliminate a class of text-parse bugs; the trade is an opaque, frequently changing on-disk format, lossy Markdown export, and an ecosystem reset.],
  ),
  implementation-card(
    "Tine",
    "Rust · Tauri · WebKitGTK · SolidJS",
    [A from-scratch Rust core parses and indexes Logseq OG's exact files behind a fine-grained reactive frontend. Zero migration and byte-compatible files make it a reversible, fast bet. A solo, AI-assisted build with no external code-PR path also means plugin compatibility, graph view, SRS, and iOS are absent or explicitly out of scope.],
  ),
  implementation-card(
    "TyLog",
    "Flutter · Rust · Typst · WebDAV",
    [Plaintext Typst notes are simultaneously readable text, structured `#tylog.note/task/ref-note` calls, and compilable programs. Worker-isolate indexing, ETag-safe Nextcloud sync, and competitor importers preserve OG-class ownership while adding compile-verifiable typed fields. It intentionally stops short of DB's entity graph and closed-value model.],
  ),
)

#callout(title: "Implementation consequence", tone: "neutral")[
The systems do not merely expose different features; their storage choices set different
failure modes. OG and Tine optimize reversibility, DB optimizes entity semantics, and TyLog
optimizes compile-checked documents plus dependable mobile file sync.
]

#pagebreak()

== Pros & cons by solution

#let solution-card(name, tone, verdict, pros, cons) = block(below: 1.3em)[
  #grid(
    columns: (auto, 1fr),
    gutter: 8pt,
    align: horizon,
    text(size: 11.5pt, weight: 700, fill: ink)[#name],
    align(right, pill(verdict, tone: tone)),
  )
  #v(0.3em)
  #grid(
    columns: (1fr, 1fr),
    gutter: 14pt,
    [
      #text(size: 8pt, weight: 700, fill: ok)[PROS]
      #v(0.2em, weak: true)
      #list(..pros.map(p => [#text(size: 8.7pt)[#p]]))
    ],
    [
      #text(size: 8pt, weight: 700, fill: bad)[CONS]
      #v(0.2em, weak: true)
      #list(..cons.map(c => [#text(size: 8.7pt)[#c]]))
    ],
  )
]

#solution-card(
  "Logseq OG (file-based)",
  "bad",
  "Dead end to invest in",
  (
    [Maximal data ownership, plain files],
    [Mature full feature set: queries, whiteboards, SRS, PDF annotation, plugins],
    [Free DIY sync],
  ),
  (
    [Frozen — security-only maintenance, observably idle roughly 3 months],
    [Acknowledged corruption risk; single-writer sync],
    [Poor large-graph performance; chronically rough mobile],
  ),
)

#solution-card(
  "Logseq 2.0 DB",
  "info",
  "Future, early adopters pay",
  (
    [Best-in-field data model: typed properties, classes, closed values, views],
    [Performance at scale is a design goal],
    [Real RTC/E2EE sync substrate; company momentum (nightlies, CLI+MCP)],
  ),
  (
    [Data lock-in is structural: one-way Mirror, lossy md export, EDN needs tooling],
    [Beta regressions: whiteboards gone, SRS not migrated, plugins reset to roughly 65],
    [Mobile still invite/pre-alpha; monthly schema churn under the hood],
  ),
)

#solution-card(
  "Tine",
  "warn",
  "Promising, too young to depend on",
  (
    [Fastest architecture in the field],
    [Zero-migration Logseq-file compatibility — a reversible bet],
    [Native PDF annotation + sheets/kanban that OG lacks; high shipping velocity],
  ),
  (
    [Bus-factor-one, two months old, AI-assisted codebase, no external review path],
    [No plugin compatibility, graph view, SRS, or iOS],
    [No own sync backend],
  ),
)

#solution-card(
  "TyLog",
  "ok",
  "Differentiated, real gaps",
  (
    [Unique typeset-PDF axis: notes to publishable documents natively],
    [Strongest task engine: RRULE recurrence + reminders + time tracking],
    [Best mobile reliability posture: release-grade Android + sync-conflict safety],
    [Plaintext with verifiable structure — writers must compile; import from both Logseqs],
  ),
  (
    [No block refs/transclusion or query language — a depth ceiling for outliner power users],
    [No extensibility story; no SRS, whiteboards, or PDF annotation],
    [Single-developer, closed source — same bus-factor critique as Tine applies],
    [No E2EE sync],
  ),
)

== TyLog gaps & opportunities, ranked

+ *Ship the Logseq DB importer.* Plan already written (`docs/superpowers/plans/2026-08-20-logseq-db-import.md`). OG users are stranded and DB users fear lock-in — TyLog can be the exit for both. Cheap: the plan exists.
+ *Position on "a typeset document, not a database."* No competitor compiles a note to a publishable PDF natively. This is the only non-replicable moat in the matrix — lean on it in any public material.
+ *Query-lite, not a query language.* All three competitors have some query mechanism, but Tine proves a scoped DSL is enough for everyday use. TyLog's report blocks + saved searches cover most of it; the real gap is *inline* dynamic sections inside notes. Extend report blocks before ever considering a DSL.
+ *PDF annotation.* Tine's proven differentiator and a natural TyLog fit — the articles pipeline and reading mode already exist; annotations could be Typst data. The largest genuinely missing feature for reading-centric workflows.
+ *E2EE option for sync.* age is already in the backup design (`docs/age-encrypted-backup.md`); Logseq Sync uses age too. An age-encrypted WebDAV layer would close the one sync axis where Logseq DB leads.
+ *Block-level refs: keep saying no.* OG/Tine users expect them, but they are the single largest complexity driver in outliner codebases (UUID tracking, transclusion rendering, ref-integrity on edit). TyLog's note-level model and compile-checked writers are a deliberate simplicity moat — revisit only on real user demand.
+ *SRS/flashcards: defer.* Logseq DB broke its own users' SRS data in migration; Tine skipped it entirely. Demand signal is low.

== Graphify relationships to the codebase

#data-table(
  ([Path], [What the graph establishes], [Audit consequence]),
  (
    ([DB format → importer], [`Logseq DB-Version Graph Storage Format` → `Implementation Plan for Logseq DB EDN Importer` → `db_import` → `src/vault_import.rs` (3 hops)], [The highest-ranked gap already terminates at the shipped import boundary rather than requiring a parallel subsystem.]),
    ([Matrix → importer], [`16-Row Feature Matrix` → `Logseq DB Feature Audit` → this synthesis → DB-format research → importer plan → `db_import` → `src/vault_import.rs` (6 hops)], [Competitive evidence, storage research, delivery plan, and implementation entry point form one traceable chain.]),
    ([Opportunity links], [Query-lite connects saved searches/full-text indexing; PDF annotation connects article ingestion and reading mode; the typeset moat connects the unique TyLog comparison axis.], [Treat these as ranked product hypotheses, not extracted proof of implementation.]),
  ),
  widths: (2.6cm, 1fr, 1fr),
  right-from: none,
)

#text(size: 8pt, fill: muted)[Graphify provenance: source-document edges are EXTRACTED;
the links from opportunity nodes into code are explicitly INFERRED. The audit corpus added
105 nodes and 93 edges, including dedicated PKMS comparison communities.]

#callout(
  title: "Method note",
  tone: "neutral",
)[Research ran as independent primary-source agents across five docs, each claim cited.
A 12-claim adversarial spot-check (4 per doc) against cited URLs returned 12 of 12
confirmed, zero contradictions. TyLog rows come from code inspection, not marketing.
Known thin spots inherited from the source research: DB sync pricing has no primary
source, DB backlink-algorithm changes are undocumented, and OG journal mechanics are
covered only by stub docs.]

#pagebreak()

= Research evidence appendix

#text(size: 11pt, fill: muted)[Full source-faithful conversion of all four research legs]

This appendix keeps the complete supporting research inside the same report rather than
reducing it to a bibliography. All external links remain live. The first three legs carry
primary-source citations; the TyLog leg is codebase-derived and cites repository paths.

#data-table(
  ([Research leg], [Evidence role], [Preserved links]),
  (
    ([Logseq OG], [Maintenance posture, feature baseline, file model, mobile and sync], [44]),
    ([Logseq 2.0 DB], [Typed entity model, storage, migration, plugins, sync and beta state], [110]),
    ([Tine], [Fork architecture, parity/divergence, governance, release velocity], [13]),
    ([TyLog], [Code-derived current feature surface and implementation evidence], [Repository paths]),
  ),
  widths: (3.2cm, 1fr, 2.7cm),
  right-from: none,
)

#callout(title: "Verification gate", tone: "ok")[
Twelve claims were adversarially spot-checked against their cited URLs — four per
web-researched leg. Result: *12 confirmed, 0 contradictions*. The appendix preserves
167 live external evidence links in total; repeated citations remain repeated where the
source uses them to support separate claims.
]

#pagebreak()
#set text(size: 8.8pt)
#set par(leading: 0.64em, spacing: 1em)
#show table: set table(
  inset: (x: 5pt, y: 4pt),
  stroke: 0.35pt + hairline,
  fill: (x, y) => if y > 0 and calc.odd(y) { zebra },
)
#show table.cell: set text(size: 7.35pt, number-width: "tabular")
#include "audit-pkms-research-annexes.typ"
