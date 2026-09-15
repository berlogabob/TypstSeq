# Execution ledger

Contract: [plan.md](plan.md). Updated 2026-09-15. Coordinator owns this file.

**Main milestones: 6/26 DONE. Active wave: P05 + P09. Production handoff: real vault restored; sync pending.** Audit checkpoint `b74f5d2` was pushed before implementation began.

| ID | Task | Dependencies | State | Acceptance |
|---|---|---|---|---|
| P01 | Back up and inventory real phone vault/configuration | — | DONE | [11,826 files verified](evidence/P01/result.md) |
| P02 | Restore production selection and normal release without uninstall | P01 | DONE | [Release and real vault persist](evidence/P02/result.md) |
| P03 | Real Mac–phone sync and existing controls | P02 | BLOCKED | No Nextcloud configuration on either device; credentials/user setup required |
| P04 | Corpus fixtures and benchmark runner | P01 | DONE | [Real/10k/100k manifests and baseline](evidence/P04b/result.md) |
| P05 | Offline embedding/vector feasibility | P04 | RUNNING | Runtime/model, quality, latency, memory, sustained run |
| P06 | Database bootstrap/migration tests | P04 | DONE | [Background SQLite, WAL/FK, creation and upgrade tests](evidence/P06/result.md) |
| P07 | Nodes/edges/sources/revisions | P06 | DONE | [Atomic writes, references, dates, identity and migrations](evidence/P07/result.md) |
| P08 | Transactional edit/outbox/jobs | P07 | DONE | [Failure-injected all-or-nothing edit transaction](evidence/P08/result.md) |
| P09 | Resumable legacy import | P07 | RUNNING | Interruption/retry, every source accounted for |
| P10 | Portable export/conflict-aware re-import | P09 | TODO | Complete round trip |
| P11 | Route existing edits/buttons through DB | P08,P10 | TODO | Existing controls and save-failure protection |
| P12 | Paged startup/list reads | P11 | TODO | Startup/open/save gates |
| P13 | Incremental FTS and filters | P11 | TODO | EN/PT/RU, latency, changed records only |
| P14 | Persistent jobs | P08 | TODO | Resume/cancel/deduplicate/stale result tests |
| P15 | Revision upload/attachments | P08 | TODO | Interrupted publish and retry |
| P16 | Transactional receive/conflict handling | P15 | TODO | Defined merge/materialization contract + convergence tests |
| P17 | Snapshot bootstrap/recovery | P16 | TODO | Scale restore; damaged snapshot rejected |
| P18 | PDF reader/versioned extraction | P07,P14 | TODO | Selection/extraction; unsupported source accounting |
| P19 | Durable annotations/navigation | P18 | TODO | Source return, stable re-index, ambiguous replacement |
| P20 | Chunking/offline embeddings | P05,P14,P18 | TODO | Versioned resumable changed-source processing |
| P21 | Hybrid retrieval/cited navigation | P13,P19,P20 | TODO | Scale/quality/memory/airplane mode |
| P22 | Evidence relations/bounded graph | P07,P12 | TODO | Edge edits, cyclic traversal bounds, SVG |
| P23 | Complete research workflow | P19,P21,P22 | TODO | Capture-to-cited-report on both devices |
| P24 | Migration rehearsal/integrated failures | P10,P12,P17,P23 | TODO | Restore/disk-full/process-kill/permissions/regressions |
| P25 | Production migration/release acceptance | P03,P24 | TODO | Integrity, sync, correct real vault/build on both devices |
| P26 | Daily-use acceptance/thesis freeze | P25 | TODO | Seven days; every required gate passes |

## Current bounded tickets

### P01a — recovery tool (DONE; Haiku draft, Luna correction, coordinator acceptance)

Own `tool/backup_android_vault.py` and `test/tool/test_backup_android_vault.py`. New private backup destination outside repository; validate device/source/destination; stop app without uninstall/clear; compare remote SHA256 before and after pull against independent local SHA256. Retain failed partial backup; no verified marker on failure. Best-effort app configuration archive explicitly distinguished from guaranteed full Android/Keystore recovery. No secrets in stdout or git. Unit tests: matching hashes, concurrent change, missing/truncated copy, spaces in paths, unsafe paths, unavailable settings. Device execution remains coordinator-owned.

