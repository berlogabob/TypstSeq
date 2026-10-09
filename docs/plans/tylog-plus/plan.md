# TyLog+ delivery plan

> **Markdown reading copy — updated 2026-10-06.** The canonical plan is [`plan.typ`](plan.typ); update it first and keep this copy aligned. [`plan.pdf`](plan.pdf) is the reader version. This is one plan with multiple formats, not a second tracker.

**Owner:** Project coordinator · **Scope:** P01–P26  
**Current state (2026-10-06):** 22 of 26 milestones complete; 2 WAIVED; U0 verified on host, Mac and A24. P05 (90 relevance labels) and P21 are WAIVED by the user on 2026-10-06: search quality is judged by real use instead. Open: P12 (real-keyboard/IME hand check on the A24, owner: user) and P26 (seven-day use, starts when P12 passes). A milestone is not DONE from host tests alone when its contract requires device, corpus, account, or real-use evidence.

**2026-10-04 maintenance:** Sync fix `f3667ed` throttles autosave syncs to 2 min,
retries transient 5xx/52x responses, and shows “Offline — changes saved, will
sync” for transient automatic failures (escalates after three consecutive
failures or 10 min). Note close and backgrounding still sync immediately.
[Phone trace and fix](evidence/P25/2026-10-04-sync-calm.md). Revision-per-save
coalescing was attempted and reverted; remains a follow-up. `3221ad6` makes
Preview a continuous screen-wide page, adds Settings → PDF page size
(A4 default, Letter, A5, Legal), and gives the four view-mode items icons and
a current-mode check. Customized `_system/theme.typ` is preserved. Follow-ups:
`75ac4c0` upgrades real v1 theme copies (they lack the bundle's trailing blank
line); `bb334ea` sets the page ahead of the source in Preview and export, because
plain-Typst notes (phone dailies have no `#show: tylog.note`) never reach the theme.
Housekeeping: Mac `/Applications` app updated to the latest release; Maestro
helper removed from the A24.

## How to use this plan

This is the only active project plan. Update milestone state, next action, and evidence in the canonical Typst source. Detailed test logs remain in `evidence/`; they are evidence, not separate plans. Private vault contents, credentials, query text, source excerpts, hashes, and raw samples stay outside Git unless evidence is explicitly redacted.

States mean: **DONE** has every acceptance item and linked evidence; **OPEN** has work left; **BLOCKED** has a concrete dependency that must change; **CONDITIONAL** runs only when its stated gate fails; **WAIVED** is explicitly waived by the user, with date and reason recorded. Keep implementation completion separate from real-device and production acceptance.

## Project outcome and fixed decisions

TyLog is a research logbook: capture, read, annotate, connect evidence, reflect, and export. Existing Flutter screens and controls remain the product surface for this delivery. The goal is to make those paths reliable and scalable on macOS and Android, not to redesign them during acceptance.

