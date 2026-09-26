# P05 Mac quality readiness — 2026-09-26

Status: SYNTHETIC MAC SMOKE PASSES; PRIVATE DRAFT PACK READY FOR HUMAN REVIEW.

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

The verified backup had no pre-existing judged pack. A private draft was
prepared from real source excerpts using the local `ornith-1.5:9b` model. Its
90 unique queries are balanced 30 each EN/PT/RU, with 20 same-language and 10
cross-language positives in each query group. Excerpt language was checked
independently from the containing Typst file; the candidate pool has 2,735
excerpts in the target languages (2,598 EN, 44 PT, 93 RU). The private draft
passes `tool/validate_embedding_benchmark.py`, including the required 10
cross-language examples per query language.

This validates only pack structure. The suggested questions and positive labels
are machine-generated and remain unjudged. Automatic language detection flags
one mixed-language Russian query for manual review. The private TSV worklist
and instructions are in the backup's measurements folder; those files, paths,
and their contents stay outside Git. No Recall@10 result is claimed until the
human review is complete. Then run the scorer in [quality-runner.md](quality-runner.md)
and record only aggregate Recall@10 overall, by language, and cross-language
subgroup, the reviewed pack digest, and runtime metadata.

P05 Mac exact-cosine timing evidence remains in `mac-exact-search.md`; it
measures the search primitive over synthetic vectors and is not semantic
retrieval-quality evidence. Android profile vector parity, exact-search/PSS,
and durable-resume gates are now closed; semantic Recall@10 remains open.
