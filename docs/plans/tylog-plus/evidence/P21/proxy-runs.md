# P21/P23 native runs (2026-09-29)

Generated 49-note fixture vault (copy only), pinned model pushed or copied offline.
Mac = macOS debug build. P30 = Huawei P30 profile `.profiletest` build via
`scripts/p21_android.sh`. The P30 is a proxy and does not close the A24 gate.

| Run | Index | First query | Warm p50 | Warm p95 |
|---|---:|---:|---:|---:|
| P21 Mac | 1,070 ms | 19 ms | 4.9 ms | 5.9 ms |
| P21 P30 | 5,696 ms | 45 ms | 39 ms | 54 ms |

The P21 run covers model install, incremental index, three cited searches in the real Search
screen, note-citation navigation, and stale-row removal. Found and fixed: note citations
had `onTap: null` (272afb0).

The P23 run covers all six steps (filter, cited passage, PDF annotation save/reassign/reopen,
deterministic filtered report with bibliography, stale row, source/PDF bytes unchanged), and
passes on Mac and P30. Report sha256 `c329961e…564ac`. Found and fixed: opening a
deleted note threw FileSystemException (aa76d0f).

Remaining: P21/P23 on the real vault (Mac profile build, then A24), and P05 quality
through this path.

## Real-vault indexing throughput (2026-09-30)

The real Mac vault copy splits into 101,523 chunks. The P21 test measured 3.5 chunks/s
(a projected 8 h), but that run had two controllers indexing the same database: the app's
own (`lib/app_mobile.dart` ~465) and the test's direct one. Both serialize on the Rust
global model lock. The ORT-only bench (`tool/p05_ort_bench`, 200 passages, pinned O4
model) gives 27 ms/chunk (37/s, ~46 min for the vault). Level3, perf-core intra threads,
and batch 16 each change it by ≤3%, so none was kept. The pinned O4 file holds fp16
weights; fp32 variants measure ~39/s, and the pinned model is unchanged. Dart-side
costs are small: `pendingChunks` 0.4–1.6 ms per batch, chunk write 0.2–7 ms. A
status index (schema 9) gave no measurable gain and was not kept.

Open: measure a single-controller in-app run (the test must drive the app's
controller only) on Mac and phone. Expect about 46 min on the Mac; phones are slower.

### Single-controller rerun (2026-09-30)

With only one controller indexing, the real vault runs at 5.97 chunks/s (3,582 chunks
in 10 min), projecting ~4 h 43 min for 101,523 chunks on the Mac. That is still ~6x
slower than the ORT-only bench (27 ms/chunk). Unexplained. Suspects: real chunks
running longer in tokens than the bench passages, and the app's ORT build differing
from the bench's `download-binaries`. Open perf item: a first full index is hours on
Mac and longer on phones. Search itself stays fast (fixture p50/p95 3.9/4.5 ms).

### Indexing gap investigation (2026-10-03)

The recorded September 30 results remain 5.97 chunks/s in-app and 27 ms/chunk
(37.04 chunks/s) in the bench: a 6.20x ratio. There is **no new model-throughput
measurement or before/after app result**: the repo contains no pinned O4 model
or tokenizer, and no models were downloaded or real vaults opened.

The extended bench's checks passed using existing Rust dependency artifacts
(Rust 1.92.0): generated budgets 8/128/256/512, percentile and padding checks,
8 synthetic lean/stock parity encodings, and the existing parity test's 22
encodings using the same toy vocabulary. A two-input CLI self-check reported
raw token min/max 11/605, encoded min/max 11/512 and 1 truncated input, with
2 matching encodings. These are **synthetic vocabulary checks**, not pinned
model/vector parity or a real-vault token distribution.

Offline Cargo tests could not build: bench archive `ahash 0.8.12` and app
archive `addr2line 0.25.1` were unavailable. `flutter test --no-pub` for the
chunking, embedding-job and native-embedding suites did not reach test execution:
the SDK initially required external writes; running its existing snapshot with
repo-local config and analytics suppressed then failed at the PDFium native hook's
network download. No Dart or production Rust embedding code changed.

Source comparison and reproducible bench commands:
[`tool/p05_ort_bench/README.md`](../../../../../tool/p05_ort_bench/README.md).

#### Host pipeline follow-up (2026-10-03)

