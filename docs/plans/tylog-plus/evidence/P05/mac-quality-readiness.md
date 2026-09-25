# P05 Mac quality readiness — 2026-09-25

Status: SYNTHETIC MAC SMOKE PASSES; JUDGED-QUERY QUALITY BLOCKED ON PACK.

The repository contains the numerical reference runner and private-pack
validator. The immutable P05.0 model/tokenizer files were downloaded to a
private cache outside the repository; all six SHA-256 digests match the
contract. The isolated Python environment uses the pinned dependencies:
Python 3.12.11, NumPy 2.4.4, tokenizers 0.22.2, Transformers 4.57.1, and ONNX
Runtime 1.30.0. CPUExecutionProvider is available.

Two offline runs through `tool/embedding_reference.py` over four synthetic
EN/PT/RU query/passage records produced identical artifact hashes
(`525787b6b634bd661e5e3a1810841a962e3576d8c3d01670bdbaf5679bbfe872`). Each
artifact has shape 4 x 384, finite values, and unit-normalized vectors (maximum
norm error 5.96e-8). Inference after model load took 9.436 ms and 8.883 ms.
This confirms local model compatibility only; it is not semantic quality or a
scale benchmark.

The verified phone backup is available locally, but no valid 90-query judgment
pack was found in the repository, the checked evaluation files, or the backup
metadata. The small evaluation reports found are not judged passage labels, so
Recall@10 remains unmeasured. The remaining Mac quality input is a private JSONL
pack accepted by `tool/validate_embedding_benchmark.py` (90 unique queries; 30
each EN/PT/RU; at least 10 cross-language queries per language). A scorer is
now available in [quality-runner.md](quality-runner.md). Once the pack is
available, record only aggregate Recall@10 overall, by language, and
cross-language subgroup, the pack digest, and runtime metadata. Do not copy
query text, note text, IDs, or private paths into repository evidence.

P05 Mac exact-cosine timing evidence remains in `mac-exact-search.md`; it
measures the search primitive over synthetic vectors and is not semantic
retrieval-quality evidence. Android quality and performance acceptance remain
device gates.
