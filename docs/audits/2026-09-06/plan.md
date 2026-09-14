# Reliability remediation tracker

Created 2026-09-06 from [the audit](audit.md), baseline `bacbf11` / `0.4.4+99`.
**Audit complete: 31/31 tasks done.** All 13 original audit findings have implementation evidence. Connected-phone validation also found and fixed the Android worker-shutdown blocker tracked as T30; device-network limitations are explicit in T00/T28 evidence.

Use this file for status; [task cards](tasks.md) for scope and acceptance; [delegation instructions](delegation.md) for execution. Load only the assigned card when delegating.

## Outcomes to measure

| Measure | Audited baseline | Acceptance target | Evidence owner |
|---|---|---|---|
| Extra scans from two pre-transfer rejected polls | 2 | 0 | T03 |
| Cold startup index publications | 2 | 1 necessary pass | T05 |
| Active worker completion after dispose | Hung beyond 1 second | Settles within 1 second in controlled test | T02 |
| Navigation after rejected save | Switched note, dirty=false | Original buffer retained, dirty=true | T08 |
| Presets after saving A then B | B only | A and B; chips match storage | T17 |
| Open-buffer mutation survival | Code-confirmed risk; not measured | All tested mutations survive later saves | T12–T14 |
| Late old-vault/note results | Code-confirmed risk; not measured | Zero stale publications in gated tests | T09–T10 |
| Phone first-usable/sync time, frames | Unmeasured | T00 baseline, T28 matched comparison | T00/T28 |
| Unnecessary idle content scans | Unmeasured on device | 0 in 5 minutes after settling | T28 |

Counts are stronger gates than guessed speedups. Device performance targets are proposed acceptance criteria, not measured improvements or promises.

## Queue

`READY` may be claimed; `TODO` becomes ready only when dependencies are DONE; `RUNNING` has one owner; `REVIEW` awaits coordinator acceptance; `DONE` has passing evidence; `WAITING_DEVICE` has an external requirement; `BLOCKED` records a concrete impediment. Only the coordinator updates this table. Evidence is a link to logs/result notes and the reviewed commit or diff fingerprint, not simply “passed”.

Model: **L** = `gpt-5.6-luna`, medium; **T** = `gpt-5.6-terra`, high. These are this plan's routing choices using models exposed by this session. Use explicit fresh-context delegation. Simple read-only measurement runs may use low effort. Reassess availability at dispatch.

