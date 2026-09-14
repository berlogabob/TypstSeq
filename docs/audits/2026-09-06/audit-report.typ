#let navy = rgb("20344a")
#let blue = rgb("2f6f9f")
#let green = rgb("26734d")
#let amber = rgb("a96816")
#let red = rgb("a23b3b")
#let ink = rgb("24313d")
#let muted = rgb("687783")
#let pale-blue = rgb("eef5f9")
#let pale-green = rgb("edf7f1")
#let pale-amber = rgb("fff7e8")
#let pale-red = rgb("fff0f0")

#set document(
  title: "TyLog Reliability Audit",
  author: "Audit report",
  keywords: ("TyLog", "Flutter", "Android", "SAF", "reliability"),
)
#set page(
  paper: "a4",
  margin: (x: 18mm, top: 16mm, bottom: 15mm),
  numbering: "1",
  header: context {
    if counter(page).get().first() > 1 {
      grid(
        columns: (1fr, auto),
        align: (left, right),
        text(size: 7.5pt, fill: muted)[TYLOG / RELIABILITY AUDIT],
        text(size: 7.5pt, fill: muted)[2026-09-09],
      )
    }
  },
  footer: context {
    align(center, text(size: 7.5pt, fill: muted)[#counter(page).display()])
  },
)
#set text(font: "Libertinus Serif", size: 9.5pt, fill: ink)
#set par(leading: 0.58em, justify: true)
#set heading(numbering: none)

#let status(label, color: green, fill: pale-green) = box(
  fill: fill,
  inset: (x: 7pt, y: 4pt),
  radius: 4pt,
  text(size: 8pt, weight: "bold", fill: color)[#label],
)

#let callout(title, body, fill: pale-blue, accent: blue) = block(
  fill: fill,
  stroke: (left: 3pt + accent),
  inset: (x: 9pt, y: 7pt),
  radius: 4pt,
  width: 100%,
  [
    #text(weight: "bold", fill: accent)[#title] #linebreak()
    #body
  ],
)

#let metric(value, label, color: navy) = block(
  fill: luma(248),
  inset: (x: 8pt, y: 7pt),
  radius: 4pt,
  width: 100%,
  align(center,
    stack(
      spacing: 2pt,
      text(size: 17pt, weight: "bold", fill: color)[#value],
      text(size: 7.5pt, fill: muted)[#label],
    ),
  ),
)

#align(left)[
  #text(size: 9pt, weight: "bold", fill: blue)[TYLOG / APPLICATION RELIABILITY]
  #v(4pt)
  #text(size: 25pt, weight: "bold", fill: navy)[Reliability audit]
  #v(3pt)
  #text(size: 11pt, fill: muted)[Android performance, indexing, sync, storage, and current controls]
  #v(8pt)
  #status("COMPLETE · 31 / 31 TASKS", color: green, fill: pale-green)
]

#v(12pt)
#grid(
  columns: (1fr, 1fr, 1fr, 1fr),
  gutter: 6pt,
  metric("54 s", "first 2,001-entry index", color: blue),
  metric("440–894 ms", "repeat cold display", color: green),
  metric("0", "idle scans in 303 s", color: green),
  metric("0", "dropped dashboard frames", color: green),
)

#v(12pt)
#callout(
  "Executive result",
  [The reported “thinking” loop was reproducible as a real Android startup race. Selecting the first folder opened the vault twice; the second open killed a worker while SAF replies were still in flight, causing a native Flutter `did_send` abort. The duplicate open is removed, worker shutdown now drains cooperatively, and the same guarded profile fixture stayed usable through startup, rebuild, idle, storage contention, and control tests.],
  fill: pale-green,
  accent: green,
)

= What was found

#table(
  columns: (1.15fr, 2.05fr, 1.2fr),
  inset: 5pt,
  align: (left, left, right),
  fill: pale-blue,
  stroke: none,
  text(fill: navy, weight: "bold")[Issue],
  text(fill: navy, weight: "bold")[Observed behavior and cause],
  text(fill: navy, weight: "bold")[Disposition],
  [Startup crash], [First Android folder selection opened the vault twice; the second worker replacement killed a live SAF response port.], status("FIXED", color: green, fill: pale-green),
  [Worker teardown], [Disposal could strand a command or kill an isolate during native/SAF I/O.], status("FIXED", color: green, fill: pale-green),
  [Repeated indexing], [A settled idle vault could be rescanned by overlapping lifecycle/sync triggers.], status("FIXED", color: green, fill: pale-green),
  [UI stalls], [Index serialization, validation, search construction, and storage work competed with the root isolate.], status("REDUCED", color: blue, fill: pale-blue),
  [SAF tail latency], [Large attachment writes overlap interactive reads and atomic saves.], status("MONITORED", color: amber, fill: pale-amber),
  [Dashboard polling], [Unchanged trace reloads consume SAF reads while the dashboard is open.], status("MEASURED", color: blue, fill: pale-blue),
)