- **Persistence:** Typst files are authoritative for note content. Drift over private native SQLite stores projections, annotations, revisions, and jobs; WAL and foreign keys are enabled, with one writer isolate and versioned migrations. SQLite, WAL, and SHM never sync.
- **Durable edit contract:** save writes the note file first, then commits its projection, revision, outbox entry, and invalidation in one database transaction. A projection failure preserves the successful file write, reports the error, and leaves retry markers; filesystem and database writes are not one atomic transaction. Preserve original Typst bytes and unknown properties through export, import, and migration. Use keyset pages of 50 by default.
- **Derived indexes:** FTS5 with `unicode61 remove_diacritics 2`; refresh only changed records. Jobs deduplicate by content revision, resume and cancel, and cannot publish stale results. Interactive work outranks indexing; one embedding job runs at a time. Startup does not wait for network or indexing.
- **Sync and recovery:** ordinary Nextcloud/WebDAV file sync transports session envelopes in `_system/revisions`. New unpublished local heads coalesce in fixed 60-second windows; materialized/uploaded revisions and conflict bases are sealed. Envelopes retain parent history for idempotent ancestry checks; failed writes leave outbox work pending. Preserve concurrent edits and delete/edit conflicts; never select winners by wall clock. This replaces the proposed separate v2 batch/device-head transport.
- **Migration safety:** keep the legacy vault and verified backup through migration. Before v2 edits, rollback can use the legacy copy. After v2 edits, recovery must preserve them through verified export; never reopen stale data over newer edits.
- **Reader and anchors:** PDFium/pdfrx supplies page text and selection. Anchors store source-version identity, page/position, quote, and context. Re-indexing retains source identity; ambiguous reattachment requires review. Image-only PDFs remain viewable and are explicitly unsearchable; OCR is deferred.
- **Retrieval:** begin with quantized multilingual-e5-small via ONNX Runtime, matching tokenization, pooling, and normalization on Mac and Android. Version model, tokenizer, dimension, and chunker. Store normalized Float32 vectors. Benchmark bounded exact cosine search in an isolate; test sqlite-vec only if the exact search gate fails. Hybrid results fuse FTS and vectors and link to stable source offsets; generated answers are out of scope.
- **Graph:** bound interactive layout to 200 nodes and 500 edges; keep saved queries/layout separate from relationships and export SVG. Bound traversal time and result size.
- **Explicit deferrals:** no live external-folder editing, shared live collaboration, OCR, cloud database, generated AI answers, DuckDB, Postgres/pgvector, or graph database. Revisit only against measured need.

## Acceptance gates

Current measurements and failures are in the milestone table and linked evidence.

| Area | Measurable acceptance | Evidence rule |
|---|---|---|
| Import | Every source item classified; zero unexplained omissions or overwritten originals. | Manifest, hashes, database integrity, and explicit content gaps. |
| Startup/edit | Cold workspace ready ≤2 s p95; note open and durable save each ≤150 ms p95 for ≤50 KB notes. | 30 startup and 100 open/save samples on a normal profile/release path. |
| Keyword search | First 50 results ≤200 ms p95 at full scale. | 250k searchable chunks; record device, build, corpus, p50/p95/max. |
| Semantic search | Query embedding plus top 20 ≤3 s warm p95; first query ≤6 s. | Real on-device model, offline after installation; include memory. |
| Retrieval quality | WAIVED by the user on 2026-10-06; search quality is judged by real use instead. | P05: 90 relevance labels and Recall@10 scoring waived; P21 waived. |
| Graph | ≤500 ms p95 for bounded interactive graph operations. | 200-node/500-edge view; 100 valid foreground samples per platform and real-vault route. |
| Frames | Fewer than 1% of frames exceed the observed refresh-stage budget. | Five-minute scripted editing runs; count a frame once if build **or** raster exceeds budget. Report total latency separately. |
| Android memory | ≤350 MB PSS during ordinary editing; ≤750 MB during embedding/search and heavy reader checks. | Profile build, repeatable workload, peak PSS. |
| Idle/jobs | Ten unchanged minutes: zero rebuilds, content uploads, or repeated processing notifications. Cancel acknowledgment ≤250 ms and no later batch starts. | Observe job state and content/index revisions. |
| Sync | Duplicate, reordered, interrupted, and retried batches converge without lost conflicts; controlled edit visible on other device ≤10 s p95. | Real account plus fault-injected host tests; verify attachment hashes and restart. |
| Portability | Export/re-import preserves IDs, content, links, annotations, bibliography, and attachment hashes. | Fresh restore, repeat import no-op, conflict retention, rollback. |
| Initial processing | Measure import, extraction, and embedding separately; restart resumes completed batches. | Real corpus plus deterministic scale fixtures; synthetic chunks do not stand in for extraction throughput. |

## Milestone tracker

Completed milestone evidence is linked so the remaining plan stays compact. “Done with gaps” means all inputs have terminal accounting and the gaps are explicit; it does not claim those source gaps have disappeared.

