# Logseq DB-Version Import Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** TyLog imports both old file-based Logseq vaults (already shipped) and new Logseq 2.0 "DB version" graphs, via the official EDN `:graph` export.

**Architecture:** A DB graph's SQLite layer is transit-JSON index-tree nodes of a *forked* datascript with ~monthly schema churn — we never read `db.sqlite`. Instead we consume the official, machine-oriented, schema-version-stamped EDN export. A new `db_import` module in `tylog_import_core` parses the EDN into a small graph model and **transpiles each page to synthetic Logseq-file markdown** (`key:: value` properties, `- TODO [#A]` tasks, `[[Title]]` refs, `journals/YYYY_MM_DD.md`), then feeds the existing `VaultDialect::Logseq` pipeline unchanged. New code = EDN reader + transpiler; parsing, Typst assembly, dedupe, and UI flow are all reused.

<!-- ponytail: transpile-to-markdown reuses the tested file pipeline; upgrade path if reparse-fidelity bugs accumulate is a direct third preprocess() producing `Preprocessed` (vault_import.rs:54). -->

**Tech Stack:** Rust (`tylog_import_core`, one new EDN-parser crate), flutter_rust_bridge FFI (`typst_flutter`), Dart UI flow (`lib/app_mobile/vault_import_flow.dart`), typst CLI 0.15.1 for compile-validation.

**Spec:** `docs/research-logseq-db-format.md` (EDN export shape, schema versioning, data-model deltas) + the pipeline map in this plan's Phase overview. The plan argues from that research doc; executors read both.

## Global Constraints

