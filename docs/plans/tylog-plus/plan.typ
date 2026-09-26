#import "../../lib.typ": report, title-block, callout
// TypstRAG v0.15.1 references: Tutorial / Template and Guides / Page Setup.

#show: report.with((
  title: "TyLog+ delivery plan",
  author: "TyLog+ project plan",
  footer: "TYLOG+ / SINGLE ACTIVE PLAN",
))
#set page(margin: (top: 1.7cm, bottom: 1.7cm, x: 1.8cm))
#set text(font: ("Avenir Next", "Noto Sans"), size: 8.5pt)
#set par(spacing: 0.55em, leading: 0.52em)
#set heading(numbering: none)

#let ink = rgb("#1F2937")
#let hairline = rgb("#E5E7EB")
#let pale = rgb("#F9FAFB")

#title-block(
  "TyLog+ delivery plan",
  subtitle: "One source of truth for remaining work, acceptance, and release",
  meta-line: "Updated 2026-09-26 · Owner: project coordinator · Scope: P01–P26",
)

#callout(
  [
    *Current state — 14 of 26 milestones complete.* Twelve milestones remain open or partial: P03, P05, P12, and P18–P26. U0, the verification gate for existing controls and the earlier UI audit, is also open. The immediate critical path is verify current controls, restore real sync access, finish P05 human relevance review, close P12 editor frame acceptance, then complete native retrieval and production rehearsal. No milestone is DONE from host tests alone when its contract requires device, corpus, account, or real-use evidence.
  ],
  title: "Status at a glance",
  tone: "info",
)

= How to use this plan

This is the only active project plan. Update milestone state, next action, and evidence here. Detailed test logs remain in `evidence/`; they are evidence, not separate plans. Private vault contents, credentials, query text, source excerpts, hashes, and raw samples stay outside Git unless the evidence is explicitly redacted.

States mean: *DONE* has every acceptance item and linked evidence; *OPEN* has work left; *BLOCKED* has a concrete dependency that must change; *CONDITIONAL* runs only when its stated gate fails. Keep implementation completion separate from real-device and production acceptance.

= Project outcome and fixed decisions

TyLog is a research logbook: capture, read, annotate, connect evidence, reflect, and export. Existing Flutter screens and controls remain the product surface for this delivery. The goal is to make those paths reliable and scalable on macOS and Android, not to redesign them during acceptance.

- *One authoritative store:* Drift over native SQLite in app-private storage; WAL and foreign keys enabled; one writer isolate; versioned migrations. Nodes, typed edges, source versions, annotations, saved views, attachment references, revisions, and durable jobs have stable identities. Indexed common fields use columns; optional properties use JSON.
- *Durable edit contract:* save commits content, immutable revision, outbox entry, and derived-data invalidation atomically. A visible saved state means the commit is durable. Preserve original Typst bytes and unknown properties through export, import, and migration. Use keyset pages of 50 by default.
- *Derived indexes:* FTS5 with `unicode61 remove_diacritics 2`; refresh only changed records. Jobs deduplicate by content revision, resume and cancel, and cannot publish stale results. Interactive work outranks indexing; one embedding job runs at a time. Startup does not wait for network or indexing.
- *Sync and recovery:* keep Nextcloud/WebDAV transport under a separate v2 namespace. Upload immutable revision batches with sequence, parent, checksum, and tombstone; publish the device head only after the batch. Apply batch and receive cursor transactionally and idempotently. Detect missing batches. Preserve concurrent edits and delete/edit conflicts; never select winners by wall clock. Attachments transfer by hash. SQLite, WAL, and SHM never sync.
- *Migration safety:* keep the legacy vault and verified backup through migration. Before v2 edits, rollback can use the legacy copy. After v2 edits, recovery must preserve them through verified export; never reopen stale data over newer edits.
- *Reader and anchors:* PDFium/pdfrx supplies page text and selection. Anchors store source-version identity, page/position, quote, and context. Re-indexing retains source identity; ambiguous reattachment requires review. Image-only PDFs remain viewable and are explicitly unsearchable; OCR is deferred.
- *Retrieval:* begin with quantized multilingual-e5-small via ONNX Runtime, matching tokenization, pooling, and normalization on Mac and Android. Version model, tokenizer, dimension, and chunker. Store normalized Float32 vectors. Benchmark bounded exact cosine search in an isolate; test sqlite-vec only if the exact search gate fails. Hybrid results fuse FTS and vectors and link to stable source offsets; generated answers are out of scope.
- *Graph:* bound interactive layout to 200 nodes and 500 edges; keep saved queries/layout separate from relationships and export SVG. Bound traversal time and result size.
- *Explicit deferrals:* no live external-folder editing, shared live collaboration, OCR, cloud database, generated AI answers, DuckDB, Postgres/pgvector, or graph database. Revisit only against measured need.

