# Local model bench

Measures whether a local coding model can be trusted with TyLog work, on five
tasks cut from this repo's own history. Base commit is fixed (`BASE` in
`run.sh`), so results stay comparable across models and dates.

    tool/model_bench/run.sh <provider> <model> [reps=3] [task ...]
    tool/model_bench/report.py            # table from results.jsonl

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
