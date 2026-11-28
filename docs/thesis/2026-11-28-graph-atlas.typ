// Graph atlas: thesis addition, 2026-11-28. Compile: typst compile 2026-11-28-graph-atlas.typ
#import "lib.typ": *

#show: report.with((
  title: "The graph as an atlas",
  author: ("Andrew Diakov",),
  footer: "Graph atlas · 28 Nov 2026",
  lang: "en",
))

#title-block(
  "The graph as an atlas",
  subtitle: "Addition to the conceptual model · TyLog",
  meta-line: "28 Nov 2026 · from a code audit of the same day, checked against the supervisor's links of 26 Nov; nothing in this note is built yet",
  standfirst: [The thesis says "one model, many sources" but never describes the graph that shows the model. An audit found five graph views on two unrelated widgets, with different filters, colours and names. This note gives the graph one concept taken from the conceptual data model: the vault is the archive, the index is the knowledge graph, that graph under one ontology is the atlas and the graph screen is how it is explored, saved selections are the anthology, and the decision log is the memory that improves the system. It then lists what the current graph lacks and the order to build it.],
)

#kpi-row((
  ("5", "Maps today", "on two widgets, no shared state"),
  ("1", "Map missing", "Structure: what is part of what"),
  ("3", "Lenses missing", "Origin, Status, Recency"),
  ("3 of 18", "Sources read", "the three atlas papers; 15 named from memory"),
))

= Why this addition

Rule 3 of the conceptual model says the graph can hide or show each source. In the app the chips filter the note kind, not where the note came from. ADR 0002 says every map draws the status of a fact. In the app only proposed links are drawn, and only around the open note. Both gaps come from the same cause: the graph grew view by view and has no model of its own.

Sources are in `literature-2026-11.md`. Section 9 holds the three atlas papers the supervisor sent on 26 Nov; they were read at the level of abstract, introduction and usage. Sections 7 and 8 were named from memory and are not read; every citation from them below is a candidate, not support. Archive, anthology, memory layer and conceptual data model are the supervisor's terms, and none of his links defines them.

= One model, five readings

A conceptual data model states what exists and how it relates, independent of storage (Chen 1976; Tsichritzis and Klug 1978). Ours has six entities: Source, Item, Mention, Link, Entity and Decision. The five terms below are readings of that one model. They are not five stores.

#data-table(
  ("Reading", "Question it answers", "Made of", "In TyLog"),
  (
    ("Archive", "What do I have, and where did it come from?", "Items with origin, derivation and time; append-only", "Vault files, decision log"),
    ("Knowledge graph", "What is connected, and how sure are we?", "Entities and typed links, each with a status", "Index: links, tags, citations, part_of"),
    ("Atlas", "How do I find my way through all of it?", "The knowledge graph under one ontology; maps are how it is read", "Index with ontology core and packs; graph screen"),
    ("Anthology", "What did I choose to keep?", "A named selection made by decisions", "Accepted links, saved views, boards"),
    ("Memory layer", "What did the system learn from me?", "Decisions consolidated into rules and names", "Ledger to resolver; daily cluster step"),
  ),
  widths: (2.6cm, 4.2cm, 1fr, 4cm),
  right-from: none,
)

A Decision is the only step that moves a fact from the archive into the anthology. This is rule 2 stated as a path. Candidate sources, not read: the open archive model of ingest, keep and record provenance (CCSDS 2012) for the archive, and the named trail through one's own material (Bush 1945) for the anthology. The Archive reading is the whole vault. It is not the attention state `archived`, which marks one Item as put away.

= Memory layer

The research question asks whether the system improves from decisions over time. That is a claim about memory. The table maps the standard memory systems onto parts that already exist. The citations in it are from memory and not read, so for now the mapping is a framing and not a result.

#data-table(
  ("Memory", "Role", "In TyLog", "State"),
  (
    ("Episodic (Tulving 1972)", "What happened, and when", "Items by day; the decision log", "Built"),
    ("Semantic (Tulving 1972)", "What is known", "Entities, links, tags, kinds, clusters", "Built"),
    ("Procedural (Squire 2004)", "How to act without asking", "Exact-match rule recorded as auto; typed /loan lines", "Built"),
    ("Working (Baddeley and Hitch 1974)", "What is in view now", "Today; the Neighbourhood map", "Built"),
    ("Consolidation (McClelland et al. 1995)", "Episodes become knowledge", "Daily cluster step; resolver reads the ledger", "Built, not measured"),
    ("Forgetting", "Unused things fade", "Attention archived; status obsolete; rejected hidden", "Partly: no recency in the graph"),
  ),
  widths: (4.4cm, 3.4cm, 1fr, 3cm),
  right-from: none,
)

Language agents use the same four stores (Sumers et al. 2024). The difference here is who writes them: the human writes the episodes and approves each consolidation. The machine only proposes.

= The atlas

In the supervisor's three papers an atlas is a knowledge graph that brings many sources under one ontology so that a field can be navigated. The Human Reference Atlas graph integrates data from many labs and technologies under the Common Coordinate Framework ontology, and its applications and Exploration User Interface read the graph as their backend (Bueckle et al. 2025). The same paper says the ontology is the framework for building an atlas and is not an atlas itself. A metadata graph built from three public platforms under a Common Metadata Ontology "serves as an atlas for navigating" the field (Venkataramanan et al. 2025). The ATLAS project pairs one ontology with a knowledge graph to aggregate unlike research outputs (Giacomini et al. 2025).