[Accepted tool evidence](evidence/P01a/result.md): 30 focused tests pass, including an interrupted-source main-flow check. P01 is complete with the verified A024 backup.

### P04a — synthetic fixture generator (DONE; Codex Luna)

Own `tool/tylog_scale_fixture.py` and `test/tool/test_tylog_scale_fixture.py`. Stdlib-only, streaming deterministic JSONL + SHA256 manifest; EN/PT/RU, heterogeneous text lengths, skewed hubs, valid node/edge/chunk references and source slices. Default counts match scale target; refuse nonempty destination. Unit tests assert determinism, changed-seed behavior, hashes/counts, endpoint/offset integrity and invalid arguments. Medium/full generation measurements live outside git; redacted summary only. This subtask may run before P01 because it never reads production data. It does not complete P04 or establish app performance. [Accepted evidence](evidence/P04a/result.md): 4 tests and independent full-scale file hash/count verification passed.

### Active wave — bounded subagent tickets

| Ticket | Owner/model | State | Depends on | Measurable exit |
|---|---|---|---|---|
| P09a import checkpoint schema | Codex Luna | DONE | P07 | [Schema v5; 13 database tests pass](evidence/P09a/result.md) |
| P09b deterministic manifest | Codex Luna | DONE | P09a names | [4 tests: stable fingerprint, validation, every file classified](evidence/P09b/result.md) |
| P09c1 atomic import materialization | Codex Luna | DONE | P09a,P08 | [Success + forced rollback proven](evidence/P09c1/result.md) |
| P09c2a durable job initialization | Codex Luna | DONE | P09b,P09c1 | [Idempotent batch create/resume proven](evidence/P09c2a/result.md) |
| P09c2b resumable batch runner | Codex Luna | READY | P09c2a | Derive progress from stored manifest states; forced restart accounts for each source exactly once |
| P09d app adapter + rehearsal | Coordinator + Codex Luna | READY | P09c2b | Existing import UI retained; 10k retry and private A024 aggregate accounting pass |
| P05.0 model/runtime contract | Codex Luna | DONE | P04 | [Pinned and independently verified](evidence/P05/contract.md) |
| P05.1a private-pack validator | Codex Luna | DONE | P05.0 | 5 tests enforce counts, labels, offsets, cross-language balance, and private output |
| P05.1b judged 90-query pack | Coordinator | WAITING | P05.1a | Private validator confirms 30 EN + 30 PT + 30 RU; whole-file hash recorded |
| P05.2 numerical runner | Codex Luna | DONE | P05.0 | [6 tests + repeatable offline Mac smoke](evidence/P05/numerical-runner.md) |
| P05.3 Mac exact-cosine benchmark | Codex Luna | DONE | P05.2 | [10k/250k latency and RSS pass](evidence/P05/mac-exact-search.md) |
| P05.4 A024 sustained benchmark | Coordinator + Codex Luna | READY | P05.2,P05.3 | Profile APK offline; PSS <=750 MB; interruption/resume and sustained run pass |
| P05.5 sqlite-vec fallback | Codex Luna | CONDITIONAL | P05.3 or P05.4 fails | Run only if exact search misses a gate; same vectors/query interface |
| P05.6 judged retrieval quality | Coordinator | WAITING | P05.1b-P05.4 | 90 judged queries; Recall@10 >=85% overall and >=80% per language/subgroup |
| P05.7 reproduction/acceptance | Coordinator | READY | P05.0-P05.6 | Commands/hashes reproduced; redacted evidence linked; P05 marked DONE |

Dispatch rule: at most two implementation subagents plus one reviewer. Each subagent owns disjoint files, runs its focused check, and does not commit. The coordinator reviews, integrates, runs the broader checks, updates this ledger, then commits and pushes the accepted checkpoint.

## Next tickets

- P01b: DONE; actual A024 backup and independent verification recorded in [evidence](evidence/P01/result.md).
- P04b: DONE; the existing scanner plus `/usr/bin/time` supplies the timing/memory runner, and the privacy-safe aggregate manifest covers production and fixtures.
- P08: DONE; content, immutable revision, outbox and derived invalidation commit atomically.
- P09: RUNNING; P09c2b resumable batch execution is the next checkpoint.
- Break later milestones into owned execution tickets before dispatch. Do not infer implementation details missing from the contract, especially P16 conflict materialization.
