# Mention extraction model competition (2026-11-25)

Which Studio model extracts mentions for the enrich worker.
Run: `BENCH=tool/championship/extract_bench/bench.py tool/championship/lang_bench/run.sh <model> ...`; table:
`python3 tool/championship/extract_bench/bench.py --report`. Inputs and raw rows hold journal text, so they stay outside the
repo in `~/Documents/tylog-gold/extract-bench/`.

100 notes with 106 gold labels (`gold-all-draft.jsonl`), the worker's own prompt and reply check, every model at
65536 context, thinking off, one model at a time with the Mac jobs stopped.

| model | found | type | linked | false link | mentions/note | dropped/note | failed | s/note | load s |
|---|---|---|---|---|---|---|---|---|---|
| ollama/ornith-1.5:35b | 0.80 | 0.79 | 0.21 | 0.06 | 8.92 | 0.79 | 0 | 7.29 | 10.5 |
| ollama/qwen3.6:27b | 0.68 | 0.79 | 0.22 | 0.00 | 6.82 | 0.45 | 0 | 35.64 | 21.8 |
| unsloth/Qwen3.8-27B-GGUF | 0.70 | 0.70 | 0.25 | 0.03 | 7.62 | 0.36 | 0 | 84.34 | 17.3 |
| unsloth/gemma-4-26B-A4B-it-qat-GGUF | 0.51 | 0.83 | 0.25 | 0.38 | 4.30 | 0.26 | 0 | 1.76 | 19.7 |
| unsloth/Muse-Glimmer-30B-GGUF | 0.57 | 0.77 | 0.23 | 0.00 | 5.75 | 0.12 | 0 | 136.31 | 13.3 |
| unsloth/Inkling-2-Mini-GGUF | 0.80 | 0.79 | 0.17 | 0.00 | 9.09 | 0.38 | 1 | 22.53 | 18.9 |
| prism-ml/Ternary-Bonsai-2-27B-gguf | 0.73 | 0.71 | 0.23 | 0.00 | 8.27 | 0.66 | 0 | 8.60 | 9.6 |

Columns: `found` = share of gold surfaces among the model's mentions; `type` = share of found ones with the gold
type; `linked` = gold has an entity, share linked to it; `false link` = gold has none, share linked to something;
`dropped` = mentions removed by the reply check (text not in the line).

## Decision

Ornith stays on the `enrich` task. It finds the most (0.80, tied with Inkling-2-Mini) and is three times faster
than Inkling. Inkling makes no false links and invents half as many mentions, but had one failed note and links
fewer of the known entities; not enough to switch.

gemma-4, the fast runner-up for Portuguese, is the worst here: it finds half of the gold mentions and links
38% of the ones that should stay unlinked. Muse-Glimmer (the `phrases` model) is careful but misses 43% and
takes over two minutes per note because it always reasons.

## Limits

- The gold labels are an unreviewed draft, one or two surfaces per note. Differences of a few points are noise.
- `linked` is about 0.2 for every model, so it measures the prompt or the labels, not the model.
- Outputs were not read side by side; the table is the only evidence.
- Left out: flint and LFM2.5 (failures in the language run), Qwen3.6-35B (does not load).
