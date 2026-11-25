# Local model bench

Measures whether a local coding model can be trusted with TyLog work, on five
tasks cut from this repo's own history. Base commit is fixed (`BASE` in
`run.sh`), so results stay comparable across models and dates.

    tool/championship/model_bench/run.sh <provider> <model> [reps=3] [task ...]
    tool/championship/model_bench/report.py            # table from results.jsonl

Each run: reset a dedicated worktree to BASE, apply the task's `setup.sh`,
commit that as the baseline, let the model work through `pi-run.sh` with the
task's visible verify command (up to 3 attempts), then score with `check.sh`,
which the model never sees.

| Task | What it asks | Hidden check |
|---|---|---|
| t1_new_file | new 30-line pure function from a spec | unit test on the spec table |
| t2_same_value_edit | swap literals for same-value tokens in a 144-line widget | every number keeps its value |
| t3_large_file_edit | add one branch to a function in a 2,500-line file | unit test, file not rewritten |
| t4_bug_fix | make three failing cache tests pass in `scanner.dart` | whole core suite still passes |
| t5_write_test | write a guard test for the macOS sandbox rule | passes now, fails when the rule is broken |

Columns in the report:
- **pass**: hidden check passed.
- **silent**: the model's own verify passed but the hidden check failed. This
  is the number that decides trust: it is work that looks finished and is wrong.
- **stray**: files changed outside the task's allowlist.
- **+/-**: lines added / deleted in allowed files (a rewrite shows as a large -).
- **min**: wall-clock minutes per run.

## Context window matters (2026-10-10)

Unsloth Studio loads a new model at 8,192 tokens unless told otherwise. At
that size the model returns empty replies as soon as it reads a source file,
and every run looks like "no change". `run.sh` therefore loads the model
itself (`studio_load.py`) before a Studio run:

    BENCH_CTX=65536 BENCH_LABEL=@64k tool/championship/model_bench/run.sh studio <model> 3 t4_bug_fix

`BENCH_CTX` defaults to 32768. `BENCH_LABEL` is appended to the model name in
`results.jsonl` so rounds at different sizes stay separate. pi assumes 65,536
for every Studio model (`~/.pi/agent/models.json`), so 65536 is the matching
server value; going higher needs both raised.

Bug-fix task (`t4_bug_fix`), 3 runs each:

| Model | 32k | 64k |
|---|---|---|
| `ollama/ornith-1.5:35b` (Q4_K_M, 22.6 GB) | 0/3 | 2/3 |
| `pfeifferj/Ornith-1.5-35B-A3B-GSQ-RCO-GGUF` 3.5-bit (15.2 GB) | 0/3 | 1/3 |

The other four tasks were 3/3 for both builds at 32k. Every 64k failure was
silent (visible test passed, core suite failed), so bug-fix diffs still need a
human read. Three runs per cell is a small sample: 2/3 against 1/3 does not
separate the two builds.

Side files: `results-invalid-8k-context.jsonl` (the first, 8k, run of the
3.5-bit build) and `results-ollama-path.jsonl` (rows taken through Ollama
instead of Studio); neither is counted in `report.txt`.

## New Studio models (2026-11-25)

`run_new_models.sh`: all five tasks, 3 runs, 64k context, Mac jobs stopped. Time rule (`skip_slow.sh`): a model
slower on the first task than the two reference models (Ornith 35b, qwen3.6: slowest run 166 s) is stopped.

| Model | pass | silent | bug fix | min per easy run |
|---|---|---|---|---|
| `ollama/ornith-1.5:35b` | 13/15 | 2 | 2/3 | 0.2-0.7 |
| `unsloth/Inkling-2-Mini-GGUF` | 13/15 | 1 | 1/3 | 0.5-2.4 |
| `ollama/qwen3.6:27b` | 12/15 | 3 | 0/3 | 1.1-5.2 |
| `unsloth/gemma-4-26B-A4B-it-qat-GGUF` | 12/15 | 0 | 0/3 | 0.3-1.9 |
| `unsloth/Qwen3.8-27B-GGUF` | 9/9, stopped for time | 0 | not run | 4.4-18.4 |
| `unsloth/Muse-Glimmer-30B-GGUF` | 1/1, stopped for time | | not run | 2.3+ |
| `prism-ml/Ternary-Bonsai-2-27B-gguf` | 1/1, stopped for time | | not run | 1.8+ |

Ornith 35b stays the default delegate: same score as Inkling, better on the bug fix, several times faster.
gemma-4 never passed the bug fix but its failures were all visible (0 silent). Three runs per cell: one run of
difference is noise.