- NEVER parse `db.sqlite`/`kvs` directly — EDN export only (spec §1, §4).
- Input is the `:graph`-type EDN export (in-app "Export EDN" or `logseq graph export --type edn` / `@logseq/cli export-edn`).
- Gate on schema version: refuse major ≠ 65 with a clear error; warn (don't fail) on minor > the tested one.
- Every writer change is validated by **compiling** emitted Typst (`typst compile`), never by parse-only round-trip (repo rule: scanNote reads malformed Typst back as valid).
- Note IDs for DB pages come from `:block/uuid`, not FNV1a path hashes (avoids the known 59-dup-id debt class).
- Exactly one new Rust dependency (the EDN parser). No new Dart dependencies.
- Every lossy flattening (typed property values, closed values, class ontology, views) increments a counter surfaced in the import report — no silent drops.

## Phase overview (trackable / measurable)

| Phase | Deliverable | Exit metric |
|---|---|---|
| 0. Fixture & ground truth | Checked-in EDN export fixture covering journal, task, typed property, class tag, uuid ref, asset | Fixture parses; every construct present exactly once and asserted |
| 1. EDN graph model | `db_import.rs`: EDN → `DbGraph{pages, properties, classes}` with schema-version gate | Fixture + a real export load with 0 errors; wrong-major export rejected with named error |
| 2. Transpiler | Page → synthetic Logseq markdown (+ flatten counters) | 100% of fixture blocks appear in output; counters match hand-count; snapshot test green |
| 3. Pipeline wiring | `convert_db_export()` end-to-end into existing Logseq pipeline; uuid-based note IDs | Fixture → Typst notes; **all emitted notes `typst compile` clean** |
| 4. App integration | FFI + Dart dialect detection (`.edn` file / `db.sqlite` dir hint) + asset copy | UI import of fixture graph succeeds on macOS; assets resolve |
| 5. Real-graph trial & release | CLI `--db-edn` mode, real DB-graph import, `tylog dedupe`, report | 0 compile failures; 0 unexplained dup-ids; dropped-construct report written |

---

### Task 1: EDN fixture and parser dependency

**Files:**
- Create: `packages/tylog_import_core/tests/fixtures/logseq_db_export.edn`
- Modify: `packages/tylog_import_core/Cargo.toml`
- Create: `packages/tylog_import_core/src/db_import.rs` (module shell + fixture-parse test)
- Modify: `packages/tylog_import_core/src/lib.rs` (add `pub mod db_import;`)

**Interfaces:**
- Produces: fixture path used by every later task; `db_import` module.

- [ ] **Step 1: Add the EDN parser crate**

Run: `cd packages/tylog_import_core && cargo add edn-format`
If the crate's API differs from the calls below, check docs.rs and adapt; fallback crate: `clojure-reader`. Pin whichever compiles in `Cargo.toml`.

- [ ] **Step 2: Author the fixture**

Hand-write `tests/fixtures/logseq_db_export.edn` mirroring the `:graph` export shape from `deps/db/src/logseq/db/sqlite/export.cljs` (see spec §2, §5). Minimal but complete — one of each construct:

```clojure
{:logseq.db.sqlite.export/schema-version {:major 65 :minor 33}
 :properties {:user.property/rating {:logseq.property/type :number}
              :user.property/source {:logseq.property/type :url}}
 :classes {:user.class/Book {:build/class-extends [:logseq.class/Root]}}
 :pages-and-blocks
 [{:page {:block/uuid #uuid "aaaaaaaa-1111-1111-1111-111111111111"
          :block/title "Reading List"
          :build/tags [:user.class/Book]
          :build/properties {:user.property/rating 5
                             :user.property/source "https://example.org"}}
   :blocks [{:block/uuid #uuid "bbbbbbbb-2222-2222-2222-222222222222"
             :block/title "Top block with a ref to [[cccccccc-3333-3333-3333-333333333333]]"
             :build/children
             [{:block/uuid #uuid "dddddddd-4444-4444-4444-444444444444"
               :block/title "Nested child"}]}
            {:block/uuid #uuid "eeeeeeee-5555-5555-5555-555555555555"
             :block/title "Buy the book"
             :build/tags [:logseq.class/Task]
             :build/properties {:logseq.property/status :logseq.property/status.doing
                                :logseq.property/priority :logseq.property/priority.high}}]}
  {:page {:block/uuid #uuid "cccccccc-3333-3333-3333-333333333333"
          :block/title "Aug 20th, 2026"
          :build/journal 20260820}
   :blocks [{:block/uuid #uuid "ffffffff-6666-6666-6666-666666666666"
             :block/title "Journal entry with asset ![scan](../assets/abcd1234.png)"}]}]}
```

IMPORTANT — ground-truth check (this is the whole point of Phase 0): before or immediately after writing the fixture, produce ONE real export (`npx @logseq/cli export-edn` on any throwaway DB graph, or in-app Export EDN) and diff the key names (`:pages-and-blocks`, `:build/children`, `:build/properties`, `:build/tags`, `:build/journal`, status/priority idents, the exact schema-version key). Fix the fixture to match reality; the fixture is the contract for every later task. Record the verified real export at `tests/fixtures/README.md` with the Logseq version used.

- [ ] **Step 3: Write the failing parse test**

In `src/db_import.rs`:

```rust
#[cfg(test)]
mod tests {
    #[test]
    fn fixture_parses_as_edn() {
        let src = include_str!("../tests/fixtures/logseq_db_export.edn");
        let value = edn_format::parse_str(src).expect("fixture must be valid EDN");
        // top level is a map containing :pages-and-blocks
        let map = match value { edn_format::Value::Map(m) => m, other => panic!("expected map, got {other:?}") };
        assert!(map.keys().any(|k| format!("{k:?}").contains("pages-and-blocks")));
    }
}
```

- [ ] **Step 4: Run to verify it fails** — `cargo test -p tylog_import_core fixture_parses` → FAIL (module/fixture missing), then wire `pub mod db_import;` in lib.rs and re-run → PASS.

- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat(db-import): EDN fixture + parser dependency for Logseq DB graphs"`

---

### Task 2: Graph model with schema gate

**Files:**
- Modify: `packages/tylog_import_core/src/db_import.rs`

**Interfaces:**
- Produces: `pub struct DbGraph { pub pages: Vec<DbPage>, pub schema_minor: u32 }`, `pub struct DbPage { pub uuid: String, pub title: String, pub journal_day: Option<u32>, pub tags: Vec<String>, pub properties: Vec<(String, String)>, pub blocks: Vec<DbBlock> }`, `pub struct DbBlock { pub uuid: String, pub title: String, pub tags: Vec<String>, pub properties: Vec<(String, String)>, pub children: Vec<DbBlock> }`, `pub fn parse_db_export(edn: &str) -> Result<DbGraph, DbImportError>`.
- `DbImportError` variants: `Edn(String)`, `UnsupportedSchemaMajor(u32)`, `MissingKey(&'static str)`.

- [ ] **Step 1: Write failing tests**

```rust
#[test]
fn parses_fixture_into_graph_model() {
    let g = parse_db_export(include_str!("../tests/fixtures/logseq_db_export.edn")).unwrap();
    assert_eq!(g.pages.len(), 2);
    let reading = g.pages.iter().find(|p| p.title == "Reading List").unwrap();
    assert_eq!(reading.blocks.len(), 2);
    assert_eq!(reading.blocks[0].children.len(), 1);
    assert!(reading.properties.iter().any(|(k, v)| k == "rating" && v == "5"));
    let journal = g.pages.iter().find(|p| p.journal_day == Some(20260820)).unwrap();
    assert_eq!(journal.blocks.len(), 1);
}

#[test]
fn rejects_unknown_schema_major() {
    let src = include_str!("../tests/fixtures/logseq_db_export.edn").replace(":major 65", ":major 66");
    assert!(matches!(parse_db_export(&src), Err(DbImportError::UnsupportedSchemaMajor(66))));
}
```

- [ ] **Step 2: Run to verify FAIL** — `cargo test -p tylog_import_core db_import` → compile error (types missing).

- [ ] **Step 3: Implement `parse_db_export`**

Walk the EDN value: read schema-version map first (error `UnsupportedSchemaMajor` if major ≠ 65; keep `schema_minor` for the report). Then map each `:pages-and-blocks` entry: `:page` → uuid (render the `#uuid` tagged value to its string), title, optional `:build/journal` int, tags (keyword idents → their trailing name segment, e.g. `:user.class/Book` → `"Book"`), properties (`:build/properties` map → `(trailing-name, value rendered to string)`; keyword values like `:logseq.property/status.doing` render to their trailing segment `"doing"`). `:blocks` recurse via `:build/children`. Helper `fn kw_name(k) -> String` and `fn value_to_string(v) -> String` centralize keyword/uuid/number/string rendering. No `:block/order` handling — the export already nests children in order (spec §5 recipe); assert nothing about order keys.

- [ ] **Step 4: Run to verify PASS** — `cargo test -p tylog_import_core db_import` → 3 passed.

- [ ] **Step 5: Commit** — `git commit -am "feat(db-import): parse EDN :graph export into DbGraph model with schema gate"`

---

### Task 3: Transpiler — DbPage → synthetic Logseq markdown

**Files:**
- Modify: `packages/tylog_import_core/src/db_import.rs`

**Interfaces:**
- Consumes: `DbGraph`/`DbPage`/`DbBlock` from Task 2.
- Produces: `pub struct SyntheticFile { pub rel_path: String, pub markdown: String, pub page_uuid: String }`, `pub struct TranspileStats { pub flattened_typed_values: usize, pub dropped_ontology_entries: usize }`, `pub fn transpile(graph: &DbGraph) -> (Vec<SyntheticFile>, TranspileStats)`.

**Mapping rules (the heart of the feature):**
- Page path: journal pages → `journals/YYYY_MM_DD.md` from `journal_day`; others → `pages/<sanitized title>.md`.
- Page properties → `key:: value` head lines (existing Logseq preprocess consumes these; noise keys are already filtered downstream).
- Page tags → a `tags:: #A #B` head line (matches the existing tag-clustering parser).
- Blocks → `- ` bullets, children indented with a tab per level; multi-line block titles: continuation lines indented under the bullet (Logseq file convention).
- `[[<uuid>]]` / `#[[<uuid>]]` inside titles → `[[<page title>]]` / `#[[<title>]]` via a uuid→title map built over all pages AND blocks; unresolvable uuids → keep literal text `[[missing:<uuid8>]]` and count.
- Task blocks (tag `Task`) → `- <STATUS> [#<P>] <title>`: status map `todo→TODO, doing→NOW, done→DONE, later→LATER, waiting→WAITING, canceled→CANCELED` (default TODO); priority `high→A, medium→B, low→C`; scheduled/deadline properties → `SCHEDULED: <...>`/`DEADLINE: <...>` continuation lines in org date format `<YYYY-MM-DD>`.
- Non-task block properties → appended `key:: value` lines under the bullet.
- Every property whose EDN value was a ref/entity (not a scalar) is rendered via `value_to_string` and increments `flattened_typed_values`; `:classes`/`:properties` ontology maps are not emitted as pages (count size into `dropped_ontology_entries`).

- [ ] **Step 1: Write failing snapshot-style test**

```rust
#[test]
fn transpiles_fixture_to_logseq_markdown() {
    let g = parse_db_export(include_str!("../tests/fixtures/logseq_db_export.edn")).unwrap();
    let (files, stats) = transpile(&g);
    assert_eq!(files.len(), 2);
    let page = files.iter().find(|f| f.rel_path == "pages/Reading List.md").unwrap();
    assert!(page.markdown.starts_with("rating:: 5\n"));
    assert!(page.markdown.contains("tags:: #Book"));
    assert!(page.markdown.contains("ref to [[Aug 20th, 2026]]"));   // uuid resolved
    assert!(page.markdown.contains("- NOW [#A] Buy the book"));      // task mapping
    assert!(page.markdown.contains("\n\t- Nested child"));           // child indent
    let journal = files.iter().find(|f| f.rel_path == "journals/2026_08_20.md").unwrap();
    assert!(journal.markdown.contains("../assets/abcd1234.png"));
    assert_eq!(stats.flattened_typed_values, 0);
}
```

- [ ] **Step 2: Run to verify FAIL**, **Step 3: implement `transpile` per the rules above**, **Step 4: run to PASS** — `cargo test -p tylog_import_core transpiles`.

- [ ] **Step 5: Commit** — `git commit -am "feat(db-import): transpile DB pages to synthetic Logseq markdown"`

---

### Task 4: End-to-end conversion with uuid note IDs + compile validation

**Files:**
- Modify: `packages/tylog_import_core/src/db_import.rs` (add `convert_db_export`)
- Modify: `packages/tylog_import_core/src/vault_import.rs` (accept explicit note-id override)

**Interfaces:**
- Consumes: `transpile()` (Task 3); existing `convert_vault_note`-equivalent internal fn for `VaultDialect::Logseq`.
- Produces: `pub struct DbConvertedNote { pub rel_typst_path: String, pub typst_source: String, pub note_id: String, pub diagnostics: Vec<String> }`, `pub fn convert_db_export(edn: &str) -> Result<(Vec<DbConvertedNote>, TranspileStats), DbImportError>`.

- [ ] **Step 1: Add an explicit-id override to the existing converter.** In `vault_import.rs`, the Logseq path derives `NoteMeta.id` from FNV1a(source path) or journal date. Add `pub id_override: Option<String>` to the conversion options struct (or a new parameter threaded to `NoteMeta` assembly, vault_import.rs:1362–1401 region); when set, it wins over FNV1a. Journals keep date ids (so daily notes merge with existing ones instead of duplicating). Failing test first:

```rust
#[test]
fn id_override_wins_over_path_hash() {
    let note = convert_logseq_with_id("pages/X.md", "- hello", Some("aaaaaaaa11111111".into()));
    assert!(note.typst_source.contains("id: \"aaaaaaaa11111111\""));
}
```

- [ ] **Step 2: Implement `convert_db_export`** — parse → transpile → for each `SyntheticFile`, run the existing Logseq conversion with `id_override = Some(page_uuid without dashes, truncated to the id-format the vault uses)` for pages, `None` for journals. Collect diagnostics + stats.

- [ ] **Step 3: Compile-validation test (repo rule: writers must compile, not parse).**

```rust
#[test]
fn all_db_converted_notes_compile() {
    let (notes, _) = convert_db_export(include_str!("../tests/fixtures/logseq_db_export.edn")).unwrap();
    assert!(!notes.is_empty());
    for n in &notes {
        compile_in_stub_vault(&n.rel_typst_path, &n.typst_source); // helper: temp dir + minimal /_system/tylog.typ stub + `typst compile`
    }
}
```

If a compile-helper already exists in the repo's test utilities, reuse it; otherwise write `compile_in_stub_vault` once here (temp dir, write a minimal `_system/tylog.typ` stub that accepts `tylog.note.with(..)`/`tylog.task(..)`/`tylog.ref-note(..)`, shell out to `typst compile --root`). Verify this test FAILS when you corrupt the assembler output (e.g. temporarily emit an unclosed `#tylog.task(`) — a compile test that can't fail is worthless.

- [ ] **Step 4: Run full crate tests** — `cargo test -p tylog_import_core` → all green.

- [ ] **Step 5: Commit** — `git commit -am "feat(db-import): end-to-end DB-export conversion with uuid ids + typst compile validation"`

---

### Task 5: FFI + Dart wiring

**Files:**
- Modify: `packages/typst_flutter/rust/src/api/vault_import.rs` (expose `convert_db_export`)
- Modify: `packages/typst_flutter/lib/src/vault_import.dart` (Dart wrapper)
- Modify: `lib/app_mobile/vault_import_flow.dart` (dialect detection + flow)
- Test: `test/vault_import_flow_db_test.dart`

**Interfaces:**
- Consumes: `convert_db_export` (Task 4).
- Produces: Dart `Future<DbImportResult> convertDbExport(String ednSource)` where `DbImportResult { List<DbNote> notes; int flattenedTypedValues; int droppedOntologyEntries; }`, `DbNote { String relPath; String source; String noteId; }`.

- [ ] **Step 1: FFI.** Mirror the existing `convert_vault_note()` wrapper style in `typst_flutter/rust/src/api/vault_import.rs`. After regenerating the bridge, **rebuild native with cargo ndk / the repo's build script — never `dart run typst_flutter:setup`** (repo rule: that downloads upstream's .so and drops local Rust changes; a "content hash Dart vs Rust out of sync" error afterward means a stale .so).

