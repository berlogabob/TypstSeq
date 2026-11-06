# 0002 - Knowledge states and provenance

- Status: accepted
- Date: 2026-11-06

## Context

Suggestions (links, mentions, tags) and vocabulary (tags, entity kinds, clusters) had no shared status or provenance; desktop auto-wrote strong matches without a recorded decision; clusters were recomputed on every edit, so the map shifted and nobody approved changes. A supervisor's architecture note asks for a fact lifecycle, provenance on each fact, and human approval of ontology changes.

## Decision

Every fact and vocabulary item has one status: proposed, accepted, rejected, auto, obsolete. Facts = links, mentions, tags on a note. Vocabulary = tags, entity kinds, clusters. Every proposal and decision records `proposed_by` (`llm:<model>`, `rule`, `user`, `auto`) and `confidence` when known. LLMs and rules only propose. Vocabulary never changes without a decision; cluster merges/splits/renames are proposals in Incoming. Desktop auto-links are recorded with status `auto`. The graph and Voronoi draw these statuses: accepted solid, proposed dashed, rejected hidden.

## Consequences

- One place to decide (Incoming, plus the graph bar).
- Thesis can measure accept rate per proposer.
- Clusters stay stable between nightly runs.
- No graph database, the vault files stay the source of truth.
