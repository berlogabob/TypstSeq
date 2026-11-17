// Answers to the supervisor's architecture note ("Conceptual and Structural Summary"), 2026-11-17.
// Compile: typst compile 2026-11-17-supervisor-answers.typ
#import "lib.typ": *

#show: report.with((
  title: "Answers to the architecture note",
  author: ("Andrew Diakov",),
  footer: "Answers to the architecture note · 17 Nov 2026",
  lang: "en",
))

#title-block(
  "Answers to the architecture note",
  subtitle: "What TyLog and OpenLabTwin use for each layer, and how they connect",
  meta-line: "17 Nov 2026 · facts checked against the repositories and the live database on that day",
  standfirst: [We follow the note's main principle: the LLM interprets, deterministic code decides, a person approves, and every change keeps its source. We reach it with a smaller stack: plain files and a local index for the personal graph, PostgreSQL for the lab, and local models served by Unsloth Studio on our GPU PC. There is no graph server, no separate vector database server (TyLog keeps its vectors inside its own index) and no message queue. Each row below names what we use for one layer of the note.],
)

= Layer by layer

#data-table(
  ("Layer in the note", "What we use", "State"),
  (
    ("User interfaces", "TyLog app on phone and desktop (notes, voice, screenshots); OpenLabTwin office (web) and public forms; QR labels on shelves and units; REST API (PostgREST); TyLog MCP server", "Built"),
    ("Local LLM", "Unsloth Studio on the Studio GPU PC, through an OpenAI-compatible API: Ornith 1.5 35B extracts from TyLog notes, Ornith 1.5 9B runs the lab idea hub. The model returns JSON only. Any OpenAI-compatible server (vLLM, Ollama) can replace it by changing a URL, which is the note's stable service interface (section 11)", "Built"),
    ("Semantic extraction", "Enrichment worker: mentions of people, places, equipment and topics per line, from day notes, screenshot OCR, audio transcripts and articles", "Built"),
    ("Validation", "Deterministic resolver; review card with a human tap; PostgreSQL constraints, row-level security and triggers (one active loan per unit); 139 database tests on the live project", "Built, no SHACL"),
    ("Knowledge graph", "TyLog: the vault itself. Notes are nodes typed by kind; links, part-of and assignees are edges; a local SQLite index answers queries. OpenLabTwin: tables and views", "Built, no graph DB"),
    ("Ontology", "A small fixed set of kinds and relations (next section). New kinds and tags are proposals the user approves", "Built, informal"),
    ("Fact lifecycle", "proposed, accepted, rejected, auto, obsolete, each with proposed_by and confidence (ADR 0002)", "Built"),
    ("Modules", "OpenLabTwin: bookings, storage, loans, ideas, paper archive, TV. TyLog: journal, tasks, loans, calendar, library, boards, audio, screenshots", "Built"),
    ("Slash commands", [`/loan out <equipment> to <person> due <date>` and `/loan return <equipment>`, parsed without the LLM; each LLM proposal shows the command it stands for], "Built"),
    ("Transactions, audit", "Review card = preview, tap = commit. Lab movements are append-only, never edited; an audit trigger keeps every change; each movement notes its channel", "Built"),
    ("Vector search", "TyLog has its own vector store inside its SQLite index: notes are cut into chunks, each embedded on the device (multilingual-e5-small, 384 dimensions). Search is hybrid (keyword + vector, merged by rank fusion) and every hit cites its chunk in the source note. Lab idea hub: nomic-embed-text through Ollama on the lab node", "Built, embedded, not a server"),
    ("Storage", "Typst files synced through our own Nextcloud; Supabase PostgreSQL; Supabase Storage for archive photos; nightly backup and a local mirror on the lab node", "Built"),
    ("Auth, events, deploy", "Supabase Auth (email link, staff role); cron and launchd instead of queues; GitHub Pages and Actions; no Docker or Kubernetes for the apps", "Built"),
  ),
  widths: (3.1cm, 1fr, 2.5cm),
  right-from: none,
)

