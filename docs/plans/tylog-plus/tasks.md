# Execution ledger

Contract: [plan.md](plan.md). Updated 2026-09-14. Coordinator owns this file.

**Main milestones: 0/26 DONE. Production handoff: incomplete.** Audit checkpoint `b74f5d2` was pushed before implementation began.

| ID | Task | Dependencies | State | Acceptance |
|---|---|---|---|---|
| P01 | Back up and inventory real phone vault/configuration | — | BLOCKED | Verified before/after/device/local hashes; phone currently disconnected |
| P02 | Restore production selection and normal release without uninstall | P01 | TODO | Real notes/settings persist across restart |
| P03 | Real Mac–phone sync and existing controls | P02 | TODO | Both-direction edit, attachment, offline retry, conflict |
| P04 | Corpus fixtures and benchmark runner | P01 | RUNNING (synthetic subtask only) | Reproducible real/10k/100k manifests and baseline |
| P05 | Offline embedding/vector feasibility | P04 | TODO | Runtime/model, quality, latency, memory, sustained run |
| P06 | Database bootstrap/migration tests | P04 | TODO | WAL/FK, creation and upgrade tests |
| P07 | Nodes/edges/sources/revisions | P06 | TODO | Atomic write, invalid reference, dates, duplicate ID |
| P08 | Transactional edit/outbox/jobs | P07 | TODO | Failure injection all-or-nothing |
| P09 | Resumable legacy import | P07 | TODO | Interruption/retry, every source accounted for |
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

[Accepted tool evidence](evidence/P01a/result.md): 30 focused tests pass, including an interrupted-source main-flow check. P01 itself remains BLOCKED until a real device backup passes verification.

### P04a — synthetic fixture generator (DONE; Codex Luna)

Own `tool/tylog_scale_fixture.py` and `test/tool/test_tylog_scale_fixture.py`. Stdlib-only, streaming deterministic JSONL + SHA256 manifest; EN/PT/RU, heterogeneous text lengths, skewed hubs, valid node/edge/chunk references and source slices. Default counts match scale target; refuse nonempty destination. Unit tests assert determinism, changed-seed behavior, hashes/counts, endpoint/offset integrity and invalid arguments. Medium/full generation measurements live outside git; redacted summary only. This subtask may run before P01 because it never reads production data. It does not complete P04 or establish app performance. [Accepted evidence](evidence/P04a/result.md): 4 tests and independent full-scale file hash/count verification passed.

## Next tickets

- P01b: actual device backup/verification; requires connected unlocked A024 and P01a acceptance.
- P04b: reproducible timing/memory command runner and real-corpus manifest; requires P01.
- Break later milestones into owned execution tickets before dispatch. Do not infer implementation details missing from the contract, especially P16 conflict materialization.
