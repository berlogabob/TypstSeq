#import "lib.typ": *

#show: report.with((
  title: "Logseq DB-Version Import",
  subtitle: "Implementation plan — stakeholder brief",
  footer: "TyLog — Logseq DB-version import plan",
  lang: "en",
))

#title-block(
  "Logseq DB-Version Import",
  subtitle: "Implementation plan — stakeholder brief",
  standfirst: [*Decision:* import Logseq 2.0 "DB version" graphs via the official EDN `:graph` export only — never raw `db.sqlite` — then transpile the parsed graph to synthetic Logseq-file markdown and feed it through the existing, tested file-import pipeline unchanged.],
  meta-line: [Plan: `docs/superpowers/plans/2026-08-20-logseq-db-import.md` · Spec: `docs/research-logseq-db-format.md` · 2026-08-20],
)

#kpi-row((
  ("6", "phases planned", "0 in progress"),
  ("1", "new rust dep", "EDN parser crate"),
  ("0", "new dart deps", "reuses FFI bridge"),
  ("65", "schema major gate", "≠ 65 rejected"),
))

== Executive summary

- *Decision:* consume the official EDN `:graph` export only. Transpile each page to synthetic Logseq-file markdown (`key:: value`, `- TODO [#A]`, `[[Title]]`, `journals/YYYY_MM_DD.md`) and feed the existing `VaultDialect::Logseq` pipeline — new code is the EDN reader and transpiler, nothing else.
- *Why:* `db.sqlite`'s `kvs` table stores transit-JSON-encoded index-tree nodes of a *forked* datascript — not queryable by SQL, and coupled to Logseq's fork internals. The EDN export is schema-version-stamped and explicitly built as the machine-stable surface, against roughly monthly schema churn (65.7 → 65.33: 26 minor bumps in 13 months).
- *Scope:* exactly one new Rust dependency (the EDN parser), zero new Dart dependencies. Parsing, Typst assembly, dedupe, and the import UI are all reused as-is.
- *Status:* all 6 phases are planned; none started. Each phase carries one measurable exit metric — see the scorecard below.
- *Key risk:* the transpiler's whole fixture rests on inferred EDN key names. Phase 0 requires a ground-truth diff against one real export before any later phase builds on it.

== Why EDN, never SQLite

#fact("Storage layer", [`kvs (addr, content, addresses)` — `content` is a transit-JSON-encoded datascript index-tree node, not a row-per-datom table; not usefully queryable with plain SQL.])
#fact("Fork risk", [Logseq pins a *fork* of datascript plus custom transit handlers (`Entity`, `ExceptionInfo`, `js/Error`). Upstream datascript's storage is not guaranteed byte-compatible.])
#fact("Schema churn", [Schema `65.7` (Jul 2025) → `65.33` (Aug 2026): 26 minor migrations in about 13 months, roughly monthly. Major has held at 65 through the beta.])
#fact("Machine surface", [EDN `:graph` export: schema-version-stamped, documented as "designed to be simple, reliable and for machines," with a supported round-trip (`graph import --type edn`).])

#v(0.3em)
#callout(tone: "info", title: "Vendor's own stability ranking")[
  EDN export ≫ reading via `nbb-logseq`/`deps/db` (tracks the fork) ≫ raw SQLite parsing (last resort). The plan couples to the first tier only.
]

== Phase plan

#data-table(
  ([Phase], [Exit metric], [Status]),
  (
    (
      [*0.* Fixture \& ground truth],
      [Fixture parses; every construct — journal, task, typed property, class tag, uuid ref, asset — present exactly once and asserted.],
      pill("Planned", tone: "neutral"),
    ),
    (
      [*1.* EDN graph model],
      [Fixture + one real export load with 0 errors; a wrong-major export is rejected with a named error.],
      pill("Planned", tone: "neutral"),
    ),
    (
      [*2.* Transpiler],
      [100% of fixture blocks appear in output; flatten counters match a hand-count; snapshot test green.],
      pill("Planned", tone: "neutral"),
    ),
    (
      [*3.* Pipeline wiring],
      [`convert_db_export()` runs end-to-end with uuid-based note IDs; all emitted notes `typst compile` clean.],
      pill("Planned", tone: "neutral"),
    ),
    (
      [*4.* App integration],
      [UI import of the fixture graph succeeds on macOS; assets resolve.],
      pill("Planned", tone: "neutral"),
    ),
    (
      [*5.* Real-graph trial \& release],
      [0 compile failures; 0 unexplained duplicate ids; dropped-construct report written.],
      pill("Planned", tone: "neutral"),
    ),
  ),
  widths: (5.8cm, 8.4cm, 2.4cm),
)

== Key risks

#callout(tone: "warn", title: "EDN key-shape drift")[
  The Phase-0 fixture is hand-written against key names *inferred* from source reading (`:pages-and-blocks`, `:build/children`, `:build/properties`, `:build/tags`, `:build/journal`, status/priority idents). Task 1 Step 2 requires diffing those against one real `export-edn` output before Task 2 starts — the fixture is the contract every later phase builds on, so this check is not optional.
]

#callout(tone: "info", title: "Lossy flattening is counted, not silent")[
  Typed property values, closed values, the class/property ontology, and DB-only views cannot round-trip to file-Logseq markdown. Global constraint: every lossy flattening increments a counter surfaced in the import report — never a silent drop.
]

== Deliberate non-goals

- Reading `db.sqlite`/`kvs` directly — blocked by the global constraints; revisit only if Logseq drops the EDN export.
- Importing the class/property ontology as TyLog structure — counted, not modeled; add later if users ask.
- Live sync with a running Logseq 2.0 app over its HTTP API — out of scope; import is one-shot.
- `search-db.sqlite`, `client-ops-db.sqlite` — derived/sync data, ignored by design.