| ID | Milestone | State | Latest evidence / remaining gap |
|---|---|---|---|
| P01 | Back up and inventory phone vault | DONE | [Verified inventory: 11,826 files](evidence/P01/result.md). |
| P02 | Restore production selection and release | DONE | [Vault and release persist](evidence/P02/result.md). |
| P03 | Real Mac–A24 sync and existing controls | DONE | [A24 reconnected; initial sync 12,238 files; 23 conflicts reconciled; two-way edits, concurrent conflict (A24 review), attachments + cold restart pass](evidence/P03/result.md). |
| P04 | Corpus fixtures and benchmark runner | DONE | [Real, 10k, and 100k manifests and baseline](evidence/P04b/result.md). |
| P05 | Offline embedding and retrieval feasibility | WAIVED | [User waiver, 2026-10-06: 90 relevance labels waived; search quality judged by real use](evidence/P05/mac-quality-readiness.md). |
| P06 | Database bootstrap and migration tests | DONE | [Background SQLite, WAL/FK, creation, and upgrade tests](evidence/P06/result.md). |
| P07 | Nodes, edges, sources, revisions | DONE | [Atomic writes, stable identity, dates, references, and migrations](evidence/P07/result.md). |
| P08 | Transactional edit, outbox, and jobs | DONE | [Failure-injected all-or-nothing edit transaction](evidence/P08/result.md). |
| P09 | Resumable legacy import | DONE WITH GAPS | [3,483/3,483 items terminal; 16 assets missing and 1,243 wikilinks unresolved](evidence/P09d5/result.md). |
| P10 | Portable export and conflict-aware re-import | DONE | [Validated, idempotent, non-destructive round trip](evidence/P10/result.md). |
| P11 | Route existing edits/buttons through database | DONE | [Edits, deletes, creation, and import durable](evidence/P11a/result.md). |
| P12 | Paged startup/list reads and editor performance | OPEN | [A24 at 120 Hz with the bounded window: plain 0.58%, formatted 0.91% over budget (<1%); real-keyboard/IME check by hand remains](evidence/P12e/a24-window.md). |
| P13 | Incremental FTS and filters | DONE | [FTS5, changed-record refresh, multilingual latency and UI fallback](evidence/P13/result.md). |
| P14 | Persistent processing jobs | DONE | [Resume, cancel, deduplicate, stale-result tests](evidence/P14/result.md). |
| P15 | Revision upload and attachments | DONE | [Durable Nextcloud retry path for revisions and binary assets](evidence/P15/result.md). |
| P16 | Transactional receive and conflict handling | DONE | [Revision envelopes decoded and parent-checked](evidence/P16/result.md). |
| P17 | Snapshot bootstrap and recovery | DONE | [Archive bootstrap, resume, and damaged-state rejection](evidence/P17/result.md). |
| P18 | PDF reader and versioned extraction | DONE | [5/5 private PDFs on Mac and A24 (identical extraction); explicit password flow; A24 peak PSS 312 MB](evidence/P18/result.md). |
| P19 | Durable annotations and navigation | DONE | [Reader, anchor and ambiguous review pass on Mac/A24; real-account annotation sync both ways with conflict preservation (2026-10-03)](evidence/P19/result.md). |
| P20 | Chunking and offline embeddings | DONE | [Mac+A24 query/passage parity 1.000000; A24 250k + model: first 952 ms, warm p95 230 ms, PSS 736 MB](evidence/P20/result.md). |
| P21 | Hybrid retrieval and cited navigation | WAIVED | [Native download-index-search-navigate passes on Mac, P30 and A24; real-vault index 65 chunks/s on Mac profile. User waived P21 on 2026-10-06; search quality judged by real use](evidence/P21/a24-native.md). |
| P22 | Evidence relations and bounded graph | DONE | [Real vault read-only, 100/100 valid per mode: A24 p95 46 ms, Mac p95 18 ms; note opens; manifests identical](evidence/P22/result.md). |
| P23 | Complete research workflow | DONE | [Six-step native workflow passes on Mac, P30 and A24; identical report bytes](evidence/P21/a24-native.md). |
| P24 | Migration rehearsal and integrated failures | DONE | [Real-account rehearsal on a real-vault sample: interrupted sync, restore, conflict, restart, export/re-import pass; NFD data-loss and 423 bugs fixed](evidence/P24/result.md). |
| P25 | Production migration and release acceptance | DONE | [A24 release install, vault integrity (0 missing/changed), safe merge, two-way, conflict resolution, cold restart; macOS universal release launch](evidence/P25/result.md). |
| P26 | Seven-day use and thesis freeze | TODO | Start only after P01–P25 required gates pass; record seven consecutive days of normal use. |

