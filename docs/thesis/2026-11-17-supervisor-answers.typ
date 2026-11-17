// Answers to the supervisor's architecture note ("Conceptual and Structural Summary"), 2026-11-17.
// Every claim below was rechecked against code and config on 2026-11-17 (codex audit .codex-runs/factcheck.log + manual greps).
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
  meta-line: "17 Nov 2026 · checked against both repositories, the AI settings and the live lab database",
  standfirst: [We follow the note's main principle: the LLM proposes, deterministic code checks, and a person decides. A strong exact match is linked without asking, and that is recorded as an automatic decision. We reach this with a small stack: plain Typst files and a local index for the personal graph, PostgreSQL for the lab, and local models on our GPU PC, served by Unsloth Studio. There is no graph server, no separate vector database server and no message queue. TyLog keeps its vectors in its own SQLite index, and OpenLabTwin keeps them in PostgreSQL. Each row below names what we use for one layer of the note.],
)

= Layer by layer

#data-table(
  ("Layer in the note", "What we use", "State"),
  (
    ("User interfaces", "TyLog app on phone and desktop (notes, voice, screenshots), plus a tylog command line with an MCP server for AI agents. OpenLabTwin: the staff office (web), a public site with booking and idea forms, a TV showcase, QR labels on shelves and units, and the database's REST API (PostgREST)", "Built"),
    ("Local LLM", "Unsloth Studio on the Studio GPU PC, through an OpenAI-compatible API. Ornith 1.5 35B extracts from TyLog notes, and Ornith 1.5 9B summarises lab ideas. The workers ask for JSON and drop replies that do not validate. Moving to another OpenAI-compatible server means changing its URL, key and model id in one settings file (TyLog ai.json, lab .env)", "Built"),
    ("Semantic extraction", "An enrichment worker reads day notes, voice-note transcripts and screenshot text (OCR plus a description). It returns mentions of people, places, equipment and topics per line, plus keywords and loan proposals. Articles are never enriched, because they are other people's text", "Built"),
    ("Validation", "A deterministic resolver checks every mention against known notes. An exact, unambiguous match is linked automatically; anything else waits on a review card. In the lab, PostgreSQL constraints, row-level security and triggers apply (one active loan per tagged unit). 139 database tests pass on the live project", "Built, no SHACL"),
    ("Knowledge graph", "TyLog: the vault itself. Notes are typed by kind; links, citations and tags are the graph edges; part_of is a note property (unit on a shelf, shelf in a room). An index file (_index/index.json) plus a local SQLite database answer queries. OpenLabTwin: tables and views", "Built, no graph DB"),
    ("Ontology", "A small set of standard kinds and relations (next section). The user can add a custom kind. Topic-cluster merges, splits and renames are proposals the user accepts in Incoming", "Built, informal"),
    ("Fact lifecycle", "Five states: proposed, accepted, rejected, auto, obsolete (ADR 0002). The graph draws proposed links dashed. Each link decision records proposed_by (llm:<model> or auto); confidence is stored when known", "Built for links, tags, clusters"),
    ("Modules", "OpenLabTwin: bookings and consultations, storage and loans, idea hub, paper archive with OCR, TV showcase and video-wall control. TyLog: journal, tasks and loans, calendar (ICS feeds), article library, boards, whiteboard, audio notes, screenshots, and installable content packs (.tylogpack)", "Built"),
    ("Slash commands", [`/loan out <equipment> to <person> [due <date>]` and `/loan return <equipment>`, parsed without the LLM into the same review card. Each LLM loan proposal shows the command it stands for], "Built"),
    ("Transactions, audit", "The review card is the preview and the tap commits. Staff can only add lab movements, never edit or delete them; a mistake is fixed with an adjustment row. An audit trigger logs every change to the staff-edited tables. Bridge movements carry a tylog: note, and the metrics script sorts every movement into a channel (tylog, import, office)", "Built"),
    ("Vector search", "TyLog: notes are cut into chunks and embedded on the device (multilingual-e5-small, 384 dimensions, an optional download). The vectors are stored in the SQLite index. Search is hybrid (keyword plus vector, merged by rank fusion), and each semantic hit cites its chunk in the source note. Lab idea hub: nomic-embed-text through Ollama on the lab node; 768-dimension vectors in PostgreSQL (pgvector), used to find similar and complementary ideas", "Built, embedded, no server"),
    ("Storage", "TyLog: Typst files synced through our own Nextcloud (WebDAV). Lab: Supabase PostgreSQL and Supabase Storage for archive photos, plus a nightly backup (03:30) and a read-only local mirror (03:45) on the lab node", "Built"),
    ("Auth, events, deploy", "Supabase Auth (email link, staff role). Scheduled jobs instead of a queue: cron on the lab node (site publish every 30 min, idea AI and archive OCR hourly, TV every 5 min), and launchd agents on the Mac for TyLog's workers. Deploy through GitHub Pages and Actions. The apps are not containerised; only our Nextcloud server runs in Docker", "Built"),
  ),
  widths: (3.1cm, 1fr, 2.5cm),
  right-from: none,
)