| ID | Task | Audit | Model | Depends on | Status | Owner | Evidence |
|---|---|---|---|---|---|---|---|
| [T00](tasks.md#t00) | Capture phone baseline | Device | L | — | DONE | coordinator | [result](evidence/T00/result.md) |
| [T01](tasks.md#t01) | Verify and index the five existing probes | All | L | — | DONE | coordinator | [result](evidence/T01/result.md) |
| [T02](tasks.md#t02) | Settle active worker commands on shutdown | F02 | T | T01 | DONE | coordinator + Luna review | [worker result](evidence/T02/result.md) |
| [T03](tasks.md#t03) | Reindex a failed sync only after local content changes | F01 | T | T01 | DONE | coordinator + Luna | [result](evidence/T03/result.md) |
| [T04](tasks.md#t04) | Pause rejected credentials and back off transient retries | F01 | L | T03 | DONE | Terra implementation + Luna verification | [result](evidence/T04/result.md) |
| [T05](tasks.md#t05) | Run one necessary startup index pass | F05 | L | T02,T03 | DONE | resume_verify (Luna) | [result](evidence/T05/result.md) |
| [T06](tasks.md#t06) | Protect startup sync when backgrounded | F10 | L | T05 | DONE | resume_verify (Luna) | [result](evidence/T06/result.md) |
| [T07](tasks.md#t07) | Make save success explicit | F03 | T | T01 | DONE | resume_verify (Luna) | [result](evidence/T07/result.md) |
| [T08](tasks.md#t08) | Gate note and vault navigation on successful save | F03 | L | T07 | DONE | resume_verify (Luna) | [result](evidence/T08/result.md) |
| [T09](tasks.md#t09) | Prevent old vault operations publishing new-vault state | F13 | T | T02,T05,T07 | DONE | t09_vault_generation (Luna) | [result](evidence/T09/result.md) |
| [T10](tasks.md#t10) | Make the latest note selection win | F13 | L | T08,T09 | DONE | resume_verify (Luna) | [result](evidence/T10/result.md) |
| [T11](tasks.md#t11) | Establish one buffer-aware note mutation path | F04 | T | T07,T09,T10 | DONE | t09_vault_generation (Luna) | [result](evidence/T11/result.md) |
| [T12](tasks.md#t12) | Route task checkbox/status changes through the mutation path | F04 | L | T11 | DONE | t09_vault_generation (Luna) | [result](evidence/T12/result.md) |
| [T13](tasks.md#t13) | Route article status/relevance/rating through the mutation path | F04 | L | T11 | DONE | t09_vault_generation (Luna) | [result](evidence/T13/result.md) |
| [T14](tasks.md#t14) | Check bulk rewrite and conflict resolution against open edits | F04 | T | T11 | DONE | t09_vault_generation (Luna) | [result](evidence/T14/result.md) |
| [T15](tasks.md#t15) | Open a new page before background indexing | F06 | L | T08,T10 | DONE | resume_verify (Luna) | [result](evidence/T15/result.md) |
| [T16](tasks.md#t16) | Refresh after rating/delete without cancelling indexing | F07 | L | T13 | DONE | t09_vault_generation (Luna) | [result](evidence/T16/result.md) |
| [T17](tasks.md#t17) | Keep saved searches current in storage and UI | F08 | L | T01 | DONE | coordinator + Luna | [result](evidence/T17/result.md) |
| [T18](tasks.md#t18) | Publish search readiness and revision after the index swap | F09 | T | T02,T05 | DONE | t09_vault_generation (Luna) | [result](evidence/T18/result.md) |
| [T19](tasks.md#t19) | Refresh an open Search screen when its index changes | F09 | L | T17,T18 | DONE | resume_verify (Luna) | [result](evidence/T19/result.md) + replacement-state check |
| [T20](tasks.md#t20) | Refresh assets for the current note revision | F11 | L | T10 | DONE | resume_verify (Luna) | [result](evidence/T20/result.md) |
| [T21](tasks.md#t21) | Wait for current assets before sharing PDF | F11 | L | T20 | DONE | resume_verify (Luna) | [result](evidence/T21/result.md) |
| [T22](tasks.md#t22) | Define a bounded report dependency strategy | F12 | T | T01 | DONE | t22_report | [contract](evidence/T22/result.md) |
| [T23](tasks.md#t23) | Load report dependencies without unrelated vault media | F12 | T | T22,T29 | DONE | resume_native (Luna) | [result](evidence/T23/result.md) |
| [T24](tasks.md#t24) | Make cancellation work after note scanning | Cancellation risk | T | T02 | DONE | Luna + coordinator | [result](evidence/T24/result.md) |
| [T25](tasks.md#t25) | Measure dashboard diagnostic reload overhead | Dashboard risk | L | T01 | DONE | coordinator + resume_verify (Luna) | [result](evidence/T25/result.md) |
| [T26](tasks.md#t26) | Measure Android SAF contention | SAF risk | T | T00 | DONE | coordinator + resume_verify (Luna) | [result](evidence/T26/result.md) |
| [T27](tasks.md#t27) | Run integrated software regression gate | All fixes | L | T04,T06,T08,T09,T10,T12,T13,T14,T15,T16,T19,T21,T23,T24 | DONE | t09_vault_generation (Luna) | [result](evidence/T27/result.md) |
| [T28](tasks.md#t28) | Verify the reported phone symptom and close the audit | Device | T | T00,T25,T26,T27,T30 | DONE | coordinator + resume_verify (Luna) | [result](evidence/T28/result.md) |
| [T29](tasks.md#t29) | Expose canonical compiler file requests | F12 | T | T22 | DONE | Terra + Luna | [result](evidence/T29/result.md) |
| [T30](tasks.md#t30) | Drain SAF replies before worker shutdown | Device blocker | L | T00 | DONE | resume_native + t09_vault_generation (Luna) | [result](evidence/T30/result.md) |

## Suggested batches

1. **Start:** T01; capture T00 independently when a device exists.
2. **Stop repeat processing:** T02 → T03 → T04 → T05 → T06. T24 can follow T02 when its files are free.
3. **Protect edits:** T07 → T08 → T09 → T10 → T11, then T12 → T13 → T14. Queue T15 and T16 as their dependencies finish.
4. **Repair existing controls:** T17 → T18 → T19; T20 → T21; T22 → T23. Dependencies and file ownership take precedence over this display order.
5. **Measure and close:** T25/T26, then T27/T28. T25/T26 may produce additional evidence-backed fix cards; such work becomes a dependency of final closure. A measured risk with no reproducible impact can close as investigated, with evidence.

One writer at a time in `app_mobile.dart` or `workspace_controller.dart`; at most two workers on disjoint files plus one reviewer. Start T02 with a read-only T22 investigation if useful. Parallelism is optional, never a reason to overlap edits. Await active code changes before running the integration gate.

## Completion accounting

- Task progress = DONE rows / total rows (currently 26/31); update the headline when rows change.
- Finding progress = audit findings whose mapped tasks are DONE / 13. F01 needs T03+T04; F03 T07+T08; F04 T11–T14; F09 T18+T19; F11 T20+T21; F12 T22+T23+T29; F13 T09+T10. Others map directly.
- Desktop software completion and device validation are reported separately. T00/T26/T28 must not become DONE from mocks or desktop results.
- Per milestone, report: completed IDs, fixed finding count, red→green evidence, open blockers, and next eligible ID. Do not reprint the whole audit.
- Native coverage: existing features in this plan receive device checks, not a UI redesign. Any remaining button without a test/check is explicitly listed by T28 rather than implied verified.

## Execution decisions

2026-09-07: T22 found the native resolver is the safe dependency authority, but requests are not exposed to Dart. Split T23 into T29 (compiler seam) then T23 (export integration), keeping the application task bounded and preserving dynamic imports. Total is now 30 tasks. T01 rerun by coordinator after the prior worker was interrupted before writing evidence. No Android device is connected.

2026-09-08: T03/T29 workers stopped at account usage limit. Requested a fresh Luna/low worker to verify the current T02/T03 diff. T29 returned to TODO with no native source change. Routine tasks now use Luna/low; escalate only a demonstrated blocker.

2026-09-08 continuation: T02/T03/T17 accepted after regression review; T04 required Terra implementation assistance, then fresh Luna/medium verified auth and retry tests (38 controller +6 worker tests). T24 has4 package cancellation regressions; T29 has19 passing native tests and regenerated bridge. T05/T23 running on Luna. Device remains disconnected. Fresh bounded Luna/medium packets proved more effective than low-effort requests that repeatedly omitted required tests.

2026-09-09: All 13 software findings are implemented and T27 passed: 5 historical probes, 599 Flutter tests with 1 intentional skip, the 10k benchmark, 209 core tests, 19 Rust tests, 5 macOS PDF integration tests, scoped analysis and diff checks. T00/T25/T26/T28 remain WAITING_DEVICE because `adb devices` reports no connected Android phone.

2026-09-09 device continuation: A Nothing A024 on Android 16 connected. Safe profile checks passed sync attribution, background-isolate SAF access and foreground service operation. Android PDF integration exposed stale pre-T29 native libraries; rebuilding all Android ABIs fixed the bridge hash. First-time selection of an isolated audit vault then reproduced a fatal late SAF response caused by a duplicate initial vault open plus immediate worker-isolate kill. T30 tracks both root fixes before measurements resume.

2026-09-09 device closure: T00/T25/T26/T28/T30 passed on the guarded `TyLogAuditVault` profile fixture. The first 2,001-entry index took 54 seconds, repeat cold display took 440–894 ms, a 303-second idle window produced zero index rewrites, SAF contention raised p95 save latency from 325 ms to 545 ms without integrity loss, and the dashboard profile dropped zero frames. Native worker, foreground, PDF, and Magic-action gates passed. No authentic pre-fix phone timing or disposable-vault Nextcloud account was available; T00/T28 record those limits without an unsupported improvement claim.