= The ontology we have

#fact("Kinds", [person, company, place, equipment, project, event, task (a loan is a task with equipment), idea, article, research, daily note, audio, screenshot, website; bookings arrive from the lab.])
#fact("Relations", [links to, part of (unit on a shelf, shelf in a room), assignee and borrower, mentions (from extraction).])
#fact("Mapping to the note", [Person = Person; company = Organization; equipment = Resource; place = Place; a loan task = Loan; a booking = Event. extracted / pending = proposed; validated / published = accepted; contested = OpenLabTwin refused it or two sources disagree; rejected; obsolete.])

= How the two systems connect

#data-table(
  ("Direction", "What moves", "How"),
  (
    ("Lab → TyLog", "Equipment and places", [`export_tylog.py` writes one note per unit and place; the note id is the asset tag or place code. TyLog never edits these notes. Dry run: 111 notes.]),
    ("Lab → TyLog", "Bookings and ideas", "They appear in TyLog's Incoming; accept or dismiss is logged like any other decision"),
    ("TyLog → Lab", "Loans", [A sentence (through the LLM) or a `/loan` line becomes a loan task once the user accepts it. `lab_bridge.py` turns it into an issue or return movement keyed `tylog:<task>:<tag>:out|return`, so it can never be recorded twice]),
    ("Lab → TyLog", "The lab's answer", "Recorded, or refused with a reason (for example: already out with someone). It shows as a chip on the task, and a refusal appears in Incoming. It is never written into a note"),
  ),
  widths: (2.6cm, 3cm, 1fr),
  right-from: none,
)

The lab database stays the only record of loans; TyLog is one more way to enter them. The bridge and the export are built and tested, and not yet switched on for real data.

= The note's data flow, on one loan

#data-table(
  ("Step in the note", "In our system"),
  (
    ("1–2 Request, LLM reads it", [Example: “Lent the Quest 3 unit 1 to Ana until Friday” in a day note; the LLM returns the mentions as JSON]),
    ("3 Resolve against the graph", "The resolver links the equipment note TL-0007 and the person note Ana Silva"),
    ("4 Command registry", [The card shows `/loan out Quest 3 unit 1 to Ana Silva due 2026-11-21`]),
    ("5 Validate", "Equipment and person exist; the unit is not already out (warning in TyLog, refusal in the database)"),
    ("6–7 Preview, execute", "The review card is the preview; the tap writes the loan task"),
    ("8–9 Graph, provenance", "The index updates; one decision row records who proposed it (llm:<model>) and who accepted it"),
    ("10 Events", "The bridge records the movement in the lab database; the answer comes back as a chip"),
    ("11 Ontology proposals", "Repeated new terms become vocabulary proposals in Incoming, never automatic changes"),
  ),
  widths: (4.2cm, 1fr),
  right-from: none,
)

= Where we differ, and why

- *No graph database (Neo4j, Jena, GraphDB).* At one person and one lab, the vault plus a SQLite index and PostgreSQL answer every query we need. We can export to RDF later without changing the model.
- *No SHACL or OWL reasoning yet.* The rules live where the data lives: PostgreSQL constraints and triggers for the lab, the resolver and the note writers' own checks for notes. One rule then holds for every channel (office, TyLog, scripts).
- *No separate vector database server, queues or Docker for the apps.* TyLog's vectors live in its own SQLite index, next to the text they came from, so a hit always points back to its note; cron and launchd replace events. The note's section 17 allows this for a first version.
- *No generic module contract or command registry yet.* Each module is a schema plus its screens. The #box[`/loan`] commands are the first typed family; others follow when a module needs them.

#callout(title: "In one line", tone: "info")[
  LLM for interpretation, files and PostgreSQL for knowledge, a small vocabulary for meaning, database rules and human review for validation, apps as modules, `/loan` lines for commands, and one decision log across both systems.
]
