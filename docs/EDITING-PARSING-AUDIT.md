# Editing + Parsing — systemic audit

*2026-07-23 · report-only pass (no app-code changes). Harness: `test/roundtrip_audit_test.dart` — run the full sweep with `AUDIT_VAULT=1 flutter test test/roundtrip_audit_test.dart --tags audit -r expanded`.*

## Executive summary

The recent "editor does nothing" bugs (Enter-adds-blank-line `+72`, Backspace-at-boundary `+74`, paste-a-`-`-list, numbered-list renumber) are **not independent pain points — they are one systemic class.** An empirical sweep of **1,709 real vault notes + 14 synthetic edge cases** shows:

- **The serializer/parser is sound.** `parse → toSource → parse` preserves visible text on **0 of 1,709** notes. The block↔Typst mapping is a clean bijection for *well-formed documents*. **Nothing to fix here.**
- **The edit path is not.** Driving realistic block-boundary edits (Enter at block end, Backspace at block start, typing at edges) reverts **3,811 of 14,571 = 26.2%** of edits — all funnelling through **two over-strict gates** run on every keystroke.
- **Exposure is high:** **81.6%** of notes contain inline chips (image/link/ref/tag/attachment → protected `￼` nodes), so protected-adjacent editing is a common, not exotic, situation.

The `+72`/`+74` fixes were correct but were **two special cases inside a class of thousands.** The recommendation is to stop patching cases and fix the two gates so the editor **self-heals** instead of reverting.

## Method

`test/roundtrip_audit_test.dart` checks two invariants; report-only (never fails the suite).

- **Invariant 1 — serialize/parse identity:** `TyLogDocument.parse(src).visibleText == parse(toSource(…, validate:false)).visibleText`, over every note.
- **Invariant 2 — edit safety:** for each block, drive `TyLogEditingController` through Enter@block-end, Backspace@block-start, type@edges; count any `onError` (a silent revert), bucketed by `op × protected-adjacent? × error-mechanism`.

Corpus: all `.typ` under `~/Nextcloud/TyLogVault` (excl. `_system`), plus hand-built edge cases (leading-marker paragraphs, trailing/adjacent blanks, adjacent lists, task/equation/heading transitions, inline-formatting). Sanity: the harness re-catches the `+72`/`+74` shapes.

## Findings

### Invariant 1 — serialize/parse identity: **0 failures / 1,709**
The serializer (`_serializeBlock`/`_serializePart`/`_escapeParagraphMarkers`, `rich_editor.dart`) and parser (`parseControlledTypst`, `controlled_editor.dart`) agree on all existing notes. The historical belief that "serialization is lossy" is **false for committed documents** — losses only appear in *transient edit states*.

### Invariant 2 — edit safety: **26.2% revert (3,811 / 14,571)**

| # | Operation | Position | Mechanism | Count | Meaning |
|---|-----------|----------|-----------|------:|---------|
| 1 | **enter** | plain boundary | validate-fail | **2,938** | Enter at a block end (heading↔paragraph, para↔para, …) → `toSource` reparse ≠ visibleText → revert. |
| 2 | **backspace** | plain boundary | crossed-protected | **518** | Backspace at a block start (deletes the separator) no-ops → mismatch → mis-fires the protected guard. |
| 3 | **enter** | next to `￼` chip | validate-fail | **165** | Enter right after a paragraph ending in an image/link/ref chip → revert. |
| 4 | **type** | plain boundary | validate-fail | **101** | Typing before a list glyph (`•`/`N.`) → the char lands outside the item → revert. |
| 5 | **backspace** | next to `￼` chip | crossed-protected | **63** | Backspace adjacent to a chip → guard fires. |
| 6 | **backspace** | plain boundary | validate-fail | **26** | A few plain-boundary backspaces still fail the round-trip. |

**Two mechanisms account for everything:**
- **validate-fail (~85%, classes 1/3/4/6):** the round-trip self-validation in `TyLogDocument.toSource` (`rich_editor.dart:962`, `FormatException('Rich editor could not validate Typst output.')`) reverts on *any* `visibleText` mismatch — including **benign normalizations** the parser would happily accept (a collapsed trailing newline, a canonical block split). `+72` (persistedVisible trailing-`\n` strip) and `+74` (`mergeBackward`) each carved out one benign case; the rest still revert.
- **crossed-protected (~15%, classes 2/5):** the guard at `rich_editor.dart:1219` (`FormatException('Edit crossed a protected Typst node.')`) triggers whenever `document.visibleText != next.text` after a `replace` — but a **boundary edit that no-ops the model** (e.g. deleting an inter-block separator that no block owns) produces exactly that mismatch **without touching any protected node.** It's a false positive.

