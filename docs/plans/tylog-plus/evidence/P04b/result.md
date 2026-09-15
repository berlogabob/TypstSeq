# P04b — corpus manifests and current scan baseline

Date: 2026-09-15. Status: PASS.

The coordinator accepted a stdlib-only aggregate manifest tool after removing an optional command wrapper that had unbounded log output. The manifest never writes paths, file names, per-file hashes, or content. Output is created with mode 0600. Thirteen focused tests cover determinism, content changes, privacy, symlinks, control characters, permissions, aggregate counts, invalid roots, and output placement.

## Reproduction

```bash
python3 test/tool/test_tylog_corpus_manifest.py
python3 tool/tylog_corpus_manifest.py --root CORPUS --output PRIVATE_OUTPUT.json
/usr/bin/time -lp dart run packages/tylog_core/tool/scan_repro.dart CORPUS
```

## Observed results

- Verified production backup: 11,826 files, 1,539,299,837 bytes; manifest elapsed 2.68 s; peak RSS 23,969,792 bytes.
- Current scanner, five production-backup runs: 5.008480, 5.044503, 5.054671, 5.079086, and 5.651914 s; p50 5.054671 s; max RSS 330,661,888 bytes. Counts were stable at 6,298 notes, 3,726 tasks, and 9,088 problems.
- Deterministic 10k fixture: 10,000 nodes, 100,000 edges, 25,000 chunks, 104,458,879 bytes. Generation took 5.98 s at 24,264,704 bytes peak RSS; aggregate manifest took 0.11 s at 22,331,392 bytes peak RSS.
- Deterministic full fixture: 100,000 nodes, 1,000,000 edges, 250,000 chunks and 1,031,679,714 bytes, with SHA256 file manifest; see P04a evidence.

Production manifests and raw timings stay outside Git. The scanner baseline measures the existing file model and establishes the performance gap; it is not a SQLite performance result.

## Agent usage

Claude Haiku `claude-haiku-4-5-20251001` drafted the bounded tool and tests: $0.1743874 reported cost, 1,663 input tokens, 14,124 output tokens, 500,464 cache-read tokens, 26,029 cache-creation tokens, and 2,083 thinking tokens. Codex `gpt-5.6-luna` performed the independent review; provider usage was unavailable. The coordinator removed the unsafe optional runner and reran all checks.