= The ontology we have

#fact("Note kinds", [Journal: daily, note, article, research, screenshot, idea. Entities: person, organization, place, website, event, project. Custom kinds are allowed; the lab export adds equipment.])
#fact("Other items", [Tasks are lines inside notes (a loan is a task with equipment and a borrower). Audio notes and files have their own pages. Bookings and ideas arrive from the lab in Incoming.])
#fact("Relations", [Graph edges: link, citation, tag, read, finished. Note properties: part of (unit on a shelf, shelf in a room), assignee, borrower, due date.])
#fact("Mapping to the note", [Person = Person; organization = Organization; equipment = Resource; place = Place; a loan task = Loan; a booking = Event. Statuses: extracted / pending = proposed; validated / published = accepted; rejected = rejected; obsolete = obsolete. We have no "contested" state. The nearest is a loan refused by the lab, which shows in Incoming.])

= How the two systems connect

#data-table(
  ("Direction", "What moves", "How"),
  (
    ("Lab → TyLog", "Places, units, professors", [`export_tylog.py` writes one note per coded place, tagged unit and professor. A unit's note id is its asset tag and a place's is its code. The notes are marked `source: openlabtwin` and the export overwrites them. A dry run on live data gave 111 notes]),
    ("Lab → TyLog", "Bookings and ideas", "Requested bookings and new ideas appear in TyLog's Incoming. Accept or dismiss is logged like any other decision"),
    ("TyLog → Lab", "Loans", [After the user accepts it, a sentence (through the LLM) or a `/loan` line becomes a loan task. `lab_bridge.py` turns it into an issue or return movement keyed `tylog:<task>:<tag>:out|return`; a unique index stops the same key from being recorded twice]),
    ("Lab → TyLog", "The lab's answer", "Recorded, or refused with a reason (for example: already out with someone, or no such person). The answer goes to a results log outside the notes. It shows as a chip on the task, and a refusal also appears in Incoming"),
  ),
  widths: (2.6cm, 3cm, 1fr),
  right-from: none,
)

The lab database stays the only record of loans; TyLog is one more way to enter them. The bridge and the export are built and tested, and the export has had a dry run on live data. Neither has been applied to real data or scheduled yet.

= The note's data flow, on one loan

#data-table(
  ("Step in the note", "In our system (illustrative example)"),
  (
    ("1–2 Request, LLM reads it", [A day note says “Lent the Quest 3 unit 1 to Ana until Friday”. The LLM returns the mentions and a loan proposal as JSON]),
    ("3 Resolve against the graph", "The resolver matches the equipment to a unit note (id = its asset tag) and the borrower to a person note"),
    ("4 Command registry", [The card shows the typed equivalent, `/loan out Quest 3 unit 1 to Ana due 2026-11-21`]),
    ("5 Validate", "The equipment must resolve to one unit; otherwise the user picks it. A unit that is already out gets a warning in TyLog and a refusal from the database trigger. The bridge skips an unknown or ambiguous borrower and records the reason, and staff add the person in the office"),
    ("6–7 Preview, execute", "The review card is the preview; the tap writes the loan task into the note"),
    ("8–9 Graph, provenance", "The index updates, and the device's decision ledger records the proposer (llm:<model>) and the user's answer"),
    ("10 Events", "The bridge run (by hand for now, later every 30 minutes) records the movement in the lab database, and the answer comes back as a chip"),
    ("11 Ontology proposals", "Topic-cluster merges, splits and renames wait in Incoming for the user. Tags and kinds change only when the user edits them"),
  ),
  widths: (4.2cm, 1fr),
  right-from: none,
)

= Where we differ, and why

- *No graph database (Neo4j, Jena, GraphDB).* At one person and one lab, the vault with its index and PostgreSQL answer every query we need so far. An RDF export is possible later work; we have not designed its mapping yet.
- *No SHACL or OWL reasoning yet.* The rules live where the data lives: in the lab, PostgreSQL constraints and triggers; in TyLog, the resolver and the note writers' own checks. The double-loan trigger then gives the same answer to every channel (office, TyLog bridge, scripts).
- *No separate vector database server, no queue, and no containers for the apps.* The vectors sit next to the text they came from: in TyLog's SQLite index, and in the lab's PostgreSQL. Scheduled jobs (cron and launchd) do the work of events. The note's section 17 allows this for a first version.
- *No shared module contract or command registry yet.* An OpenLabTwin module is a schema plus its screens. TyLog has content packs, but they carry notes, not behaviour. The `/loan` commands are the first typed family.
- *Two records, not one.* TyLog logs decisions in its own ledgers (Incoming decisions and link review). The lab logs movements, append-only, and keeps an audit log. They are linked per loan step by the `tylog:` key and the results log.

#callout(title: "In one line", tone: "info")[
  LLM for interpretation; files and PostgreSQL for knowledge; vectors inside the TyLog index and the lab database for retrieval; a small vocabulary for meaning; database rules, the resolver and human review for validation; apps as modules; `/loan` lines for commands; TyLog's decision ledger and the lab's movement log, joined by one key per loan step.
]
