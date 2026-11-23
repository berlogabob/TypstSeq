# TyLog ontology

Method: Noy & McGuinness, "Ontology Development 101". Code: `packages/tylog_core/lib/src/ontology.dart` (format in its header comment).

## Layers
- **Core** (`kCoreOntology`, ships with the app): root `thing`; person, organization, place, event, project, website, equipment under it; relation `part_of`. A domain class with no closer core parent says `is_a: thing` to be linkable.
- **Domain** (one JSON per field of application, in the vault at `_system/settings/ontology/<id>.json`, or as `ontology.json` inside a `.tylogpack`): classes that extend core through `is_a`, and slots with a value type, range, domain and cardinality. Domains: [techlab.json](techlab.json); [smartagri.json](smartagri.json), drafted from SAREF4AGRI v2.1.1 (ETSI TS 103 410-6), each class and slot carrying its source term in `same_as`. `packages/tylog_core/test/second_domain_test.dart` installs it as a pack and checks validation, the `part_of` query, linking and export with no agriculture-specific code.
- **Legacy** `_system/settings/kinds.json`: a bare class map, read as the personal domain.

Kinds stay open: a kind no document lists is still valid. Only declared slots are checked. Violations appear in the app's Problems list with code `ontology`.

## The seven steps, and where each lives
| Step | Where |
|---|---|
| 1. Scope, competency questions | below |
| 2. Reuse | mapping table below |
| 3. Terms | `CONTEXT.md`, Language |
| 4. Classes, hierarchy | `classes`, `is_a` |
| 5. Slots | `slots`, class `fields` |
| 6. Facets | slot `type`, `range`, `domain`, `max`, `values` |
| 7. Instances | entity notes in the vault |

## IADE places pack
`packages/tylog_core/tool/olt_places_pack.dart` builds a `.tylogpack` from OpenLabTwin exports: every row of `places` (rooms, cabinets, shelves, with their hierarchy as `part_of`) and every location named in the schedule. Each note carries `evidence` pointing at the rows it came from, and the pack ships the TechLAB ontology. Built 2026-11-23: 51 notes (21 rooms, 2 labs, 27 storage places, 1 building); installs, scans with no ontology problems, all 51 linkable. Not installed in any vault.

## Competency questions (TechLAB)
1 to 3 are tests in `packages/tylog_core/test/competency_questions_test.dart`; 4 and 5 are not yet tested.
1. Where is equipment X? (`location`)
2. What equipment is in lab L, including its rooms? (`pointingInto`: `location` + transitive `part_of`)
3. Which bookings use place P on day D? (`places`, `starts_at`)
4. Which people are linked to project P?
5. What evidence supports a given link? (mention file + decision row)

## Resolver
With an ontology, entities of a domain class are link targets under their core kind (a `lab` resolves as a `place`); the worker offers them to the model the same way. The type-preference rule (`EnrichMemory.preferMentionType`) is off in the app. Compare on a gold set:

    dart run bin/tylog.dart eval-links --vault V --gold G.jsonl
    dart run bin/tylog.dart eval-links --vault V --gold G.jsonl --ontology

First run, 2026-11-23, 40 sampled mentions with draft labels (13 unverified), real vault with no domain ontology installed: both arms identical (6 linked correct, 0 wrong, 11 review, 23 propose). Second run the same day on 181 draft-labelled mentions (150 more, weighted to daily notes): again identical in both arms and with or without the ledger: 47 linked correct, 1 wrong, 60 review, 73 propose (precision 0.98, coverage 0.27). The labels are drafts; 32 of them come from links already written in the notes, which makes those rows easy. A verified gold set and a vault that uses a domain are needed before any claim.

## Export
    dart run bin/tylog.dart export-domain --vault V --id techlab --out DIR

Writes the domain document, `instances.jsonl`, `decisions.jsonl` (ledger rows about those instances, the examples for a small model) and `techlab.ttl` (OWL in Turtle; open in Protégé). `--id core` exports the built-in classes. The Turtle states no disjointness, so a reasoner infers types from ranges instead of rejecting; closed-world checking is the scanner's job. Reasoner check (needs Java):

    uv run --with rdflib --with owlready2 python tool/ontology_hermit_check.py DIR/techlab.ttl

On 2026-11-23 HermiT found the TechLAB and smart-agriculture fixture exports consistent, with no unsatisfiable classes.

## Resolver misses and the exact-name rule
`packages/tylog_core/tool/link_misses.dart` classifies each gold mention by why it was or was not linked. On the 181 draft labels, 75 mentions have a real page; the main loss (25) was a page named exactly as written losing to notes whose titles only contain the word ("Blender" against Blender tutorials). Rule added in `_candidates`: one exact-name page wins over partial matches unless the user already accepted another page for that word.

| | linked correct | linked wrong | review | propose | precision | accuracy |
|---|---:|---:|---:|---:|---:|---:|
| before | 47 | 1 | 60 | 73 | 0.979 | 0.260 |
| after | 72 | 2 | 34 | 73 | 0.973 | 0.398 |

Caveat: the rule was designed after reading these same rows and the labels are unverified drafts, so this is not a held-out result. It needs a fresh verified sample.

## Handing a class to a small model
Code: `packages/tylog_core/lib/src/slm_readiness.dart`. Each ledger decision is about one entity, whose kind gives its class, so the ledger is already tagged by class.

    dart run bin/tylog.dart slm-readiness --vault V
    dart run bin/tylog.dart export-domain --vault V --id core --class person --out DIR

A class is suggested (`slmSuggestions`) at 200 decisions about 20 distinct entities with at least one rejection; both numbers are untuned constants. The user's answer is a Decision row (`source: slm`, `item: slm:<class>`). Real vault on 2026-11-23: person 16 decisions, place 5, project 3, organization 2; nothing is ready.

Small-model arm, first run 2026-11-23 (`tool/gliner_baseline.py`; GLiNER `urchade/gliner_multi-v2.1`, zero-shot, the seven mention types as labels, Studio CPU). Reference is the LLM's own extraction, so this is agreement, not accuracy. 38 notes (24 screenshots, 14 daily), 329 LLM mentions:

| | found by GLiNER |
|---|---:|
| person | 64/69 |
| place | 67/79 |
| organization | 49/69 |
| equipment | 7/10 |
| event | 7/11 |
| project | 13/34 |
| topic | 23/57 |
| all | 230/329 (70%), same type 169 (51%) |

GLiNER also returned 358 spans the LLM did not; nobody has judged them. Median 0.78 s per note on CPU, 35 s for all 38. Of the 13 draft-gold mentions that have a real entity, GLiNER found 10. `gliner_baseline.py sheet` writes every span from both models (687) for a person to mark real or not; with that, both are scored against the same truth.

Not built: the card in the app, fitting a model, registering it per class in `ai.json`, the keep-only-if-it-matches guard.

## Reuse
| TyLog | Standard |
|---|---|
| person, organization, place, event | schema.org Person, Organization, Place, Event |
| `part_of` | schema.org `isPartOf` / `containedInPlace` |
| Decision | PROV-O `prov:Activity` by a `prov:Agent` |
| Revision, origin/derivation | PROV-O `prov:wasRevisionOf`, `prov:wasDerivedFrom` |

## Not built
General inverse/transitive inference (only `part_of` is followed), per-class slot overrides, required slots, domain classes as mention types.