= Device evidence

The guarded profile build ran on a Nothing A024 (Android 16 / SDK 36) using the disposable `TyLogAuditVault` tree. The production vault was never selected or modified during measurements.

#table(
  columns: (1.55fr, 1fr, 1fr, 1fr),
  inset: 5pt,
  align: (left, right, right, right),
  fill: pale-blue,
  stroke: (x: 0.4pt + rgb("d7e3eb"), y: 0.4pt + rgb("d7e3eb")),
  text(weight: "bold", fill: navy)[Measurement],
  text(weight: "bold", fill: navy)[p50],
  text(weight: "bold", fill: navy)[p95],
  text(weight: "bold", fill: navy)[max / result],
  [SAF note read + atomic save / idle], [263 ms], [325 ms], [325 ms],
  [SAF with 24 MiB attachment transfer], [264 ms], [545 ms], [744 ms],
  [Dashboard load + parse], [46.5 ms], [56.5 ms], [60.9 ms],
  [Dashboard JSON parse only], [1.19 ms], [2.12 ms], [5.84 ms],
  [Inline vs worker root-isolate stalls], [6 frames], [3 frames], [63 vs 35 ms],
)

#v(7pt)
#grid(
  columns: (1fr, 1fr),
  gutter: 8pt,
  callout("Idle behavior", [After settling, `index.json` and `search-index.json.gz` stayed unchanged for 303 seconds.], fill: pale-green, accent: green),
  callout("Integrity", [All 60 SAF mutations preserved bytes, hashes, decoded content, and atomic replacement semantics.], fill: pale-green, accent: green),
)

= Implemented changes

#enum(
  [First-vault onboarding returns after the selected entry has already been opened, preventing the duplicate startup open.],
  [Worker disposal settles the client stream immediately but keeps the worker isolate alive until its current native/storage await returns.],
  [Successful search-index publication is explicit and revisioned; cancelled or failed builds do not publish partial search state.],
  [Save failures now gate note/vault navigation so dirty buffers are retained.],
  [Sync authentication failures pause automatic retries until credentials change or the user explicitly retries.],
  [Report exports request only canonical compiler dependencies, avoiding unrelated vault media reads.],
)

= Verification coverage

#grid(
  columns: (1fr, 1fr),
  gutter: 8pt,
  [
    #text(weight: "bold", fill: navy)[Software]
    #v(3pt)
    599 Flutter tests passed with one intentional skip; 209 core tests, 19 Rust tests, the 10k-note benchmark, five macOS PDF tests, targeted analysis, and graph refresh passed.
  ],
  [
    #text(weight: "bold", fill: navy)[Connected phone]
    #v(3pt)
    SAF contention, worker shutdown/replacement, background/foreground sync, native worker indexing, PDF export, and all Magic editor actions passed in profile mode.
  ],
)

#v(8pt)
#callout(
  "Operational recommendation",
  [Keep large attachment transfers away from interactive editing windows. The measured p95 SAF tail rose by 68% under contention even though content integrity remained intact. No lock or atomic-write change is justified by the current evidence.],
  fill: pale-amber,
  accent: amber,
)

= Limits and follow-up

#table(
  columns: (1.6fr, 2.4fr),
  inset: 5pt,
  stroke: (x: 0.4pt + rgb("e4e8eb"), y: 0.4pt + rgb("e4e8eb")),
  [Network baseline], [The disposable fixture had no Nextcloud account, so a real remote sync completion time and production 401/403 run were unavailable. Controlled 401/403 regressions verify that automatic retries pause correctly.],
  [Before/after timing], [No authentic pre-fix phone baseline exists. This report therefore makes no percentage-improvement claim; it reports post-fix measurements and the reproduced crash cause.],
  [App-local state], [An early driver command without `--keep-app-running` removed app-local settings. The external production vault was untouched, but its registry entry and credentials may need to be restored on the phone.],
)

#v(10pt)
#text(size: 8pt, fill: muted)[Evidence: `docs/audits/2026-09-06/evidence/` — T00, T25, T26, T28, and T30. Layout guidance retrieved with TypstRAG from the Typst Page Setup Guide, template guidance, semantic PDF guidance, and table/syntax references (Typst v0.15.1).]