## Remaining execution plan

The sequence is dependency-led. Work that does not need cloud credentials can proceed while account access is restored. Do not start P26’s seven-day clock until every required gate below passes.

### 0 · Verify existing controls and UI audit — U0

**Depends on:** none for host checks; A24 and Mac for native control sweep. **State:** code changes were staged in August, but `docs/ui-fix-status.md` explicitly records that `make verify` and the new tests were never run. Keep this gate open until they run.

Run `make verify` and fix any analyzer, test, or build failures. Inventory every visible button, menu item, icon action, and gesture on each main app surface; record the inventory count and IDs, then show 100% of current actions have a verified outcome or a named platform limitation. Verify the existing regression guards rather than trusting source scans alone: all non-text colors meet the 3:1 contrast floor; custom interactive targets are at least 48 dp; no existing action depends only on long-press; saved task/article/status changes render from persisted state; failed saves preserve edits; highlighting choices, filters, reader actions, graph export, and Typst export remain reachable and functional. The original 15 UI work packages and measured source metrics are preserved in the archived audit records linked from `docs/ui-fix-status.md`.

On Mac and A24, exercise each current control in its real app surface and record pass/fail against this checklist: create/open/edit/save; task completion and status; article delete/status/relevance/rating; search and filters; saved views; all highlight choices; PDF select/save/reopen/reassign; graph filters and SVG share; filtered Typst report/export. A failure must leave committed data intact and show a recoverable result.

**Close when:** `make verify` passes; the contrast and 48 dp gates pass; every inventoried control has a test result on its supported platform; no current action is omitted; no silent edit loss, wrong destination, or crash occurs. No UI redesign is required by U0.

### 1 · Restore real sync safely — P03

**Depends on:** P01, P02. **State:** blocked on app-local cloud configuration; the last recorded device state has the production vault reselected, but the profile test reset app-private configuration. Do not infer the account is configured from USB connection alone.

Re-enter the existing Mac and A24 account configuration, install profile builds in place, and resume the safe merge. Complete the initial transfer before testing. Inspect the two existing conflict records by stable ID, timestamp, and snapshot hash against the verified backup before resolving either. Do not record credentials, test by uninstalling/clearing the production package, or start an unverified overwrite.

**Close when:** Mac↔A24 small edits pass in both directions; a concurrent same-note edit is preserved as a reviewable conflict on both devices; an attachment hash matches after round trip and cold restart; the initial sync finishes with counts and no unexplained data loss. Reconcile each pre-existing conflict explicitly.

### 2 · Judged retrieval quality — P05 WAIVED

WAIVED by the user on 2026-10-06: the 90 relevance labels and Recall@10 scoring are no longer required. Search quality is judged by real use instead. Existing numerical, device, and runtime evidence remains historical evidence; no judged quality score is claimed.

### 3 · Close editor frame and behavior acceptance — P12

**Depends on:** P11. **State:** startup/open/save pass; frame and full editor-parity gates fail or remain unverified.

The corrected metric counts a frame once when build or raster exceeds the observed refresh-stage budget; report total interaction latency separately. The corrected A24 300-second plain run recorded 83/1,098 violations (7.56%) at 90 Hz; the formatted diagnostic recorded 56/56 (100%) at 120 Hz and missed its minimum workload. A DevTools trace attributes most formatted edit cost to `RenderEditable` layout (74.38 ms mean in the diagnostic). Quill's isolated short run passed while its earlier matched candidate run failed; this variance is unresolved. No editor replacement is approved by that one short pass.