- [ ] **Step 2: Dialect detection.** In `detectVaultDialect()` (vault_import_flow.dart:42–50): a picked *file* ending in `.edn` → `VaultDialect.logseqDb`; a picked *directory* containing `db.sqlite` → show an instruction dialog: "This is a Logseq DB graph. In Logseq: ⋯ → Export graph → EDN, then pick the exported .edn file here" (do NOT attempt to read the sqlite). Failing widget/unit test first in `test/vault_import_flow_db_test.dart` covering both detections.

- [ ] **Step 3: Import flow.** For `logseqDb`, replace the per-file loop (vault_import_flow.dart:151–155) with one `convertDbExport(ednText)` call, then write each returned note through the same note-writing path the file dialects use. Asset copy: if the picked `.edn` sits next to an `assets/` dir (or the user's graph dir at `~/logseq/graphs/<name>/assets/` is offered via a second picker), copy referenced `../assets/*` files exactly like the existing Logseq asset copy (vault_import_flow.dart:69–254). Surface `flattenedTypedValues`/`droppedOntologyEntries` in the completion summary alongside the existing dropped-block-refs counter.

- [ ] **Step 4: Run** — `flutter test test/vault_import_flow_db_test.dart` → PASS; then manual macOS run: import the fixture EDN via the UI, confirm notes appear and compile.

- [ ] **Step 5: Commit** — `git commit -am "feat(db-import): app wiring — .edn dialect detection, FFI, import flow + counters"`

---

### Task 6: Real-graph trial, dedupe, report

**Files:**
- Modify: `packages/tylog_import_core/src/bin/logseq_import.rs` (add `--db-edn <file>` mode)
- Create: `docs/db-import-trial-report.md`

- [ ] **Step 1: CLI mode.** `logseq_import --db-edn export.edn --out <dir>` writes the converted vault to disk using `convert_db_export`. One assert-based smoke test or `--db-edn` run on the fixture in CI.

- [ ] **Step 2: Real trial.** Create a non-trivial DB graph in Logseq 2.0.1 (or migrate a copy of a file graph with Logseq's own converter to get realistic volume), export EDN, run the CLI. Measure and record: pages/blocks/tasks converted, unresolved-uuid count, flattened-typed-value count, wall time.

- [ ] **Step 3: Compile + dedupe gates.** `typst compile` every emitted note against the real `_system/tylog.typ` (script the loop); run `dart run packages/tylog_core/bin/tylog.dart dedupe` over the output. Exit metric: 0 compile failures, 0 unexplained duplicate ids (journal merges with an existing vault are explained ones).

- [ ] **Step 4: Write `docs/db-import-trial-report.md`** with the measured numbers per Phase-overview metric, the verified schema version, and any constructs found in the wild that the fixture lacks (feed those back as fixture additions + tests).

- [ ] **Step 5: Commit** — `git commit -am "feat(db-import): CLI --db-edn mode + real-graph trial report"`

---

## Deliberate non-goals (say no now, cheap to add later)

- Reading `db.sqlite`/kvs directly — blocked by Global Constraints; revisit only if Logseq drops the EDN export.
- Importing the class/property ontology as TyLog structure — counted, not modeled; add if users ask.
- Live sync with a running Logseq 2.0 app (HTTP API) — out of scope; import is one-shot.
- `search-db.sqlite`, `client-ops-db.sqlite` — derived/sync data, ignored by design.

## Self-review notes

- Spec coverage: storage/no-sqlite rule → Global Constraints + Task 6 non-goal; export path → Tasks 1–4; external readers → only used for ground-truthing the fixture (Task 1 Step 2); stability → schema gate (Task 2); model deltas (properties/classes/order/journals/tasks/refs/assets) → transpiler rules (Task 3) + asset copy (Task 5).
- Type consistency: `DbGraph/DbPage/DbBlock` (Task 2) consumed by `transpile` (Task 3); `SyntheticFile`/`TranspileStats` consumed by `convert_db_export` (Task 4); `DbConvertedNote` surfaces as Dart `DbNote` (Task 5).
- Known risk pinned in Task 1: exact `:build/*` key names are verified against a real export before anything else is built — the fixture is the contract.
