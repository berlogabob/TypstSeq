# P20 progress — deterministic chunking

Status: HOST ACCEPTED / DEVICE BLOCKED

Added deterministic text chunking keyed by source-version ID. Each chunk carries source character offsets, configurable overlap, and a SHA-256 content hash; unchanged source versions therefore produce stable chunk IDs and changed ranges can be re-embedded independently. SQLite schema v8 persists chunks with pending/complete/failed state, model identity, and optional Float32-compatible BLOB embeddings.

Evidence:

- `flutter test test/retrieval_chunking_test.dart` — 2 passed.
- `flutter analyze lib/retrieval/chunking.dart test/retrieval_chunking_test.dart` — clean.
- `flutter test test/database/chunk_persistence_test.dart` — pending-to-complete embedding state and BLOB persistence pass.
- `flutter test test/database/tylog_graph_schema_test.dart test/database/portable_snapshot_test.dart` — v2→v8 migration and snapshot format v8 pass.
- `flutter test test/retrieval_embedding_jobs_test.dart test/database/chunk_persistence_test.dart` — bounded batches persist completed vectors, leave failed work pending, and resume after a fresh runner invocation.
- `flutter analyze lib/retrieval/embedding_jobs.dart test/retrieval_embedding_jobs_test.dart` — clean.

The new `runEmbeddingBatch` seam uses the existing chunk state as its durable queue: it processes at most 1,000 rows, writes each vector before advancing, and leaves failures pending for retry. Remaining work: move the native callback behind an isolate and run Android quality/latency gates.

## Cooperative scheduling (2026-09-21)

The bounded runner yields once between chunks, so an embedder that completes
inline cannot monopolize the event queue. A regression test schedules a timer
alongside an eight-chunk inline batch and verifies the timer runs before the
batch completes. Native callback isolation and Android quality/latency/memory
acceptance remain device-gated.

The pinned ORT bridge is now adapted by `nativePassageEmbedder`, which validates the native 384-dimensional finite result and stores its Float32 bytes through the same batch runner. The package exports this API publicly; host validation covers asset-path checks. Android model smoke and sustained profile measurements remain device-gated.

## Host regression rerun (2026-09-21)

The combined chunking, resumable embedding-job, native-adapter validation,
chunk persistence, schema migration, and portable snapshot suite passed 26
tests. This confirms the durable host queue and both passage/query validation
paths; native callback isolation and Android quality/latency/memory remain open.

## Host acceptance rerun (2026-09-22)

The focused chunking, persistence, embedding-job, adapter, cosine, hybrid, and
vector suites passed **19 tests**; targeted analysis is clean. Host scheduling
and durable state are accepted. Private model execution and Android
quality/latency/memory remain device-gated.

## macOS native embedding and vector parity (2026-09-27)

`embed()` was compiled for arm64 Android only, so the Mac had no on-device
model. `ort` is now enabled for Apple-silicon macOS too (Cargo target cfg +
`src/api/embedding.rs`); the universal library's x86_64 slice and x86 Android
keep the `embedding_unsupported_platform` stub, since ort ships no prebuilts
there. The macOS pod previously used `-force_load`, which pulled the
statically linked ONNX Runtime's duplicate protobuf objects (756 duplicate
symbols); it now links the archive normally, keeps the 22 FFI/Quick Look entry
points with `-Wl,-u` (computed by `nm` at `pod install`), and links `-lc++`.

The pinned model files (revision `ccc66d3`) were re-downloaded outside Git and
all six SHA-256 values matched `evidence/P05/contract.md`. The frozen golden
query vector was regenerated with the pinned ORT 1.30.0 reference runner.

```text
macOS profile (M4 Pro): P05_VECTOR_PARITY cosine=1.000000 max_abs=0.000058
A24 profile (2026-09-26): cosine=1.000000 max_abs_difference=0.000092
acceptance: cosine >= 0.999; max_abs_difference <= 0.02 — PASS on both
```

Typst compilation through the bridge still passes on macOS
(`markdown_import_native_test`), and the release app links and exports all 22
entry points. Remaining P20: query-embedding + top-20 latency and PSS measured
in the app path at 250k chunks on both platforms (exact search alone already
passes: A24 warm p95 811 ms / PSS 551 MB; Mac warm p95 18 ms), which needs the
P21 in-app wiring.

## Cached session, lean tokenizer and A24 memory (2026-09-27)