Measured on the Mac 2026-10-03: production Rust `tool/p05_ort_bench --app`
14.2/29.2 ms per chunk at 256/512 tokens; raw dynamic ORT 7.9/14.1/28.5 ms
at 128/256/512 tokens. The historical single-controller app rate remains
5.97 chunks/s (~167.5 ms/chunk). These supersede the earlier lack of access to
model-throughput evidence; they are not a new app before/after measurement.

Added `test/retrieval_indexing_benchmark_test.dart`: a disposable FILE-backed
TyLogDatabase, 100,000 chunks of 1,608-byte synthetic English prose, alternating
50% complete rows with 1,536-byte embedding blobs and 50% pending rows. The real
SemanticIndexer processes 320 pending chunks (20 batches of 16), then cancels.
The fake embedder awaits 29 ms and returns 1,536 bytes. Database setup is excluded;
no vault is read. The executor uses NativeDatabase(file), default SQLite settings,
without adding a status index or changing journal/synchronous modes.

| Host fake-embedder run | chunks/s | ms/chunk | pendingChunks total ms | embed total ms | completeChunk total ms | pending COUNT SQL total ms | other total ms |
|---|---:|---:|---:|---:|---:|---:|---:|
| Before | 26.42 | 37.85 | 15.045 | 9,928.611 | 462.342 | 1,657.865 | 48.230 |
| After, isolated rerun | 29.73 | 33.63 | 34.519 | 9,897.503 | 583.769 | 194.029 | 52.459 |
| After, final host suite | 29.24 | 34.20 | 26.052 | 10,143.444 | 514.244 | 215.362 | 45.487 |

Stopwatches wrap the complete pendingChunks/completeChunk calls and embed delay;
COUNT timing wraps its SQL executor call (Drift construction/decoding is in
"other"). The requested 29 ms timer takes ~31–32 ms in this host run. Before,
COUNT consumed 5.18 ms/chunk; completeChunk consumed 1.44 ms/chunk. Thus this
fixture does **not** reproduce ~130+ ms/chunk above Rust. It confirms a smaller
avoidable repeated-count cost, not the cause of the entire historical app gap.

Minimal fix in `lib/retrieval/semantic_indexer.dart`: decrement pending by this
worker's successful completions each batch, reconcile with SQL every 16 batches,
and recount exactly on exit, including cancellation/failure. Counts drop from
22 to 3 in this run. Done/running progress still updates each batch; concurrent
additions/deletions can lag in pending progress until reconciliation. Failed
chunks remain pending; cancellation stays at batch boundaries. No batch write
transaction was added because write time did not explain the reported gap.
The benchmark asserts the three-count cadence and exact final progress;
`test/semantic_indexer_test.dart` adds concurrent insertion during cancellation.

The existing P05 embedding test is a device integration test using RustLib.init;
`test/retrieval_native_embedding_test.dart` only validates arguments. The host
benchmark explicitly loads the existing arm64 release dylib at
`packages/typst_flutter/.native-build-1.92.0-rustup/aarch64-apple-darwin/release/libtypst_flutter.dylib`.
It reads only the user-authorized model_O4.onnx/tokenizer.json under the app's
models directory. Production nativePassageEmbedder, 50 warm synthetic chunks:
first run cold 323.800 ms, warm mean 15.802 ms/chunk (63.28/s); final host suite
cold 293.457 ms, warm mean 16.563 ms/chunk (60.37/s). This includes FRB and Dart
byte conversion. Token length was not measured for this synthetic text; this
is not a matched-token bridge-only subtraction or real-vault throughput result.
Reproduce the optional native test by setting `TYLOG_BENCH_DYLIB` to that dylib
and `TYLOG_BENCH_MODEL_DIR` to the directory containing both model assets.

Source trace: nativePassageEmbedder -> nativeEmbedder -> generated Dart
crateApiEmbeddingEmbed (executeNormal/NormalTask, SSE codec) -> generated Rust
wire__crate__api__embedding__embed_impl (wrap_normal) -> api::embedding::embed.
FRB dispatches normal inference work to its Rust worker thread pool; this is
not executeSync on the Dart root isolate. Dart serialization/decoding and vector
validation/byte conversion run on the calling isolate. Rust caches one session
and tokenizer by path; it loads on first call or path change, not every chunk.
A global mutex is held through tokenization, inference and pooling. Per-call
copies include serialized path/kind/text arguments, token IDs/masks converted to
i64 and copied into ORT tensors, hidden output data.to_vec for pooling, and the
384-float result encoded/decoded across FRB. Dart views the Float32 buffer as
bytes then copies via toList; completeChunk copies again into Uint8List. Their
individual copy costs were not measured. No native reload/thread/copy fix was
supported by the host timings.

