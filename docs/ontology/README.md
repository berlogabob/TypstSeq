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

First run, 2026-11-23, 40 sampled mentions with draft labels (13 unverified), real vault with no domain ontology installed: both arms identical (6 linked correct, 0 wrong, 11 review, 23 propose). The rule changed nothing on this sample; a verified, larger gold set and a vault that uses a domain are needed before any claim.

## Export
    dart run bin/tylog.dart export-domain --vault V --id techlab --out DIR

Writes the domain document, `instances.jsonl`, `decisions.jsonl` (ledger rows about those instances, the examples for a small model) and `techlab.ttl` (OWL in Turtle; open in Protégé). `--id core` exports the built-in classes. The Turtle states no disjointness, so a reasoner infers types from ranges instead of rejecting; closed-world checking is the scanner's job. Reasoner check (needs Java):

    uv run --with rdflib --with owlready2 python tool/ontology_hermit_check.py DIR/techlab.ttl

On 2026-11-23 HermiT found the TechLAB and smart-agriculture fixture exports consistent, with no unsatisfiable classes.

## Reuse
| TyLog | Standard |
|---|---|
| person, organization, place, event | schema.org Person, Organization, Place, Event |
| `part_of` | schema.org `isPartOf` / `containedInPlace` |
| Decision | PROV-O `prov:Activity` by a `prov:Agent` |
| Revision, origin/derivation | PROV-O `prov:wasRevisionOf`, `prov:wasDerivedFrom` |

## Not built
General inverse/transitive inference (only `part_of` is followed), per-class slot overrides, required slots, domain classes as mention types.