= Acceptance gates

These are the release targets. Current measurements and failures are in the milestone table and evidence links below.

#table(
  columns: (1.2fr, 2.7fr, 2.1fr),
  inset: 5pt,
  align: (left, left, left),
  stroke: (x: 0.4pt + hairline, y: 0.4pt + hairline),
  fill: (x, y) => if y == 0 { rgb("#EEF5F9") } else if calc.odd(y) { pale },
  table.header(
    text(weight: 700, fill: ink)[Area],
    text(weight: 700, fill: ink)[Measurable acceptance],
    text(weight: 700, fill: ink)[Evidence rule],
  ),
  [Import], [Every source item classified; zero unexplained omissions or overwritten originals.], [Manifest, hashes, database integrity, and explicit content gaps.],
  [Startup/edit], [Cold workspace ready ≤2 s p95; note open and durable save each ≤150 ms p95 for ≤50 KB notes.], [30 startup and 100 open/save samples on a normal profile/release path.],
  [Keyword search], [First 50 results ≤200 ms p95 at full scale.], [250k searchable chunks; record device, build, corpus, p50/p95/max.],
  [Semantic search], [Query embedding plus top 20 ≤3 s warm p95; first query ≤6 s.], [Real on-device model, offline after installation; include memory.],
  [Retrieval quality], [`Recall@10` ≥85% overall and ≥80% in each query-language and cross-language group.], [90 human-judged queries; publish aggregate scores and reviewed-pack digest only.],
  [Graph], [≤500 ms p95 for bounded interactive graph operations.], [200-node/500-edge view; 100 valid foreground samples per platform and real-vault route.],
  [Frames], [Fewer than 1% of frames exceed the observed refresh-stage budget.], [Five-minute scripted editing runs; count each frame once if build OR raster exceeds budget. Report total latency separately.],
  [Android memory], [≤350 MB PSS during ordinary editing; ≤750 MB during embedding/search and heavy reader checks.], [Profile build, repeatable workload, peak PSS.],
  [Idle/jobs], [Ten unchanged minutes: zero rebuilds, content uploads, or repeated processing notifications. Cancel acknowledgment ≤250 ms and no later batch starts.], [Observe job state and content/index revisions.],
  [Sync], [Duplicate, reordered, interrupted, and retried batches converge without lost conflicts; controlled edit visible on other device ≤10 s p95.], [Real account plus fault-injected host tests; verify attachment hashes and restart.],
  [Portability], [Export/re-import preserves IDs, content, links, annotations, bibliography, and attachment hashes.], [Fresh restore, repeat import no-op, conflict retention, rollback.],
  [Initial processing], [Measure import, extraction, and embedding separately; restart resumes completed batches.], [Real corpus plus deterministic scale fixtures; synthetic chunks do not stand in for extraction throughput.],
)

= Milestone tracker

Completed milestone evidence is linked so the remaining plan stays compact. “Done with gaps” means all inputs have terminal accounting and the gaps are explicit; it does not claim those source gaps have disappeared.

