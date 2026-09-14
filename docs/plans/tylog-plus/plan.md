# TyLog+ scalable research workspace

Accepted 2026-09-14. This is the execution contract for P01–P26. The coordinator owns acceptance; see [tasks.md](tasks.md) for live state.

## Confirmed decisions

- Research logbook first: capture → read → annotate → connect evidence → reflect → export.
- Flutter UI and existing editor; SQLite/Drift is the authoritative store, in a background isolate. Keep Rust Typst compilation.
- Mac and Android A024; 100,000 nodes, 1,000,000 edges, 250,000 searchable chunks.
- English, Portuguese, Russian; offline document and query embeddings on the phone after model installation.
- Typst remains editable record content and an explicit export/import format. No live external-folder editing in this release.
- Preserve workspace privacy/storage boundaries; research/teaching are presets over one typed model.
- Recover production phone use before production migration. Synthetic device tests cannot close production acceptance.
- No calendar freeze date supplied. Shared live collaboration, genealogy presets, OCR, cloud databases and generated AI answers are deferred. Image-only sources remain readable/exportable and are labelled unsearchable.

## Storage and edit contract

Use native SQLite in app-private storage, WAL and foreign keys enabled, one writer isolate. Pin a supported SQLite release containing the WAL-reset fix. Databases, WAL and SHM never travel through file sync. Large immutable attachments live in hash-addressed local files.

Authoritative entities: nodes, typed edges, source versions, annotations, saved views, attachment references and revisions. Derived local entities: chunks, FTS entries, embeddings and processing jobs. UUID identity is independent of file paths. Queryable common fields use indexed columns; optional attributes use JSON. Dates describing events are distinct from creation/modification timestamps. Wall clocks never choose conflict winners.

An accepted edit commits content, revision, outbox entry and derived-data invalidation atomically. Saved means committed. Preserve original Typst bytes and unknown properties through migration/export. Serialize schema changes and expose versioned migration tests.

Paged reads default to 50 results using keyset pagination. FTS5 uses `unicode61 remove_diacritics 2`, updated for changed content only. Persistent jobs deduplicate by content revision, resume and cancel; obsolete results cannot publish. Interactive work outranks indexing. One embedding job runs at once. Startup is independent of network and index completion.

## Synchronization and recovery

Retain Nextcloud/WebDAV transport with a separate v2 namespace. Immutable revision batches carry device sequence numbers, parent revisions, checksums and tombstones. Publish the device head only after batch upload. Apply each received batch and receive cursor in one transaction; duplicates are idempotent and missing batches are detected.

Concurrent revisions and delete/edit races preserve all conflicting content. Before P16 implementation, specify deterministic materialization of a conflicted entity and referential integrity under concurrent edge edits; no silent last-writer-wins. Attachments transfer by hash and may remain pending while records are usable.

New devices bootstrap from verified logical snapshots plus later batches. Keep revision history in this release; history growth is measured, not claimed unbounded. Automatic pruning requires a later acknowledged-device retirement protocol.

Keep legacy vault and verified backup during migration. Before cutover, rollback uses the legacy copy; after v2 edits, recovery must preserve those edits through verified export, never simply reopen stale legacy data.

## Reading, graphs and retrieval

Use pdfrx/PDFium for PDF reading and text selection. Anchors carry source-version identity, page/position, quote and context. Re-indexing retains source identity; ambiguous reattachment needs review. Unsupported/image-only PDFs are accounted for, not silently dropped.

Reuse Flutter graph rendering with bounded subgraphs (200 nodes, 500 edges initially). Persist view queries/layout overrides separately from relationships; export SVG. Bound recursive traversal time and results.

Start the feasibility benchmark with quantized multilingual-e5-small through ONNX Runtime. Tokenization, pooling and normalization match across devices. Store model/tokenizer/dimension/chunker versions. Pin runtime only after P05 passes; CPU first, acceleration only if measured necessary.

