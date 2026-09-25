# P05.6a — judged retrieval quality scorer

Status: HOST TOOL READY; PRIVATE JUDGMENTS AND ANDROID GATES OPEN.

`tool/benchmark_embedding_quality.py` scores a validated private 90-query pack
against the `.npz` output of `tool/embedding_reference.py`. It uses exact
cosine ranking with deterministic ID tie-breaking, counts a query as a hit
when any judged relevant passage is in the top 10, and reports overall,
per-language, and cross-language Recall@10. Its exit status enforces the P05
thresholds: 85% overall and 80% for each language and the cross-language group.

The scorer validates that query and judged-passage vectors exist and rejects
invalid dimensions, duplicate IDs, non-finite/zero vectors, and too few
candidates. Output contains only aggregate counts, pass/fail, and SHA-256
digests; it does not emit private queries, passage IDs, or input paths.

Verification: `python3 test/tool/test_benchmark_embedding_quality.py` and
`python3 test/tool/test_validate_embedding_benchmark.py` pass. The test exercises
90 balanced queries, all three per-language groups, the cross-language group,
missing judged vectors, and the complete file-based scoring path. It uses
synthetic vectors only and does not claim retrieval quality on the private
corpus.

Run after producing an accepted private pack and embedding artifact:

```bash
python3 tool/benchmark_embedding_quality.py "$PRIVATE_PACK" "$EMBEDDING_NPZ"
```

The private judged pack remains unavailable. No semantic Recall@10 result is
claimed; Android profile parity, latency, and memory gates also remain open.