### Track B — metadata scanner (parsing the note header)
From `scanner.dart`/`validation.dart` and the in-app Problems screen: notes fall back from the Typst-**query** path to **regex** parsing (`metadataSource:'fallback'`, "safe fallback scanner") and legacy notes lack a managed `#show: tylog.note.with(...)` header ("legacy parsing"). These are a *separate, lower-acuity* surface (they degrade metadata richness, they don't silently eat edits). The `+73` "Convert" fixer + entity-kind recognition already address the user-facing warnings; the residual risk is the query path's fragility (see Track C). Not the cause of the editing pain.

### Track C — Typst compile/query + imports
The managed pipeline assumes each note carries `#import "/_system/tylog.typ" as tylog` + the `tylog.note.with` header (`_noteSource`). Hand-authored / imported `.typ` break that assumption (the `+73` device-test "convert added a header but no import" bug was one instance; fixed in `replaceNoteHeader`). The query→fallback decision is where "unverified-note-metadata (info)" comes from. Robustness here is a Track-B follow-up, independent of the round-trip fix.

## Root-cause analysis

The editor keeps a block model and, on **every** edit, (a) serializes to Typst, (b) reparses, (c) compares. It then **reverts on the slightest disagreement** and **guards protected nodes by raw text comparison.** Both gates conflate *"the document changed in a way the round-trip normalizes"* (benign — should be accepted) with *"the edit corrupted or dropped content"* (real — should be rejected). Because the model's *transient* edit states (trailing newlines, empty separators, caret-before-glyph, chip-adjacent carets) are legion, ~1 in 4 boundary edits trips a benign disagreement and is thrown away. The serializer being a perfect bijection on committed docs (Invariant 1) is precisely why **the fix belongs in the validation/guard policy, not the serializer.**

## Remediation roadmap

### Option 1 — *accept-and-resync* validation (recommended, root-cause)
Change the two gates from **revert** to **self-heal**:
1. In `toSource`/`_handleValue`: when the post-edit source **reparses to a document that preserves (i) every protected node's source (`_sameProtectedSources`) and (ii) the visible content modulo whitespace/block-structure normalization**, *adopt the reparsed document* (a caret-preserving variant of `loadSource`) instead of throwing. Revert **only** on genuine loss (protected node gone, or non-whitespace content dropped).
2. Scope the crossed-protected guard (`:1219`) to fire **only when a protected node's source is actually lost**, never on a bare `visibleText` length mismatch.
- **Kills classes 1, 3, 4, 6 (validate-fail, ~85%) and 2, 5 (crossed-protected, ~15%) together.** `+72`/`+74` become redundant fast-paths.
- **Effort:** medium (one focused change in the commit/validate path + a caret-preserving resync). **Risk:** medium — must nail the "benign vs corrupting" predicate; the harness is the safety net (drive to **0%** revert on the corpus while keeping protected-loss cases rejected).

### Option 2 — canonical bijection (broader, case-by-case)
Make the block model represent empty paragraphs / trailing newlines / separators unambiguously and canonicalize on edit so serialize∘parse is identity on *transient* states too. Principled but touches the model core and every mutation; higher risk, slower. Prefer Option 1 first; adopt pieces of this only where resync can't preserve intent.

### Option 3 — scanner robustness (Track B/C, independent)
Reduce reliance on the fragile Typst-query path and make header/import assumptions self-repairing on load. Separate workstream; schedule after the editing fix.

### Suggested sequencing
1. **Option 1** behind the harness (target: boundary-edit revert rate 26.2% → ~0%, protected-loss still rejected). Ship as a release.
2. Keep `test/roundtrip_audit_test.dart` as a **permanent regression gate** (add `--tags audit` sweep to `make verify`).
3. Track B/C robustness as a follow-up.

## Regression net
`test/roundtrip_audit_test.dart` stays in the tree. Default `flutter test` runs only the fast synthetic checks; the full vault sweep is opt-in via `AUDIT_VAULT=1 … --tags audit`. Post-fix, the same harness proves the class is closed and guards against re-introduction.

## Appendix — reproductions (minimal, runnable via the harness synthetic corpus)
- validate-fail (Enter): `= Title\n\nbody`, Enter at end of the heading.
- validate-fail (Enter, chip): `…text ending in #link(...)[x]\n\n￼\n\nmore`, Enter after the chip paragraph.
- crossed-protected (Backspace): `= Title\n\nbody`, Backspace at the start of `body`.
- type-before-glyph: `- a\n- b`, type `x` at offset 0.