Store normalized Float32 vectors. Benchmark bounded exact cosine search in an isolate without loading the corpus as Dart objects. If the latency/memory gate fails, test native sqlite-vec behind the same interface. If both fail, block and explicitly revise the design before retrieval integration; do not reduce corpus coverage silently.

Hybrid retrieval uses reciprocal-rank fusion of FTS and vector results, source-linked passages and stale-embedding exclusion. It does not generate answers.

## Acceptance gates (targets, not current measurements)

| Area | Required result |
|---|---|
| Existing data | Every input accounted for; zero unexplained omissions or overwritten originals |
| Startup | Existing full-scale workspace editable within 2 s p95; no network dependency |
| Open/save | Each ≤150 ms p95 for notes up to 50 KB, including background work; save is durable commit |
| Keyword search | First 50 results ≤200 ms p95 at full scale |
| Semantic search | Query embedding + top 20 ≤3 s p95 warm, first query ≤6 s |
| Retrieval quality | Relevant passage in top 10 for ≥85% of 90 judged queries; ≥80% per language and cross-language subset |
| Graph | Bounded 200-node/500-edge view interactive ≤500 ms p95 |
| UI | <1% frames exceed device refresh budget over scripted five-minute workload |
| Android PSS | ≤350 MB normal editing; ≤750 MB embedding/search |
| Incremental jobs | Edit reparses one note and affected records; no unrelated embeddings regenerated |
| Idle | Ten unchanged minutes: zero rebuilds, content uploads or repeated processing notifications |
| Cancellation | UI acknowledgment ≤250 ms; no subsequent background batch starts |
| Sync correctness | Duplicate/reordered/interrupted/retried batches converge; conflicting content recoverable |
| Sync efficiency | Small edit transfers revision/protocol metadata only; no whole-workspace download |
| Controlled sync | Text edit visible on second device ≤10 s p95 on specified test network |
| Export/re-import | IDs, content, links, annotations, bibliography and attachment hashes preserved |
| Initial processing | Separate import/extraction/embedding measurements; interruption resumes completed batches |

Use normal release builds for acceptance and profile builds for frame timings. Capture real corpus plus deterministic scale fixtures with representative lengths and skewed connectivity. Thirty startup runs and at least 100 frequent-operation samples; record hardware, build, manifest, p50/p95/max, memory and logs. Real Nextcloud evidence is separate from controlled-network tests. Synthetic generated chunks are not evidence of extraction/embedding throughput.

## Execution policy

Haiku CLI / Codex Luna implement bounded tickets and tests; Sonnet is escalation for difficult migration/sync only. At most two implementers plus one reviewer, disjoint ownership. Coordinator integrates and approves evidence. Record requested and observed model, usage when exposed, exact commands, changed files and limitations. Do not label unavailable usage as zero. Pass ticket + needed files/contracts, not conversation history.

State: TODO → READY → RUNNING → REVIEW → DONE; BLOCKED records a concrete dependency. A ticket needs reviewed diff, reproducible checks and evidence. Split work beyond one focused session before assignment. Implementation progress and production acceptance remain separate. Seven days of successful daily use and every required gate precede thesis freeze.

Private corpus/configuration/backups stay outside git. Only redacted aggregate recovery evidence goes into this repository. The user authorized committing/pushing current work and starting this plan.

## Technical references

- Drift native background database: https://drift.simonbinder.eu/platforms/vm/
- SQLite WAL constraints/fixes: https://www.sqlite.org/wal.html
- SQLite FTS5: https://www.sqlite.org/fts5.html
- Drift migration tests: https://drift.simonbinder.eu/migrations/tests/
- PDF reader: https://github.com/espresso3389/pdfrx
- Annotation anchors: https://www.w3.org/TR/annotation-model/
- ONNX mobile benchmarking: https://onnxruntime.ai/docs/tutorials/mobile/
- sqlite-vec exact KNN: https://alexgarcia.xyz/sqlite-vec/features/knn.html