`embed()` used to parse the tokenizer and build an ONNX session on every call.
It now caches both behind one lock (one embedding at a time, as the plan
requires). A24 profile PSS with the model loaded was still ~900 MiB. Ruled out
by measurement: arena/memory-pattern off, graph optimizations off, weight
prepacking off, fp32 `model.onnx`, zero-copy `.ort` (O4 and fp32), and int8
`model_qint8_avx512_vnni.onnx` (parity 0.997298 on ARM, below 0.999). The
cause was `tokenizers`' Unigram trie: 384 MiB steady for the 250k XLM-R vocab.
`src/lean_tokenizer.rs` runs the same Viterbi over a flat map inside
`tokenizers`' own normalizer, Metaspace, added-token and template pipeline;
token IDs and masks are identical to `tokenizers::Tokenizer` on 12,632
encodings (all 6,305 notes of the verified backup plus 71 edge cases, 60 of
them generated with local ornith-1.5:9b), with 512-token truncation.

| Platform | Parity cosine / max abs | First query | Warm query p50 / p95 | Peak PSS |
|---|---|---:|---:|---:|
| A24 profile | 1.000000 / 0.000092 | 708 ms | 9.8 / 11.1 ms | **456 MiB** |
| macOS profile (M4 Pro) | 1.000000 / 0.000058 | 272 ms | 2.3 / 2.4 ms | — |

With exact search over 250,000 vectors (A24 warm p95 811 ms, cold 825 ms), a
semantic query plus top 20 is about 0.83 s warm and 1.5 s first on the A24,
inside the 3 s / 6 s gates. Still open for P20: one run measuring PSS with the
model loaded and a 250k-vector search in the same process (each alone is 456
and 551 MB), and resume/cancel of the in-app indexer on device.

## Combined 250k search + model memory gate (2026-09-27) — PASS

`integration_test/p05_exact_search_profile_test.dart` now runs the app's
search shape on the A24 profile build (`P05_HANDSHAKE=true
P05_COMPACT=true`): the pinned model is pushed and loaded, every run embeds a
real query, an int8 in-memory scan copy of 250,000 synthetic 384-d vectors
ranks 200 candidates, and those are reranked with exact Float32 vectors.

| Shape | First query | Warm p50 / p95 | Peak TOTAL PSS |
|---|---:|---:|---:|
| Float32 in memory + model (before) | 1,927 ms | 1,216 / 1,238 ms | ~965 MiB (spike 1,355) |
| fp16 scan copy + model | 927 ms | 224 / 228 ms | ~818 MB |
| **int8 scan copy + model** | **952 ms** | **224 / 230 ms** | **718,752 KiB (736 MB)** |

Gates: first ≤6 s, warm p95 ≤3 s, PSS ≤750 MB — pass, with a thin (~2%)
memory margin; the breakdown at the fp16 point was native heap 418 MB (ONNX
model), Dart heap ~240 MB, graphics 71 MB (test harness). Host proof that the
compact copy does not change results: over 20 random queries on 5,000
vectors, the int8 top 200 reranked in Float32 equals the exact top 20
(`test/vector_index_test.dart`). The app's `SemanticSearchController` uses
the same path, loading the copy from SQLite in 2,000-row keyset pages of
(id, vector) only and rebuilding at most once a minute while indexing.
Decision (user, 2026-09-27): compact copy + exact rerank instead of
sqlite-vec; chunking stays 800/120 (~97k chunks for the real vault).

## Passage parity on both platforms (2026-09-27) — P20 DONE

The P05 profile test now also embeds a fixed passage ("passage: " prefix) and
compares it with a golden vector from the pinned ORT 1.30.0 reference runner.

| Platform | Query cosine / max abs | Passage cosine / max abs |
|---|---|---|
| macOS profile | 1.000000 / 0.000058 | 1.000000 / 0.000076 |
| A24 profile | 1.000000 / 0.000092 | 1.000000 / 0.000077 |

All P20 close criteria now hold: passage and query parity (≥0.999, ≤0.02) on
both platforms; deterministic resume (A24 durable resume accepted in P05 plus
the host indexer tests for single flight, cancellation and a permanently
failing chunk); semantic query + top 20 on the A24 at 952 ms first and 230 ms
warm p95 (≤6 s / ≤3 s); and peak PSS 718,752 KiB (736 MB ≤750 MB) with the
model resident and 250k vectors searched.
