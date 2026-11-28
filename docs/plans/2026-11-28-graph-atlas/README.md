# Graph atlas: redesign plan

Status: planned, nothing built. Written 2026-11-28.
Audit: [docs/audits/2026-11-28-graph.md](../../audits/2026-11-28-graph.md).
Thesis text: [docs/thesis/2026-11-28-graph-atlas.typ](../../thesis/2026-11-28-graph-atlas.typ).

## Goal

The graph screen becomes an atlas: several maps of one model, with one shared state.
The thesis and the app use the same words.

## Concept

| Term | Meaning | In TyLog |
|---|---|---|
| Conceptual data model | Source → Item → Mention → Link → Entity, Decision on top | `docs/thesis/conceptual-model.md` |
| Archive | Everything kept, with origin, derivation and time | vault files + decision log |
| Knowledge graph | Entities and typed links, each with a status | index: links, tags, citations, part_of |
| Atlas | Several maps of the same graph, one question each | the graph screen |
| Anthology | What the human chose to keep, saved under a name | accepted links, saved views, boards |
| Memory layer | Decisions consolidated into rules, names and vocabulary | decision ledger → resolver, daily cluster step |

## Design

Three independent controls, held in one immutable `AtlasState` owned by the shell.

**Map** — where things sit. Mode ids stay as they are; only labels change.

| Map | Id | Question | Change |
|---|---|---|---|
| Territory | `voronoi` | What is my knowledge made of? | fix defects, take filters |
| Topics | `conceptMap` | How do topics relate? | true legend, topic colours, drawn weight |
| Network | `allFiles` | Which notes hold it together? | rank notes, not hubs |
| Neighbourhood | `local` | What is around this note? | depth 1–3, statuses |
| Timeline | `timeline` | When did it happen? | window control, true "added" edge |
| Structure | `structure` | What is part of what? | new, tree over `part_of` |

**Lens** — what colour means.

| Lens | Values | Scope |
|---|---|---|
| Topic | community, same hue everywhere, user names everywhere | all maps |
| Kind | note kind | all maps |
| Origin | typed, extracted, institutional, imported | all maps |
| Status | accepted, auto, proposed | Neighbourhood only |
| Recency | fade by last edit or open | all maps |

**Filter** — what is included: origin, kind, edge kind, time window, depth, unlinked.
Search dims non-matches; it does not filter or relayout.

**Saved view** — name + map + lens + filters + focus, in `_system/graph/views.json`.

Words: say "origin", not "source", for provenance (`CONTEXT.md:68`).

## Phases

Each phase ships on its own.

### P1 — defects, no API change

- `lib/voronoi_view.dart`: `shouldRepaint` includes `selectedPath` (`:840`); a failed
  flag with Retry replaces the respawn loop (`:196`, `:467`); "In cluster" walks to the
  root cell (`:539`); the Uncategorized cluster is grey (`:619`); `total` is
  `clusterOrder.length`; keep the transform when the viewport is unchanged (`:239`).
- `packages/tylog_core/lib/src/voronoi.dart:485`: slot is the `clusterOrder` index.
- `lib/graph.dart`: `_hitNode` picks the nearest node with its own radius (`:766`);
  semantics rect uses `_radiusFor` (`:1676`); banner fires when the cap truncated.
- `lib/app_mobile.dart:454`: no note open uses the 40/120 cap.
- Delete `graphPositions` (`lib/graph.dart:885`), `minimumNodeSpacing` (`:1347`),
  `GraphStats.hubPaths`.
- Tests: `test/voronoi_view_test.dart`, `packages/tylog_core/test/voronoi_test.dart`,
  `test/graph_test.dart:452,475`.

### P2 — core model

- `packages/tylog_core/lib/src/graph.dart`: append `partOf`, `added`, `cooccurs` to
  `GraphEdgeKind` (append only: edges sort by `kind.index`, `:117`); rename
  `GraphNode.source` to `noteKind`, add `origin`; add `GraphEdge.mutual` and keep one
  edge per pair (`:86-89`); Timeline uses `added` (`:444`), Overview uses `cooccurs`
  (`:196`).
- New `packages/tylog_core/lib/src/origin.dart`: `enum NoteOrigin`, `originOf(NoteRef)`.
  Typed by default; extracted for screenshot and audio; institutional for
  `properties['source']` `openlabtwin` or `lab`; imported for contacts.
- `lib/graph.dart`: `edgeColor` (`:1713`), `GraphLegend`, `connectionReason`.
- Tests: `packages/tylog_core/test/graph_source_test.dart` (rename), new
  `origin_test.dart`, `test/graph_test.dart`, `test/contrast_test.dart` (every edge
  colour at 3:1).

### P3 — atlas state and bar