TyLog has the same three parts at the scale of one person. The ontology core and its packs are the framework. The index, with links, tags, citations and part_of from every source, is the graph. The graph screen is the exploration interface. So the atlas is not the screen: it is the graph under its ontology, and the screen offers several maps of it.

A map fixes one projection and answers one question (Munzner 2014, not read). The set follows the order overview, then zoom and filter, then detail (Shneiderman 1996, not read).

#data-table(
  ("Map", "Question", "Projection", "Today", "Change"),
  (
    ("Territory", "What is my knowledge made of?", "Containment: topic, tag, note (Balzer and Deussen 2005)", "Voronoi", "Fix six defects; accept filters"),
    ("Topics", "How do topics relate?", "Tag co-occurrence", "Overview", "True legend; topic colours; draw weight"),
    ("Network", "Which notes hold it together?", "Force layout (Fruchterman and Reingold 1991)", "All files: top 200 nodes by degree, mostly tag hubs", "Rank notes, not hubs"),
    ("Neighbourhood", "What is around this note?", "Hops around a focus", "Focused: two hops, fixed", "Depth 1 to 3; draw statuses"),
    ("Timeline", "When did it happen?", "Time", "45 days, articles only", "Window control; true added edge"),
    ("Structure", "What is part of what?", "Tree over part_of", "Missing", "New; the layout code exists"),
  ),
  widths: (2.9cm, 3.1cm, 3.5cm, 3.3cm, 1fr),
  right-from: none,
)

Topics come from label propagation over tags (Raghavan et al. 2007). Large node-link drawings stop being readable long before they stop being drawable (von Landesberger et al. 2011), which is why Network is ranked and capped and Territory is the overview.

= Lenses and filters

A map says where a node sits. A lens says what its colour means. A filter says what is included. Today each widget keeps its own mix of the three. The redesign holds them in one state shared by every map.

#data-table(
  ("Control", "Values", "Today", "Closes"),
  (
    ("Lens: Topic", "Community, same hue on every map", "Hues differ between two maps", "Consistency"),
    ("Lens: Kind", "Note kind", "Chips only, no colour", "Consistency"),
    ("Lens: Origin", "Typed, extracted, institutional, imported", "Missing", "Rule 3"),
    ("Lens: Status", "Accepted, auto, proposed", "Proposed only, one map", "ADR 0002"),
    ("Lens: Recency", "Last edited or opened", "Missing", "Forgetting"),
    ("Filter", "Origin, kind, edge kind, time window, depth, unlinked", "Kind, edge kind, unlinked; none in Voronoi", "Rule 3"),
    ("Saved view", "Name, map, lens, filters, focus", "Missing", "Anthology"),
  ),
  widths: (2.6cm, 1fr, 4.4cm, 2.4cm),
  right-from: none,
)

= Audit of the current graph

#scorecard((
  ("Voronoi", "Six defects", "warn", "Selection does not repaint; a failed layout retries forever; the bar names the tag as the cluster; no filters, statuses or export"),
  ("Focused", "Limited", "info", "Two hops, fixed; with no note open it shows the topic map under the Focused name; a mutual link is drawn twice"),
  ("Overview", "Mislabelled", "warn", "Co-occurrence is shown as Same tag; weight is not drawn; no topic colours"),
  ("All files", "Misnamed", "warn", "Top 200 nodes by degree, mostly tag hubs; colours differ from Voronoi; renamed clusters ignored"),
  ("Timeline", "Mislabelled", "warn", "Added is shown as Links; the window is fixed; articles only"),
  ("Shared state", "Missing", "warn", "Four maps share filters by accident; layout runs on the interface thread"),
  ("Rule 3: hide or show each source", "Half met", "warn", "Chips filter note kind, not origin"),
  ("ADR 0002: status in every map", "Half met", "warn", "Proposed links only, around the open note only"),
))

The full audit with file and line references is in `docs/audits/2026-11-28-graph.md`.

= What this adds to the measures

No new metric. Two existing ones become visible in the graph.

- *Coverage per source.* The Origin lens and filter show which sources carry confirmed links.
- *Accept rate.* The Status lens shows accepted, auto and proposed links around a note.

= Build order

#fact("P1 Defects", [Voronoi and graph fixes with no interface change.])
#fact("P2 Core model", [Truthful edge kinds (part of, added, co-occurs), origin on every node, one edge per mutual link.])
#fact("P3 Atlas state", [One state and one bar for every map. Rule 3 is met here.])
#fact("P4 Maps", [Structure map; Network ranked by notes; Timeline window.])
#fact("P5 Memory", [Recency lens; saved views.])
#fact("P6 Documents", [Manual, ADR 0002, conceptual model.])

The plan with files and tests is in `docs/plans/2026-11-28-graph-atlas/README.md`.

#callout(title: "Questions for the supervisor", tone: "info")[
  1. Is "one model, five readings" an acceptable frame for the conceptual chapter?
  2. Is the memory mapping a framing, or a claim that needs its own measure of consolidation?
  3. Is "anthology: a named selection made by decisions" an acceptable definition?
  4. Which source do you mean for anthology, memory layer and conceptual data model? Your links of 26 Nov cover atlas and knowledge graph only.
]