First reconcile candidate variance with a fixed device/host-load/viewport/focus/fixture and measurement procedure. Then change the expensive layout path only if a trace confirms the cause. Preserve source bytes, formatting, headers, document-wide selection, cross-paragraph operations, IME/composition, paste, undo/redo, autosave, and real keyboard behavior. Do not enable a candidate until the host parity suite passes.

**Close when:** on A24 profile build, the plain 900-row workload runs 300 seconds with at least 1,100 real edits, and the formatted 900-row workload runs 300 seconds with at least 60 edits; each has less than 1% over-budget frames, stable measured refresh rate, no app hang, and passing source/format/behavior assertions. Also retain the existing 30-startup and 100-open/save profile gates (p95 ≤2,000/150/150 ms).

### 4 · Finish reader and annotation gates — P18, P19

**Depends on:** P07, P14. P19 sync acceptance also depends on P03.

On Android profile, open the five-PDF private corpus sequentially and record extraction coverage, failures, and peak PSS. Keep the ordinary editing/heavy-operation memory limits in the acceptance table. Test password-protected PDFs: the reader must either open and extract them correctly after an explicit password flow, or report a stable recoverable unsupported/password-required state without corrupting annotations or source versions. Scanned-image OCR stays deferred; image-only input must remain viewable and explicitly unsearchable.

Run annotation save, close/reopen, navigation, exact reattachment, ambiguous reattachment review, and manual reassignment on both platforms. Then use the real account to sync annotation revision envelopes both directions and verify parent-conflict behavior.

**Close P18 when:** all five PDFs are accounted for, the no-text PDF remains viewable, extraction offsets match the host contract, password behavior is explicit, there are no crashes, and peak A24 PSS stays within the 750 MB heavy-operation ceiling. **Close P19 when:** selection/save/reopen/navigation and ambiguous review pass on both platforms, and remote annotation revisions converge without silent overwrite.

### 5 · Run on-device embedding and hybrid retrieval — P20, P21

**Depends on:** P05, P14, P18, P19, and P13 as listed in the milestone graph.

On both Mac and A24, run the pinned ONNX model offline after installation. Verify query/passage vector parity against the frozen reference (cosine similarity ≥0.999 and maximum absolute difference ≤0.02) and verify chunking/tokenization/pooling/normalization versions. Exercise interrupted embedding and resume; confirm stale vectors cannot publish. Measure initial and warm query latency and peak PSS on 250,000 representative searchable chunks. Search quality is judged by real use instead (user waiver, 2026-10-06).

Wire the actual search action through query embedding, FTS and vector candidate retrieval, reciprocal-rank fusion, result display, and tap navigation to the correct source version and offset. Test missing/stale sources, duplicate candidates, cancellation, offline first-use, and back navigation.

**Close P20 when:** passage/query vectors meet those parity thresholds on both platforms, jobs resume deterministically, semantic query/top-20 meets ≤3 s warm p95 and ≤6 s first-query latency, and PSS stays ≤750 MB. **P21: WAIVED by the user on 2026-10-06; search quality is judged by real use instead.**

### 6 · Close bounded graph performance — P22

**Depends on:** P07, P12.

Keep the 200-node/500-edge ceiling. The current private 6,298-note route successfully opened a selected note with zero attempted vault writes, but Flutter could not reliably foreground the app and the observed mode-switch p95 values (926 ms Concept map; 689 ms All files) exceed 500 ms. Treat them as diagnostic failure signals, not valid acceptance samples. Direct-stage timings do not substitute for complete visible interaction timing.

Fix the profile harness so foreground, focus, selected node, view, and settled state are asserted before every sample. Collect at least 100 valid foreground interactions per graph mode on Mac and A24 with the real vault read-only. If p95 remains above 500 ms, trace the complete route and optimize; rerun the same gates. Recheck SVG export and target handoff after any graph change.

