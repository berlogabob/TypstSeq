# Conceptual data model

One graph, many sources. Every fact records where it came from (`source`) and how it was produced (`derivation`). Field names below are the real ones in the vault and in OpenLabTwin (OLT).

## Research question

RQ: In a personal knowledge system fed by human, machine and institutional sources, does one provenance-aware Item model with one Decision log (accept, defer, dismiss, ignore) make sources linkable and attention measurable, and does the system improve from those decisions over time, compared with per-source silos?

Framing:

- mixed-initiative interaction (Horvitz 1999): the machine proposes, the human decides, and ignoring is a decision too.
- attention is the scarce resource (triage cost).
- boundary objects (Star and Griesemer 1989): OLT places and items are shared by the institution and the person.

```mermaid
erDiagram
  SOURCE ||--o{ ITEM : produces
  ITEM ||--o{ MENTION : contains
  MENTION ||--o{ LINK : proposes
  ENTITY ||--o{ LINK : target
  ENTITY ||--o{ ENTITY : "alias / part of"
  LINK ||--o{ DECISION : "accept / reject"
  ITEM { string id string kind date date tags tags string path }
  MENTION { string surface string note string content_sha int prompt }
  ENTITY { string id string kind string title aliases aliases }
  LINK { string surface string entity string note }
  DECISION { string at string decision string context }
  SOURCE { string name string derivation }
```

## Entities

| Entity | In TyLog | In OLT |
|---|---|---|
| Item | a `.typ` note: daily, note, screenshot (OCR), audio (ASR transcript), article, event | `activities`, `lessons` |
| Entity | a note of kind person, place, project, concept or marker | `people`, `places`, `items`, `assets` |
| Mention | a span in an Item (`_system/enrich/mentions/*.json`) | an activity's note or purpose text |
| Link | the resolved reference (`#tylog.link`) | `activity_items`, `movements` |
| Decision | `_system/enrich/feedback/*.jsonl` (`at`, `decision`, `surface`, `entity`, `note`, `context`) | `audit_log` |

## Source and derivation

| Source | Produces | Derivation |
|---|---|---|
| Typed text (daily, notes) | Items | typed |
| Screenshot OCR | screenshot Items: category, tags, keywords | extracted |
| Audio ASR | transcript inside an audio Item | extracted |
| LLM enrichment | Mentions and suggested Links | suggested, then confirmed or rejected |
| OLT (Supabase) | external Entities, keyed by place code or uuid | institutional |
| Calendar (ICS) | event Items | imported |
| Contacts | person Entities | imported |

## Attention and Decision

Every Item has an attention state: new, kept, acted, archived. This is separate from domain progress such as task todo/doing/done or article reading. Old values map on read: screenshot inbox maps to new, `idea` new maps to new, and `idea` approved maps to kept. Screenshot kept/acted/archived and `idea` archived map to themselves.

One Decision row is `{at, device, item, source, action, target, context}`. Actions: seen, added-to-today, scheduled, accepted, rejected, dismissed, ignored. Rows live in `_system/decisions/<device>.jsonl`. Decisions in `_system/enrich/feedback` and `_system/enrich/shown` are read too.

External Items (OLT, Microsoft) are cached outside the synced vault and become a note only when the user acts.

## Rules

1. An external Entity (`source: openlabtwin`) is read-only in TyLog; edits go through OLT's API and its own access rules.
2. A Link is never final until a Decision accepts it; the resolver uses accepted Decisions to improve.
3. The graph can be filtered by source; clusters can be grouped by source.
4. Secrets (tokens, API keys) are not part of the model; they stay per device.

## What the thesis measures

- Accept rate of suggested Links over time (`tool/enrich_learning.py`).
- Decision latency per source.
- Ignore rate per source.
- Gold set: 100-200 hand-labelled mentions, resolver with and without the Decision ledger.
- Coverage: share of Items per source that carry at least one confirmed Link.
- Novelty claim to test: one personal graph that mixes sources and tracks provenance links better over time than per-source silos.