Validation: requested `flutter test --no-pub test/retrieval* test/database
 test/semantic_indexer_test.dart` was attempted via the existing Flutter tools
snapshot (SDK wrapper writes are sandbox-blocked). The normal test launcher
failed before executing tests because localhost server sockets are denied.
As a fallback, compiled these suites with Flutter's frontend server and ran
socket-free under the existing arm64 flutter_tester with VM service disabled,
using test_api Declarer/Suite/LiveTest: **99 passed, 0 failed**, including the
fake/native benchmarks and cancellation/retry/concurrent-addition checks.
One existing opt-in bounded-neighborhood benchmark was skipped; the widget
lifecycle suite was excluded from this fallback because it could not complete
without the normal test harness. This is not a claim that normal flutter test
passed. `flutter analyze --no-pub` via the SDK snapshot: no issues found.
`graphify update .` completed (AST only). No vaults touched and no commit made.
The unexplained real-app gap remains open; no new in-app run was authorized or
performed, so there is no measured app before/after result.

#### Where the gap is not (2026-10-03)

Each layer measured alone is fast: production Rust embedding 29 ms/chunk at 512 tokens,
the Dart loop + 100k-row file DB with a 29 ms fake embedder 34 ms/chunk, and the native
embedder through FRB on the host 16 ms/chunk. None reproduces the in-app ~167 ms/chunk. The
remaining cost sits in the running app: progress listener rebuilds, concurrent vault/index
work on the same isolate or Rust lock, or the test's UI. Next step: a DevTools timeline of the
real app indexing the vault copy. Not a named gate; it affects P26 first-index time.

#### Indexing dips: main-isolate json_extract scan (2026-10-03)

Schema v9 adds `idx_nodes_path` on `json_extract(attributes_json, '$.path')`
for fresh databases and upgrades. The stamp query explicitly traverses the
index; the 500-path content batches and note-persistence equality query use
that same expression. EXPLAIN QUERY PLAN tests verify index use. Portable
schema v8 backups remain importable; logical records are unchanged.

Triggers: workspace notifications schedule a 300 ms debounced refresh through
`_ensureSemanticController(refresh: true)`; cloud polling every 25 seconds
can generate these notifications. App resume and model download completion
also refresh. Semantic progress only updates state; there is no semantic
periodic timer. Existing `_refreshInFlight` spans sync AND `runUntilIdle`,
preventing repeat syncs during indexing. A held-embedder test verifies 20
refresh calls share that future and only one embedder is created. No new
trigger guard was needed.

Production opens SQLite via `NativeDatabase.createInBackground` (P06).
The P21 native integration test injects main-isolate `NativeDatabase.memory()`.
No database execution restructuring was done.

Host benchmark: 6,500 synthetic nodes (~1 KB content / 1.4 KB attributes each),
one stamp query plus thirteen 500-path content batches, main-isolate in-memory
SQLite, warm median of five runs after warm-up: **59.156 ms before → 10.142 ms
after (5.83x)**. The test prints timings and checks results and query plans.
This measures lookup cost, not embedding/chunk sync or real-app dip frequency;
no real-vault before/after profile was captured.

Validation: requested `flutter test --no-pub` for `test/database`, semantic
controller/indexer, and embedding-jobs suites was attempted via the SDK snapshot
wrapper; sandbox localhost socket denial blocks the normal launcher. Socket-free
frontend-server/flutter_tester fallback: **86 passed, 0 failed, 1 opt-in benchmark
skipped**, including v1/v2/v3/v4/v8 migrations and v8 backup compatibility.
The widget database lifecycle suite was excluded from the fallback.
`flutter analyze --no-pub`: only the concurrent job's `avoid_print` info at
`test/real_account/p24_rehearsal_real_test.dart:148`; scoped analysis of all
11 changed Dart files passes. `git diff --check` and AST-only `graphify update .`
pass. `test/real_account/` was not edited; no commit made.