**Close when:** each platform/mode has 100 valid samples, p95 ≤500 ms, selection opens the intended note, export remains valid, and before/after real-vault manifests match exactly.

### 7 · Validate the complete research workflow — P23

**Depends on:** P19, P21, P22.

Exercise the existing app controls end to end: filter a research set, retrieve and open a source-linked passage, save or reassign an annotation, follow its source anchor, and export deterministic Typst with the selected notes and bibliography. Validate that a stale retrieval row cannot navigate to the wrong note and that results remain usable offline.

**Close when:** the same scripted workflow passes on Mac and A24 with the real app and storage adapter; selected records, source offsets, bibliography, and export bytes are verified; the report opens in the existing Typst flow; every failure leaves edits and source data recoverable.

### 8 · Production migration, release, and seven-day use — P24, P25, P26

**Depends on:** all preceding required gates; P25 depends on P03 and P24.

Repeat migration on a fresh verified copy of the real vault, never the only production copy. Exercise permission loss, low disk, process death during migration, interrupted sync, restore, and conflict cases with a normal production-shaped release. Verify before/after manifest and attachment hashes and run export/re-import. Produce and launch the signed universal macOS release and normal Android release/profile package; install over the existing phone package with `adb install -r`, never uninstall or clear app data during acceptance.

**Close P24 when:** all injected and real process-death checkpoints recover to a valid old or new state with no missing committed edit, and the real account sync/restore path passes. **Close P25 when:** migration, release launch, production vault integrity, two-way sync, conflict recovery, and restart all pass on Mac and A24 with redacted evidence. **Close P26 when:** seven consecutive days of normal use cover capture/edit, search, reader/annotations, graph, export, sync, background/foreground, and cold restart; zero crashes, lost committed edits, unexplained missing records, or repeating idle processing notifications are observed. Reset the seven-day window after any failed required gate.

## Dependency order and parallelism

| Wave | Work | Exit condition |
|---|---|---|
| A | U0 host verification; P03 account re-entry and safe initial sync; P05 user waiver (2026-10-06). | Existing controls verified; real sync usable; search quality judged by real use. |
| B | P12 editor parity/frame fix; P18 Android reader/password/memory; P22 valid graph timings. These can proceed independently with disjoint files. | Each local/device gate passes with reproducible evidence. |
| C | P19 annotation sync; P20 on-device embedding; P21 in-app hybrid cited search. | P05/P21 waived by the user on 2026-10-06; search quality judged by real use. |
| D | P23 workflow, P24 failure/migration rehearsal, P25 release and production acceptance. | Real-vault integrity and two-device acceptance pass. |
| E | P26 seven-day normal use. | Seven consecutive days meet the use contract. |

Use at most two implementation agents plus one reviewer at a time, with non-overlapping file ownership. Prefer simple models for bounded implementation or test tasks; give each only this plan, its ticket, and required contracts/evidence. The coordinator reviews every diff, runs focused checks and broader acceptance, owns device/destructive steps, and updates the canonical plan before committing. Record observed model and usage only when exposed; unavailable usage is not zero. Unload local inference before performance runs.

## Completion checklist

- [x] U0 existing controls and UI regression audit passes on host, Mac, and A24.
- [ ] P03–P05 gates closed and linked evidence current.
- [ ] P12 frame and editing parity gates pass on A24 profile.
- [ ] P18–P23 native reader, annotation sync, retrieval, graph, and workflow gates pass on Mac and A24.
- [x] P24 migration/failure rehearsal passes on a verified copy and real account.
- [x] P25 release build, install, production-vault integrity, sync, and recovery pass.
- [ ] P26 records seven consecutive successful days; final evidence is redacted.
- [ ] Plan state reflects the latest results; no remaining ticket is OPEN, BLOCKED, or CONDITIONAL without a named owner/next action.
