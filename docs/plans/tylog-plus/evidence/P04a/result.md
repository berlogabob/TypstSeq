# P04a — deterministic scale fixture generator

Date: 2026-09-14. Status: PASS (synthetic generator only).

Requested worker: Codex `gpt-5.6-luna`. Provider-observed usage is unavailable; no zero-cost claim. Coordinator reviewed the implementation and required heterogeneous length tiers, independent language/type coverage, seed-sensitive text, and chunk offsets into parent content.

## Reproduction

```bash
python3 -m unittest discover -s test/tool -p 'test_tylog_scale_fixture.py' -v
/usr/bin/time -l python3 tool/tylog_scale_fixture.py --output-dir /tmp/tylog-full-fixture-new
```

The output directory must be absent or empty. The generator emits synthetic nodes, edges, chunks and a manifest identifying seed/counts/distributions and file SHA256 hashes. It never reads user data. Full outputs remain outside git.

## Observed coordinator run

- Four unit tests passed: deterministic bytes/hashes/counts, valid references, seed-sensitive content, parent-language/source-offset consistency, empty corpus, invalid counts and nonempty destination.
- 100,000 nodes; 1,000,000 edges; 250,000 chunks.
- JSONL payload: 1,031,679,714 bytes.
- Elapsed 62.05 seconds; user CPU 60.12 seconds; system CPU 1.35 seconds.
- Maximum resident set size: 27,426,816 bytes (`/usr/bin/time -l`, macOS).
- Nodes by language: English 33,334; Portuguese 33,333; Russian 33,333.
- Length tiers: short 69,900; medium 25,011; long 5,089.

## Limits

This is a bounded-memory fixture generation measurement, not application/database latency, real-source extraction, real language retrieval quality, or embedding throughput. Synthetic word sequences are not a judged semantic benchmark. Device corpus inventory and benchmark runner remain outstanding, so P04 stays incomplete.
