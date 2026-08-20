// One-page executive companion to audit-pkms-comparison.pdf.
// Compile: typst compile --font-path docs/fonts --ignore-system-fonts \
//   docs/audit-pkms-onepager.typ docs/audit-pkms-onepager.pdf
#import "lib.typ": *

#show: report.with((
  title: "PKMS Competitive Audit — Executive Brief",
  author: ("TyLog",),
  footer: "TyLog · PKMS audit executive brief",
  lang: "en",
))

#set page(margin: (top: 1.35cm, bottom: 1.45cm, x: 1.45cm))
#set text(size: 8.7pt)
#set par(leading: 0.62em, spacing: 0.7em)
#set list(spacing: 0.35em)

#let card(name, verdict, tone, body) = block(
  width: 100%,
  fill: surface,
  stroke: 0.6pt + hairline,
  radius: radius-md,
  inset: 8pt,
  breakable: false,
)[
  #grid(
    columns: (1fr, auto),
    gutter: 5pt,
    align: horizon,
    text(size: 9.5pt, weight: 700, fill: brand)[#name],
    pill(verdict, tone: tone),
  )
  #v(0.35em)
  #text(size: 8.15pt)[#body]
]

#let priority(rank, title, body, tone: "info") = block(
  width: 100%,
  fill: surface,
  stroke: 0.5pt + hairline,
  radius: radius-sm,
  inset: 7pt,
  breakable: false,
)[
  #grid(
    columns: (18pt, 1fr),
    gutter: 5pt,
    align: top,
    pill(str(rank), tone: tone),
    [#text(size: 8.4pt, weight: 700)[#title] #text(size: 8pt, fill: muted)[— #body]],
  )
]

#text(size: 19pt, weight: 700, fill: brand)[PKMS Competitive Audit]
#linebreak()
#text(size: 10.5pt, fill: muted)[Executive brief · Logseq OG · Logseq 2.0 DB · Tine · TyLog]
#v(0.35em)
#line(length: 100%, stroke: 2pt + accent)
#v(0.5em)

#callout(title: "BLUF", tone: "info")[
The market has split between a frozen files-first incumbent, an ambitious but lock-in-prone database rewrite, and a fast but fragile solo rewrite. *None occupies TyLog's ground:* typed, compilable plaintext; native publishable PDF; and release-grade Android sync safety. TyLog should win as the trustworthy exit for file-owning users — not imitate Logseq's outliner depth.
]

#grid(
  columns: (1fr, 1fr),
  rows: (auto, auto),
  gutter: 8pt,
  row-gutter: 8pt,
  card(
    "Logseq OG",
    "Mature, frozen",
    "bad",
    [Files are the source of truth and the feature set is broad: queries, plugins, whiteboards, SRS, PDF annotation. But maintenance is security-only, large graphs and mobile remain rough, and sync is effectively single-writer. *Fine to stay; a dead end to invest in.*],
  ),
  card(
    "Logseq 2.0 DB",
    "Powerful, early",
    "info",
    [Best data model: typed properties, classes, views, incremental search, RTC/E2EE foundations. The cost is structural lock-in: SQLite source of truth, one-way desktop Markdown Mirror, lossy export, feature regressions, and an ecosystem reset. *The future of Logseq; trust is not yet earned.*],
  ),
  card(
    "Tine",
    "Fast, fragile",
    "warn",
    [Rust-first speed, byte-compatible Logseq files, native PDF annotation, and zero migration make the bet reversible. It is also two months old, solo-maintained, without Logseq plugin compatibility, graph view, SRS, iOS, or its own sync. *Strong demand signal; too young to depend on.*],
  ),
  card(
    "TyLog",
    "Distinct, incomplete",
    "ok",
    [Only product here whose notes are readable text, structured data, and compilable typesetting programs. It also leads on tasks, Android reliability, and conflict-safe WebDAV. Gaps: no block transclusion, query language, plugins, PDF annotation, or E2EE. *A differentiated product, not a Logseq clone.*],
  ),
)

#v(0.8em)
#grid(
  columns: (0.92fr, 1.08fr),
  gutter: 10pt,
  [
    #text(size: 10.2pt, weight: 700, fill: brand)[TyLog's defendable position]
    #v(0.35em)
    #block(
      width: 100%,
      fill: ok.lighten(94%),
      stroke: (left: 3pt + ok),
      radius: (right: radius-sm),
      inset: 8pt,
    )[
      #text(size: 9pt, weight: 700, fill: ok.darken(12%))[“Your notes are a typeset document, not a database.”]
      #v(0.25em)
      #text(size: 8.1pt)[This is the only non-replicated moat in the 16-row matrix. Tine validates demand for fast files-first tools; TyLog adds compile-checked structure, publishing, and safer mobile operation.]
    ]
    #v(0.45em)
    #text(size: 8.1pt)[*Strongest current claims*]
    #list(
      [Native Typst → publishable PDF],
      [RRULE tasks, reminders, time tracking],
      [Release-grade Android + ETag conflict safety],
      [Logseq and Obsidian import already shipped],
    )
  ],
  [
    #text(size: 10.2pt, weight: 700, fill: brand)[What to do next]
    #v(0.35em)
    #grid(
      columns: (1fr,),
      row-gutter: 5pt,
      priority(1, "Ship the Logseq DB importer", [The plan and import boundary already exist; serve stranded OG users and lock-in-wary DB users.], tone: "ok"),
      priority(2, "Lead with the Typst/PDF moat", [Make the unique value proposition explicit in every public surface.], tone: "ok"),
      priority(3, "Add query-lite", [Extend report blocks with inline dynamic sections; do not build a general query language.]),
      priority(4, "Add PDF annotation", [The largest missing feature for the existing reading and article workflow.]),
      priority(5, "Offer optional E2EE", [An age-encrypted WebDAV layer closes the main sync axis where Logseq DB leads.]),
    )
  ],
)

#v(0.65em)
#line(length: 100%, stroke: 0.6pt + hairline)
#v(0.35em)
#grid(
  columns: (1fr, auto),
  gutter: 8pt,
  text(size: 7.4pt, fill: muted)[Evidence: 16 × 4 matrix, 12/12 adversarial claim checks confirmed, 0 contradictions. Deliberately defer block-level refs and SRS until real demand.],
  align(right, text(size: 7.4pt, fill: muted)[Full matrix, implementation analysis, and citations: `docs/audit-pkms-comparison.pdf`]),
)
