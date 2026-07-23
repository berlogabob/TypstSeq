# Metadata parsing / scanner — systemic audit

*2026-07-23 · report-only pass (no app-code changes). Harness: `test/metadata_audit_test.dart` — run with `AUDIT_VAULT=1 flutter test test/metadata_audit_test.dart --tags audit -r expanded` (optional `AUDIT_STRIDE=N`). Drives the real `typst` metadata query (CLI inspector) over every note.*

## Executive summary

Contrary to the "safe fallback scanner / formatting couldn't be read" noise on the Problems screen, **the parse pipeline is healthy.** Sweeping all **1,708** real notes with the actual Typst query:

- **98.9%** (1,689) query cleanly → verified metadata (`typst-query`).
- **0.1%** (1) genuinely lack `#metadata`.
- **1.1%** (18) fail to compile — and these are the *exact* articles on your Problems screen.
- **Every query is fast: max 393 ms, 0 notes over 5 s.** The 30 s native-worker timeout never legitimately trips.

So the app's fallbacks are **not** because notes are slow or unparseable. Three real, bounded problems remain:

1. **18 markdown-import compile artifacts** (the "formatting couldn't be read" notes) — a small set of importer bugs, fully enumerable.
2. **A 98.5% properties gap** — 1,663 of 1,689 verified notes carry custom `properties` that `_fallbackNote` throws away (`properties: const {}`), so *any* fallback is badly lossy.
3. **Native single-worker fragility** — the app degrades more notes to fallback than the CLI's clean 98.9% because it shares one wedge-able Rust compiler and feeds it in-memory imports; a device sweep is needed to size this.

## Method
`test/metadata_audit_test.dart` runs `CliTypstInspector` (`typst eval query(metadata) --root <vault> --in <note>`) — same decode path (`decodeTylogMetadataRecords`) as the native inspector — over the real note roots (`daily/ notes/ projects/ articles/`), timing each and bucketing outcomes. The CLI reads from disk (all imports present), so it isolates *note/compile* health from native-worker/in-memory-file issues.

## Findings

### Distribution (1,708 notes)
| Outcome | Count | % |
|---|---:|---:|
| `typst-query` (verified, rich) | 1,689 | 98.9% |
| `fallback` (compiles, no `#metadata`) | 1 | 0.1% |
| `query-failed` (compile error) | 18 | 1.1% |

Query latency: **max 393 ms, 0 notes > 5 s** → poisoning-by-timeout does not occur for any real note; the deliberate "one timeout nulls the inspector for the pass" guard (`scanner.dart:443`) is defending against a case the corpus doesn't contain.

### Failure taxonomy — all 18 are markdown-import artifacts
| Class | ~count | Root cause | Example |
|---|---:|---|---|
| **A. inline-function field access** | ~13 | Importer emits `#emph[…]` / `#strong[…]` / `#link(…)` immediately followed by `.Word`; Typst parses `].Word` as member access → `emph does not have field "Instead"`. | `Best Claude Code…`: `#emph[confident guessing].Instead of…` |
| **B. markup inside code + unconverted tables** | ~4 | Emphasis/escape conversion runs *inside* fenced code (`r"^\s#emph[…"` injected into Python) and markdown tables aren't converted → raw `|` / `\` "not valid in code". | `machinelearningmastery.com…`, `projectmanager.com…` |
| **C. bare `@domain` ref** | 1 | A bare `20251186@iade.pt` parses as a Typst `@label` ref → `label <iade.pt> does not exist` (same class as the editor's email-autolink, but in imported text). | `daily/2026/07/2026-07-22.typ` |
| **D. plain syntax error** | ~1 | Misc. `unexpected/expected`. | `github.com - …Codebox Online fast.typ` |

These map 1:1 to the "A note's formatting couldn't be read" group. The common denominator is **`lib/markdown_article_import.dart` producing Typst that doesn't compile** — inline functions abutting `.`, emphasis conversion leaking into raw/code spans, tables/pipes untranslated, bare emails.

### Properties gap — 98.5%
1,663 of 1,689 verified notes have non-empty `properties`. `_fallbackNote` (`scanner.dart:1145`) hard-codes `properties: const {}`, so every note that falls back (from native-worker poisoning) silently loses its custom fields (entity `email`, source URL, ratings, …) until it re-queries — and re-query is capped at 50/pass.

### Native single-worker (why the app > CLI fallbacks)
`FlutterTypstInspector` shares one `TypstCompiler` (Rust FFI) across the whole scan and feeds it `input.source` + a preloaded `_inspectionFiles` map. Two app-only failure modes the disk-based CLI can't reproduce: (a) one note that wedges the compiler poisons the rest of the pass (`activeInspector = null`); (b) an import missing from `_inspectionFiles` fails a compile the CLI (real filesystem) passes. The CLI's clean 98.9% is the ceiling the app should reach.

## Remediation roadmap (prioritized by the data)

**P1 — Markdown-import correctness (prevents recurrence + clears the 18).** Fix `markdown_article_import.dart` so it emits compiling Typst: never abut an inline function with a following `.` (insert a space or escape), don't run emphasis/escape conversion inside fenced code / raw, translate `|`-tables (or fence them), and route bare emails through the existing mailto-autolink. Then a one-shot **repair pass** over the 18 existing notes, and make `metadata-query-failed` **actionable** in Problems (a "Repair"/"Convert" action reusing `+73`'s converter, surfacing the compile error from `detail`). Highest concrete value — it's the exact Problems the user sees, with a systemic root.

**P2 — Close the properties gap.** Parse `properties: (…)` from the header in `_fallbackNote` via the existing header helpers (`parseNoteProperties`/`_field`, `scanner.dart`) so a fallback note keeps its custom fields. Cheap, removes the main downside of ever falling back.

**P3 — Native-worker robustness (device-sized).** De-poison: on a wedge, skip/restart the worker instead of nulling it for the pass; ensure `_inspectionFiles` includes every transitive import; consider raising/adapting the 50/pass reinspection cap. **Confirm on the Huawei P30** whether the app's fallback count actually exceeds the CLI's ~0 — the desktop CLI can't observe the native worker, so this needs a device run before investing.

## Regression net
`test/metadata_audit_test.dart` stays in the tree (opt-in vault sweep, report-only). Re-run after P1/P2 to confirm the 18 → 0 and that fallback preserves properties; it can gain an assertion mode (like the editor harness) gating `query-failed` count and the properties gap.

## Appendix — the 18 query-failed notes
Articles: Best Claude Code Claude.md…, Building Agent Memory…, LLM собрала IndexedDB…, NVIDIA Isaac GR00T N1…, Nous Research Hermes…, Open WebUI…, docs-db-version.md…, machinelearningmastery.com – Complete Guide to Tool, projectmanager.com – Top 10 OSS PM, github.com – Codebox Online fast, Как подготовить данные…, Компьютерное зрение на коленке…, Пробуем локальные LLM…, Прогнал семь LLM…; daily/2026/07/2026-07-22.typ. (Full errors in the harness output.)
