# Executing one remediation task

This is a dispatch protocol for [plan.md](plan.md), not permission to start all implementation merely by reading it. The current user request created the plan. Start implementation when the user asks to execute it or a selected batch.

## Coordinator

1. Read the tracker. Select a task with satisfied dependencies; claim its exact files and record RUNNING/owner. Check current changes so previous work is preserved. T00 can remain waiting while software work proceeds.
2. Give a fresh subagent only this protocol, its task card, the applicable repository instructions, and short dependency decisions/evidence. Extract the card between its `## Txx` heading and the next heading. Supply absolute paths rooted at `/Users/berloga/Documents/GitHub/TypstSeq`. The child reads relevant source itself; do not paste the audit, full source files, or parent transcript.
3. Use the tracker model with `fork_turns="none"` and explicit reasoning effort. In the current tool interface, Luna and Terra are available for these roles. If the requested model cannot be selected, record that limitation and use a supported routing choice rather than claiming a cheaper model was used.
4. The child owns one task and its regression tests. Aim for one behavior, usually 1–3 production files. If the seam requires several unrelated changes, split the task at the discovered boundary. After two unsuccessful repair attempts, return the repro and findings; the coordinator re-scopes or escalates the bounded question to Terra/the parent. This is a checkpoint, not permission to abandon authorized work.
5. Serialize shared-file writers and Flutter build/test commands that contend for the same workspace. Read-only investigation can run alongside a writer. Review the worker's diff and result; use an independent Terra reviewer for save, sync, mutation, and ownership changes. A reviewer receives the task criteria, changed-file list, diff, and test evidence, not the worker's full reasoning transcript. Reviewer fixes return to the owning worker.
6. Mark REVIEW on worker completion; mark DONE only after acceptance criteria, relevant existing tests and review pass. Store result notes/raw logs under `evidence/Txx/` when produced; that directory has one worker owner. Use task-specific temporary/output filenames so parallel workers cannot overwrite each other’s evidence. Run `graphify update .` after a coordinated code-change batch with no competing graph writer. The coordinator owns tracker/graph updates; workers return their outcomes rather than racing on shared status files.
7. Finish one milestone with an abbreviated checkpoint: IDs done, evidence, interface decisions, remaining blockers and next eligible ID. The tracker and evidence must be sufficient to resume in a new conversation. Starting a fresh child prevents history inheritance; it does not erase the parent's existing context.

Planning estimates: a narrow Luna task is usually one 15–30 minute work session; a Terra task one 30–60 minute session, including targeted checks. These are scope estimates, not completion guarantees. If a task cannot fit one behavior and one bounded session, split it before a broad rewrite. Do not use unmeasured token/cost savings as success criteria. Record model, attempts and elapsed time; record token usage only when actually reported by the tools. Raw logs stay in files.

## Dispatch template

Use `collaboration.spawn_agent` for delegated work inside the current task, not sidebar task creation. Fill the card and allowed files concretely before dispatch:

```json
{
  "task_name": "t02_worker_shutdown",
  "model": "gpt-5.6-terra",
  "reasoning_effort": "high",
  "fork_turns": "none",
  "message": "Implement T02 only in /Users/berloga/Documents/GitHub/TypstSeq. Read docs/audits/2026-09-06/delegation.md and only the T02 section of tasks.md. Dependencies: T01 DONE; evidence: <actual path>. Own lib/vault_worker.dart and test/vault_worker_test.dart; request scope expansion if required. Follow applicable AGENTS.md and use the existing graphify query before source exploration. Establish the regression, implement the smallest fix, run relevant checks, and return the result format below. Preserve unrelated changes. Do not spawn more agents or update the tracker."
}
```

A fresh worker for each independent task is the default. Reuse a worker only for a review correction to that same task, with a short message identifying the failed criterion. Limit concurrent workers to useful independent work; spawning more agents itself costs context and tokens.

## Worker result: at most 200 words

```text
Task: Txx
Outcome: READY_FOR_REVIEW | NEEDS_SCOPE | BLOCKED | NOT_REPRODUCED
Model / attempts / elapsed: actual values
Changed files: paths
Reproduction: command + observed failure before change
Validation: commands + pass/fail counts + evidence paths
Acceptance: each criterion satisfied or remaining
Decision for downstream tasks: changed contract, or none
Limitations: device checks pending / concrete blocker / none
```

Create one result note containing these fields. Include only the failure excerpt needed to assess the cause; keep complete logs separately. A code-confirmed audit finding is not automatically a reproduced failure. For measurement tasks, a well-supported “no change needed” can satisfy the card; report that separately from an implemented fix.

## Testing and promotion

- Reuse the five audit probes. For a relevant bug, demonstrate red→green and put a focused regression into the normal `test/` suite. Keep the historical output immutable. The explicit audit file may remain as an additional check or delegate to promoted tests; assertions must keep their behavioral meaning.
- Use gated storage/network futures and fake time for ordering/retry assertions. Avoid real 25-second waits or timing a desktop test as if it were a phone benchmark.
- Worker checks cover the changed behavior and its affected existing tests. T27 runs the full suite, scoped analysis and 10k gate once changes have settled. Extra full-suite reruns need a new change or failure to justify them.
- Preserve atomic writes, conflict semantics, edit revisions and device data. Device profiling uses profile builds and a deliberately selected isolated vault. Installation over release preserves the vault; it does not make a production vault an appropriate test fixture.
- Track native work as pending until actual device evidence exists. Build/test failures caused by missing tools or package setup are recorded separately from product regressions.

## Source for delegation choices

OpenAI's [subagent guidance](https://learn.chatgpt.com/docs/agent-configuration/subagents) recommends bounded prompts, condensed returns and care with simultaneous code edits. It describes Luna as suitable for narrow, repeatable work. The exact Luna/Terra task assignments and fresh-context dispatch parameters here are this project's plan, based on the tools exposed in this session; they are not guaranteed savings or a change to global Codex configuration.
