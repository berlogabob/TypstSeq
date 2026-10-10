// Source of every figure: ../results.jsonl (60 rows). Regenerate the numbers
// with ../report.py before editing this file.
#import "lib.typ": *

#show: report.with((
  title: "Local Model Bench",
  author: ("TyLog",),
  footer: "TyLog · local model bench · 2026-10-10",
  lang: "en",
))

#title-block(
  "Local Model Bench",
  subtitle: "Which Studio model can be trusted with TyLog coding work",
  meta-line: "Runs 2026-10-09 to 2026-10-10 · base commit 9dbfa0f · data: tool/model_bench/results.jsonl",
  standfirst: [Ornith 1.5 35b passed 14 of 15 runs and finished every small
  task in about half a minute. It is the only model that fixed the real scanner bug
  more than once. No model was free of wrong work that looked finished, so
  every delegated diff still needs a human or codex review. The Ornith 27b
  coder result is a tooling failure, not a measure of that model.],
)

#kpi-row((
  ("14/15", "Ornith 35b passed", "best of four"),
  ("60", "Runs scored", "4 models × 5 tasks × 3"),
  ("6", "Wrong but looked done", "across three models"),
  ("11/11", "Control runs correct", "re-run 2026-10-10"),
))

= Result

#data-table(
  ("Model", "Passed", "Wrong but looked done", "No change made", "Touched other files"),
  (
    ([Ornith 1.5 35b], [14/15], [1], [0], [0]),
    ([Ornith 1.5 9b], [11/15], [2], [1], [1]),
    ([Qwen3-Coder 30B], [9/15], [3], [1], [2]),
    ([Ornith 1.5 27b coder], [1/15], [0], [13], [0]),
  ),
)

#bar-row("Ornith 1.5 35b", "93%", 0.93, tone: "ok")
#bar-row("Ornith 1.5 9b", "73%", 0.73, tone: "warn")
#bar-row("Qwen3-Coder 30B", "60%", 0.60, tone: "warn")
#bar-row("Ornith 1.5 27b coder", "7%", 0.07, tone: "bad")

"Wrong but looked done" counts runs where the model changed code, its own
verify command passed, and the hidden check failed. It is the figure that
decides trust: such work would be merged if nobody read the diff.

= Passes by task

#data-table(
  ("Task", "Ornith 35b", "Ornith 9b", "Qwen3-Coder", "Ornith 27b coder"),
  (
    ([New file from a spec], [3/3], [3/3], [1/3], [1/3]),
    ([Same-value edit, 144-line widget], [3/3], [3/3], [2/3], [0/3]),
    ([One branch in a 2,500-line file], [3/3], [1/3], [3/3], [0/3]),
    ([Real bug fix in `scanner.dart`], [2/3], [1/3], [0/3], [0/3]),
    ([Write a guard test], [3/3], [3/3], [3/3], [0/3]),
  ),
  total: ([Total], [14/15], [11/15], [9/15], [1/15]),
)

#pagebreak(weak: true)
== Median seconds per run

#data-table(
  ("Task", "Ornith 35b", "Ornith 9b", "Qwen3-Coder"),
  (
    ([New file from a spec], [33], [57], [25]),
    ([Same-value edit], [28], [24], [190]),
    ([One branch in a large file], [22], [16], [121]),
    ([Real bug fix], [806], [901], [1,927]),
    ([Write a guard test], [34], [78], [160]),
  ),
)

Medians are used because two Ornith 9b runs (5,697 s and 553 s) were stretched
by the laptop sleeping. Their pass or fail outcome is unaffected. The Ornith
27b coder is left out: its runs ended in 3 to 40 seconds without doing the work.

= Findings

#scorecard((
  ("Ornith 1.5 35b", "Use as default", "ok", "Clean on all four small tasks; fixed the bug in 2 of 3 runs"),
  ("Ornith 1.5 9b", "Small files only", "warn", "Follows a spec; 1 of 3 inside a large file"),
  ("Qwen3-Coder 30B", "Pinpoint edits only", "warn", "3 of 3 in the large file; drops rules from a spec"),
  ("Ornith 1.5 27b coder", "Not measured", "info", "Stops before editing; tool-calling fault not investigated"),
))

- *Ornith 35b* made no error on the 12 small-task runs. Its single failure was
  on the bug fix: the targeted tests passed and two donor-adoption tests
  elsewhere in the core suite broke.
- *Ornith 9b* failed twice on the large-file edit, once printing the literal
  text `<code>` instead of the status code and once making no change, and once touched a file outside its allowlist.
- *Qwen3-Coder* passed the new-file task once in three; both failures ignored
  the rule to keep the detail suffix and still passed lint. On the same-value
  edit it changed a 2 into a 4. It never fixed the bug and twice edited
  files it was told to leave alone.
- *Ornith 27b coder* made no change in 13 of 15 runs. In the one log read in
  full it located the function, announced the edit and ended the turn without
  calling the edit tool. The cause was not investigated.

#callout(title: "Recommendation", tone: "ok")[Make Ornith 1.5 35b the default
Studio model for delegated work, including small edits to existing files that
were going to codex. Keep codex for multi-file and design-heavy fixes. Keep
reading every diff: the best model still produced one wrong result that passed
its own check.]

= Method

Five tasks were cut from this repository's own history, so each has a
known-good answer. Every run starts from commit `9dbfa0f` in a separate git
worktree. The model works through `pi-run.sh` with a visible verify command and
up to three attempts of 900 seconds. The score comes from a check the model
never sees.

#data-table(
  ("Task", "Visible to the model", "Hidden check"),
  (
    ([New file], [lint of the new file], [unit test over the full spec table]),
    ([Same-value edit], [lint of the file], [every number keeps its value; at least 3 tokens used]),
    ([Large-file edit], [lint of the file], [unit test; at most 3 lines deleted; file not truncated]),
    ([Bug fix], [the failing cache tests], [whole core suite passes; tests not edited]),
    ([Write a test], [the new test passes], [test fails when either entitlements file is broken]),
  ),
  right-from: none,
  widths: (1fr, 1.3fr, 2.2fr),
)

== Controls

`selftest.sh` checks the bench itself before any model is scored. All 11
control runs gave the required outcome when re-run for this report.

#data-table(
  ("Control", "Input", "Required", "Result"),
  (
    ([Null], [untouched baseline, 5 tasks], [fail], [5/5 failed]),
    ([Reference], [the real fix from git history, 5 tasks], [pass], [5/5 passed]),
    ([Sloppy], [same-value edit with one number changed], [fail], [1/1 failed]),
  ),
  right-from: none,
  widths: (0.7fr, 2.2fr, 0.7fr, 0.9fr),
)

== Limits

- Three runs per cell. A 2/3 against a 3/3 is one run of difference; only the
  larger gaps are meaningful.
- One harness (pi) and one prompt per task. A model that calls tools
  differently, as the 27b coder appears to, is scored as failing.
- Lint is a weak visible check on three tasks by design, to expose work that
  looks finished. With a stronger visible check some failures would be retried.
- All models ran on the Studio PC, one at a time. Times include model loading
  and the local test runs on the laptop.
- Reproduce with `tool/model_bench/run_all.sh`; the table with `report.py`.