- New `lib/atlas.dart`: `AtlasState`, `applyAtlasFilter(NoteGraph)`,
  `filterIndexForAtlas(VaultIndex)`, `lensColor`.
- New `lib/widgets/atlas_bar.dart` replaces the chip rows (`lib/graph.dart:380-461`)
  and the mode menu (`lib/app_mobile.dart:3694-3716`).
- Move `_memoizedGraph` and wiring to a new part `lib/app_mobile/graph_flow.dart`.
  Filter before `boundGraphForLayout`; add the filter hash to the cache key.
- `GraphView`: drop `_visibleKinds`, `_hiddenSources`, `_focusFilter`,
  `_showSuggestions`; take `atlas` and `clusterNames`; always take `communities`.
- `VoronoiView`: take `atlas`; filter the index passed to `buildVoronoiRequest`, with
  communities from the full index so hues hold.
- One layout request for the sync and isolate paths; isolate above 100 connected nodes;
  keep old positions while computing.
- SVG export receives the graph and its positions; per-edge colour and dash.
- Tests: new `test/atlas_state_test.dart`; `test/graph_test.dart`,
  `test/voronoi_view_test.dart`, `test/voronoi_cluster_names_test.dart`,
  `test/retrieval_graph_svg_test.dart`, `test/widget_test.dart:1923`,
  `integration_test/graph_share_native_test.dart`,
  `integration_test/p22_graph_latency_native_test.dart`.

Rule 3 of the thesis is met after P2 and P3.

### P4 — Structure, Network, Timeline

- `packages/tylog_core/lib/src/tree_layout.dart`: add `layoutTreeIds(root, children,
  {leafGap, levelGap})`; `layoutTree` delegates to it.
- `buildStructureGraph(index)`: only notes in a part-of relation.
- `GraphView.layout` enum replaces the timeline sniffing (`lib/graph.dart:784`).
- `buildNetworkGraph(index, {maxNotes})`: rank notes; keep a hub only if it joins two
  kept notes.
- Timeline window and Neighbourhood depth come from the filter.
- Tests: `packages/tylog_core/test/tree_layout_test.dart`, new
  `structure_graph_test.dart`, `test/graph_test.dart:587-647`.

### P5 — Recency lens and saved views

- New `lib/atlas_views.dart`: read and write `_system/graph/views.json` (schema 1,
  unknown keys preserved, as in `lib/kind_registry.dart:47`). Focus stored as note id.
- Recency fades by the later of last edit and last open.
- Test: new `test/atlas_views_test.dart`.

### P6 — docs

`USER_MANUAL.md`, `PLAN.md:10`, `CONTEXT.md:60,68`, `docs/vault-format.md`,
`docs/adr/0002-knowledge-states.md` (Voronoi draws no statuses),
`docs/thesis/conceptual-model.md`, `CHANGELOG.md`. Then `graphify update .`.

## Deferred

- Send a selection to a board.
- Status lens outside Neighbourhood (needs every mentions file).
- Attention colouring (null for most notes).
- Text search as a filter; time range outside Timeline.

## Rules that bind this work

- No index version bump: nothing touches `NoteRef` or the scanner. Derive origin at
  build time (`CONTEXT.md:36`).
- Banner and status stay in overlays (`CONTEXT.md:29`).
- Jank evidence is frame timings, not gfxinfo (`CONTEXT.md:33`).
- Improve existing mechanisms, trace every consumer (`CONTEXT.md:43`).
- Design tokens: `test/design_tokens_test.dart`.
- Device work only on `org.tylog.tylog.profiletest` (`AGENTS.md`).

## Test commands

```
cd packages/tylog_core && dart test
flutter analyze
flutter test test/graph_test.dart test/graph_layout_test.dart test/voronoi_view_test.dart test/voronoi_rename_test.dart test/voronoi_cluster_names_test.dart test/retrieval_graph_svg_test.dart test/contrast_test.dart test/design_tokens_test.dart
flutter test test/rich_editor_test.dart test/widget_test.dart test/graph_test.dart test/archive_release_test.dart test/background_completion_test.dart test/release_config_test.dart
```

## Risks

| Risk | Mitigation |
|---|---|
| Index rebuild cost | do not store origin on `NoteRef` |
| Tests that assume `allFiles` | keep the ids, change labels only |
| Saved views outlive ids or paths | frozen ids, focus by note id, unknown map falls back to `local` |
| New edge kinds break switches or contrast test | append only; pick colours against `test/contrast_test.dart` first |
| Force layout on the UI thread | isolate above 100 connected nodes; confirm with frame timings |
| Voronoi rebuilds on every filter toggle | search only dims; keep old cells until new ones land |

## Start here next session

P1. It has no dependencies and removes the visible bugs.