#table(
  columns: (0.55fr, 2.15fr, 1.15fr, 2.4fr),
  inset: 4pt,
  align: (left, left, left, left),
  stroke: (x: 0.35pt + hairline, y: 0.35pt + hairline),
  fill: (x, y) => if y == 0 { rgb("#EEF5F9") } else if calc.odd(y) { pale },
  table.header(
    text(weight: 700, fill: ink)[ID],
    text(weight: 700, fill: ink)[Milestone],
    text(weight: 700, fill: ink)[State],
    text(weight: 700, fill: ink)[Latest evidence / remaining gap],
  ),
  [P01], [Back up and inventory phone vault], [DONE], [#link("evidence/P01/result.md")[Verified inventory: 11,826 files.]],
  [P02], [Restore production selection and release], [DONE], [#link("evidence/P02/result.md")[Vault and release persist.]],
  [P03], [Real Mac–A24 sync and existing controls], [OPEN], [#link("evidence/P03/result.md")[Cloud config must be re-entered; initial transfer was interrupted; two existing conflict cards need safe inspection.]],
  [P04], [Corpus fixtures and benchmark runner], [DONE], [#link("evidence/P04b/result.md")[Real, 10k, and 100k manifests and baseline.]],
  [P05], [Offline embedding and retrieval feasibility], [OPEN], [#link("evidence/P05/mac-quality-readiness.md")[Android model/vector/search/resume gates pass. Human review and `Recall@10` score remain.]],
  [P06], [Database bootstrap and migration tests], [DONE], [#link("evidence/P06/result.md")[Background SQLite, WAL/FK, creation, and upgrade tests.]],
  [P07], [Nodes, edges, sources, revisions], [DONE], [#link("evidence/P07/result.md")[Atomic writes, stable identity, dates, references, and migrations.]],
  [P08], [Transactional edit, outbox, and jobs], [DONE], [#link("evidence/P08/result.md")[Failure-injected all-or-nothing edit transaction.]],
  [P09], [Resumable legacy import], [DONE WITH GAPS], [#link("evidence/P09d5/result.md")[3,483/3,483 items terminal; 16 assets missing and 1,243 wikilinks unresolved.]],
  [P10], [Portable export and conflict-aware re-import], [DONE], [#link("evidence/P10/result.md")[Validated, idempotent, non-destructive round trip.]],
  [P11], [Route existing edits/buttons through database], [DONE], [#link("evidence/P11a/result.md")[Edits, deletes, creation, and import durable.]],
  [P12], [Paged startup/list reads and editor performance], [OPEN], [#link("evidence/P12e/result.md")[Startup/open/save pass. Corrected A24 frame gate fails: plain 7.56%; formatted 100% in the short smoke. Editor parity remains.]],
  [P13], [Incremental FTS and filters], [DONE], [#link("evidence/P13/result.md")[FTS5, changed-record refresh, multilingual latency and UI fallback.]],
  [P14], [Persistent processing jobs], [DONE], [#link("evidence/P14/result.md")[Resume, cancel, deduplicate, stale-result tests.]],
  [P15], [Revision upload and attachments], [DONE], [#link("evidence/P15/result.md")[Durable Nextcloud retry path for revisions and binary assets.]],
  [P16], [Transactional receive and conflict handling], [DONE], [#link("evidence/P16/result.md")[Revision envelopes decoded and parent-checked.]],
  [P17], [Snapshot bootstrap and recovery], [DONE], [#link("evidence/P17/result.md")[Archive bootstrap, resume, and damaged-state rejection.]],
  [P18], [PDF reader and versioned extraction], [OPEN], [#link("evidence/P18/result.md")[Mac private corpus and no-text rendering pass; Android PSS and password-protected behavior remain.]],
  [P19], [Durable annotations and navigation], [OPEN], [#link("evidence/P19/result.md")[Reader and anchor flows pass on Mac/A24; real account annotation sync remains.]],
  [P20], [Chunking and offline embeddings], [OPEN], [#link("evidence/P20/result.md")[Host scheduling and native adapter exist; on-device model, latency, quality, and memory gates remain.]],
  [P21], [Hybrid retrieval and cited navigation], [OPEN], [#link("evidence/P21/result.md")[Host citation/fusion seams pass; full model-to-result-to-source flow needs device acceptance.]],
  [P22], [Evidence relations and bounded graph], [OPEN], [#link("evidence/P22/result.md")[Mac synthetic graph passes; real-vault timing is invalid or above 500 ms; Android timing remains.]],
  [P23], [Complete research workflow], [OPEN], [#link("evidence/P23/result.md")[Host filtered retrieval-to-report path passes; native end-to-end workflow remains.]],
  [P24], [Migration rehearsal and integrated failures], [OPEN], [#link("evidence/P24/result.md")[Host failure matrix and isolated A24 process-death test pass; real-account/release rehearsal remains.]],
  [P25], [Production migration and release acceptance], [OPEN], [#link("evidence/P25/result.md")[macOS universal release and Android profile artifacts build; real vault/account release gate remains.]],
  [P26], [Seven-day use and thesis freeze], [TODO], [Start only after P01–P25 required gates pass; record seven consecutive days of normal use.],
)

= Remaining execution plan

The sequence is dependency-led. Work that does not need cloud credentials can proceed while account access is restored. Do not start P26’s seven-day clock until every required gate below passes.

== 0 · Verify existing controls and UI audit — U0

*Depends on:* none for host checks; A24 and Mac for native control sweep. *State:* code changes were staged in August, but `docs/ui-fix-status.md` explicitly records that `make verify` and the new tests were never run. Keep this gate open until they run.

Run `make verify` and fix any analyzer, test, or build failures. Inventory every visible button, menu item, icon action, and gesture on each main app surface; record the inventory count and IDs, then show 100% of current actions have a verified outcome or a named platform limitation. Verify the existing regression guards rather than trusting source scans alone: all non-text colors meet the 3:1 contrast floor; custom interactive targets are at least 48 dp; no existing action depends only on long-press; saved task/article/status changes render from persisted state; failed saves preserve edits; highlighting choices, filters, reader actions, graph export, and Typst export remain reachable and functional. The original 15 UI work packages and measured source metrics are preserved in the archived audit records linked from `docs/ui-fix-status.md`.

On Mac and A24, exercise each current control in its real app surface and record pass/fail against this checklist: create/open/edit/save; task completion and status; article delete/status/relevance/rating; search and filters; saved views; all highlight choices; PDF select/save/reopen/reassign; graph filters and SVG share; filtered Typst report/export. A failure must leave committed data intact and show a recoverable result.

*Close when:* `make verify` passes; the contrast and 48 dp gates pass; every inventoried control has a test result on its supported platform; no current action is omitted; no silent edit loss, wrong destination, or crash occurs. No UI redesign is required by U0.

== 1 · Restore real sync safely — P03

*Depends on:* P01, P02. *State:* blocked on app-local cloud configuration; the last recorded device state has the production vault reselected, but the profile test reset app-private configuration. Do not infer the account is configured from USB connection alone.

Re-enter the existing Mac and A24 account configuration, install profile builds in place, and resume the safe merge. Complete the initial transfer before testing. Inspect the two existing conflict records by stable ID, timestamp, and snapshot hash against the verified backup before resolving either. Do not record credentials, test by uninstalling/clearing the production package, or start an unverified overwrite.

*Close when:* Mac↔A24 small edits pass in both directions; a concurrent same-note edit is preserved as a reviewable conflict on both devices; an attachment hash matches after round trip and cold restart; the initial sync finishes with counts and no unexplained data loss. Reconcile each pre-existing conflict explicitly.

== 2 · Finish judged retrieval quality — P05

*Depends on:* P04; Android exact-search and durable-resume evidence is already accepted. *State:* waiting for human review.

Use the private `P05-human-review-v2.pdf` to read the 90 candidate query/passage pairs and enter final labels in `p05-human-review-worklist-v2.tsv`. Review 30 EN, 30 PT, and 30 RU queries; each group contains 10 cross-language cases. Mark relevant, not relevant, or unresolved; add any missed relevant passage IDs. Resolve the flagged mixed-language Russian query. Keep source excerpts, query text, paths, identifiers, and vectors outside Git.

Run the scorer only when all 90 judgments are resolved. Record the private reviewed-pack digest and runtime metadata outside Git, and add only aggregate scores to the evidence report.

*Close when:* `Recall@10` is at least 85% overall, 80% in each language, and 80% in the cross-language subset; pack validation passes; scorer command and aggregate-only result reproduce. If a threshold fails, fix retrieval/model behavior and rerun the same frozen judged set. Run sqlite-vec only if exact search misses its established latency or memory gate.

== 3 · Close editor frame and behavior acceptance — P12

*Depends on:* P11. *State:* startup/open/save pass; frame and full editor-parity gates fail or remain unverified.

The corrected metric counts a frame once when build or raster exceeds the observed refresh-stage budget; report total interaction latency separately. The corrected A24 300-second plain run recorded 83/1,098 violations (7.56%) at 90 Hz; the formatted diagnostic recorded 56/56 (100%) at 120 Hz and missed its minimum workload. A DevTools trace attributes most formatted edit cost to `RenderEditable` layout (74.38 ms mean in the diagnostic). Quill's isolated short run passed while its earlier matched candidate run failed; this variance is unresolved. No editor replacement is approved by that one short pass.

First reconcile candidate variance with a fixed device/host-load/viewport/focus/fixture and measurement procedure. Then change the expensive layout path only if a trace confirms the cause. Preserve source bytes, formatting, headers, document-wide selection, cross-paragraph operations, IME/composition, paste, undo/redo, autosave, and real keyboard behavior. Do not enable a candidate until the host parity suite passes.

*Close when:* on A24 profile build, the plain 900-row workload runs 300 seconds with at least 1,100 real edits, and the formatted 900-row workload runs 300 seconds with at least 60 edits; each has less than 1% over-budget frames, stable measured refresh rate, no app hang, and passing source/format/behavior assertions. Also retain the existing 30-startup and 100-open/save profile gates (p95 ≤2,000/150/150 ms).

== 4 · Finish reader and annotation gates — P18, P19

*Depends on:* P07, P14. P19 sync acceptance also depends on P03.

On Android profile, open the five-PDF private corpus sequentially and record extraction coverage, failures, and peak PSS. Keep the ordinary editing/heavy-operation memory limits in the acceptance table. Test password-protected PDFs: the reader must either open and extract them correctly after an explicit password flow, or report a stable recoverable unsupported/password-required state without corrupting annotations or source versions. Scanned-image OCR stays deferred; image-only input must remain viewable and explicitly unsearchable.

Run annotation save, close/reopen, navigation, exact reattachment, ambiguous reattachment review, and manual reassignment on both platforms. Then use the real account to sync annotation revision envelopes both directions and verify parent-conflict behavior.

*Close P18 when:* all five PDFs are accounted for, the no-text PDF remains viewable, extraction offsets match the host contract, password behavior is explicit, there are no crashes, and peak A24 PSS stays within the 750 MB heavy-operation ceiling. *Close P19 when:* selection/save/reopen/navigation and ambiguous review pass on both platforms, and remote annotation revisions converge without silent overwrite.

== 5 · Run on-device embedding and hybrid retrieval — P20, P21

*Depends on:* P05, P14, P18, P19, and P13 as listed in the milestone graph.

On both Mac and A24, run the pinned ONNX model offline after installation. Verify query/passage vector parity against the frozen reference (cosine similarity ≥0.999 and maximum absolute difference ≤0.02) and verify chunking/tokenization/pooling/normalization versions. Exercise interrupted embedding and resume; confirm stale vectors cannot publish. Measure initial and warm query latency and peak PSS on 250,000 representative searchable chunks. Keep the quality set frozen while making implementation changes.

Wire the actual search action through query embedding, FTS and vector candidate retrieval, reciprocal-rank fusion, result display, and tap navigation to the correct source version and offset. Test missing/stale sources, duplicate candidates, cancellation, offline first-use, and back navigation.

*Close P20 when:* passage/query vectors meet those parity thresholds on both platforms, jobs resume deterministically, semantic query/top-20 meets ≤3 s warm p95 and ≤6 s first-query latency, and PSS stays ≤750 MB. *Close P21 when:* the in-app path returns stable citations to the expected source/version/offset and meets P05 quality gates on Mac and A24 with no network dependency after model installation.

== 6 · Close bounded graph performance — P22

*Depends on:* P07, P12.

Keep the 200-node/500-edge ceiling. The current private 6,298-note route successfully opened a selected note with zero attempted vault writes, but Flutter could not reliably foreground the app and the observed mode-switch p95 values (926 ms Concept map; 689 ms All files) exceed 500 ms. Treat them as diagnostic failure signals, not valid acceptance samples. Direct-stage timings do not substitute for complete visible interaction timing.

Fix the profile harness so foreground, focus, selected node, view, and settled state are asserted before every sample. Collect at least 100 valid foreground interactions per graph mode on Mac and A24 with the real vault read-only. If p95 remains above 500 ms, trace the complete route and optimize; rerun the same gates. Recheck SVG export and target handoff after any graph change.

*Close when:* each platform/mode has 100 valid samples, p95 ≤500 ms, selection opens the intended note, export remains valid, and before/after real-vault manifests match exactly.

== 7 · Validate the complete research workflow — P23

*Depends on:* P19, P21, P22.

Exercise the existing app controls end to end: filter a research set, retrieve and open a source-linked passage, save or reassign an annotation, follow its source anchor, and export deterministic Typst with the selected notes and bibliography. Validate that a stale retrieval row cannot navigate to the wrong note and that results remain usable offline.

*Close when:* the same scripted workflow passes on Mac and A24 with the real app and storage adapter; selected records, source offsets, bibliography, and export bytes are verified; the report opens in the existing Typst flow; every failure leaves edits and source data recoverable.

== 8 · Production migration, release, and seven-day use — P24, P25, P26

*Depends on:* all preceding required gates; P25 depends on P03 and P24.

Repeat migration on a fresh verified copy of the real vault, never the only production copy. Exercise permission loss, low disk, process death during migration, interrupted sync, restore, and conflict cases with a normal production-shaped release. Verify before/after manifest and attachment hashes and run export/re-import. Produce and launch the signed universal macOS release and normal Android release/profile package; install over the existing phone package with `adb install -r`, never uninstall or clear app data during acceptance.

*Close P24 when:* all injected and real process-death checkpoints recover to a valid old or new state with no missing committed edit, and the real account sync/restore path passes. *Close P25 when:* migration, release launch, production vault integrity, two-way sync, conflict recovery, and restart all pass on Mac and A24 with redacted evidence. *Close P26 when:* seven consecutive days of normal use cover capture/edit, search, reader/annotations, graph, export, sync, background/foreground, and cold restart; zero crashes, lost committed edits, unexplained missing records, or repeating idle processing notifications are observed. Reset the seven-day window after any failed required gate.

= Dependency order and parallelism

#table(
  columns: (0.8fr, 3.8fr, 1.8fr),
  inset: 5pt,
  stroke: (x: 0.4pt + hairline, y: 0.4pt + hairline),
  fill: (x, y) => if y == 0 { rgb("#EEF5F9") } else if calc.odd(y) { pale },
  table.header(
    text(weight: 700, fill: ink)[Wave],
    text(weight: 700, fill: ink)[Work],
    text(weight: 700, fill: ink)[Exit condition],
  ),
  [A], [U0 host verification; P03 account re-entry and safe initial sync; P05 human relevance review and scoring.], [Existing controls verified; real sync usable; quality gate scored.],
  [B], [P12 editor parity/frame fix; P18 Android reader/password/memory; P22 valid graph timings. These can proceed independently with disjoint files.], [Each local/device gate passes with reproducible evidence.],
  [C], [P19 annotation sync; P20 on-device embedding; P21 in-app hybrid cited search.], [P05 quality plus native end-to-end retrieval pass.],
  [D], [P23 workflow, P24 failure/migration rehearsal, P25 release and production acceptance.], [Real-vault integrity and two-device acceptance pass.],
  [E], [P26 seven-day normal use.], [Seven consecutive days meet the use contract.],
)

Use at most two implementation agents plus one reviewer at a time, with non-overlapping file ownership. Prefer simple models for bounded implementation or test tasks; give each only this plan, its ticket, and required contracts/evidence. The coordinator reviews every diff, runs focused checks and broader acceptance, owns device/destructive steps, and updates this plan before committing. Record observed model and usage only when exposed; unavailable usage is not zero. Unload local inference before performance runs.

= Completion checklist

- [ ] U0 existing controls and UI regression audit passes on host, Mac, and A24.
- [ ] P03–P05 gates closed and linked evidence current.
- [ ] P12 frame and editing parity gates pass on A24 profile.
- [ ] P18–P23 native reader, annotation sync, retrieval, graph, and workflow gates pass on Mac and A24.
- [ ] P24 migration/failure rehearsal passes on a verified copy and real account.
- [ ] P25 release build, install, production-vault integrity, sync, and recovery pass.
- [ ] P26 records seven consecutive successful days; final evidence is redacted.
- [ ] Plan state reflects the latest results; no remaining ticket is OPEN, BLOCKED, or CONDITIONAL without a named owner/next action.
