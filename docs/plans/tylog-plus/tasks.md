# Execution ledger

Contract: [plan.md](plan.md). Updated 2026-09-20. Coordinator owns this file.

**Main milestones: 8/26 DONE. Active wave: P05 + P09 + P12. Production handoff: real vault restored; sync pending.** Audit checkpoint `b74f5d2` was pushed before implementation began.

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
| P10 | Portable export/conflict-aware re-import | P09 | DONE | [Validated, idempotent, non-destructive round trip](evidence/P10/result.md) |
| P11 | Route existing edits/buttons through DB | P08,P10 | DONE | [Edits/deletes](evidence/P11a/result.md) and [creation/import](evidence/P11c/result.md) durable |
| P12 | Paged startup/list reads | P11 | RUNNING | Startup/open/save gates |
| P13 | Incremental FTS and filters | P11 | DONE | FTS5, changed-record refresh, UI fallback routing, multilingual latency gate |
| P14 | Persistent jobs | P08 | DONE | Resume/cancel/deduplicate/stale result tests |
| P15 | Revision upload/attachments | P08 | RUNNING | Durable outbox publication contract next |
| P16 | Transactional receive/conflict handling | P15 | RUNNING | Parent-checked receive contract landed; sync convergence wiring remains |
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
| P09c2b resumable batch runner | Codex Luna | DONE | P09c2a | [7 restart/accounting/privacy tests pass](evidence/P09c2b/result.md) |
| P09d1 database lifecycle seam | Codex Luna | DONE | P09c2b | [One open/close per HomeScreen lifecycle](evidence/P09d1/result.md) |
| P09d2a restart-safe materialization | Codex Luna | DONE | P09d1 | [Checkpointed path survives interruption](evidence/P09d2a/result.md); one node/revision after resume |
| P09d2b durable UI adapter | Codex Luna | DONE | P09d2a | [Deterministic adapter, rerun accounting, and interruption-safe UI](evidence/P09d2b/result.md) |
| P09d3 assets + cancellation | Codex Luna | DONE | P09d2b | [Assets recover from committed nodes; cancellation leaves pending work resumable](evidence/P09d3/result.md) |
| P09d4 synthetic rehearsal | Coordinator + Codex Luna | DONE | P09d3 | [10k restart rehearsal and validation overhead measurement](evidence/P09d4/result.md) |
| P09d5 private A024 rehearsal | Coordinator | READY | P09d4 | Aggregate manifest=terminal counts; vault remains readable; no private logs committed |
| P05.0 model/runtime contract | Codex Luna | DONE | P04 | [Pinned and independently verified](evidence/P05/contract.md) |
| P05.1a private-pack validator | Codex Luna | DONE | P05.0 | 5 tests enforce counts, labels, offsets, cross-language balance, and private output |
| P05.1b judged 90-query pack | Coordinator | WAITING | P05.1a | Private validator confirms 30 EN + 30 PT + 30 RU; whole-file hash recorded |
| P05.2 numerical runner | Codex Luna | DONE | P05.0 | [6 tests + repeatable offline Mac smoke](evidence/P05/numerical-runner.md) |
| P05.3 Mac exact-cosine benchmark | Codex Luna | DONE | P05.2 | [10k/250k latency and RSS pass](evidence/P05/mac-exact-search.md) |
| P05.4a1 isolated Rust ORT spike | Codex Luna | DONE | P05.2 | [Pinned build/test + offline Mac 384d smoke](evidence/P05/rust-ort-spike.md) |
| P05.4a2 Android cross-build | Codex Luna | DONE | P05.4a1 | [ARM64 cross-build passes](evidence/P05/android-arm64-cross-build.md); device vector agreement pending P05.4b |
| P05.4b Android profile harness | Coordinator + Codex Luna | HOST COMPLETE / DEVICE PENDING | P05.4a2 | [ORT bridge, arm64 profile APK, and package inspection](evidence/P05/android-profile-harness.md); private model install and offline vector smoke remain device-gated |
| P05.4c A024 exact search/PSS | Coordinator + Codex Luna | READY | P05.4b | 250k cold <=6 s, warm p95 <=3 s, PSS <=750 MB |
| P05.4d sustained resume | Coordinator + Codex Luna | READY | P05.4c | Forced stop resumes bounded batches; final count/hash matches uninterrupted run |
| P05.5 sqlite-vec fallback | Codex Luna | CONDITIONAL | P05.3 or P05.4 fails | Run only if exact search misses a gate; same vectors/query interface |
| P05.6 judged retrieval quality | Coordinator | WAITING | P05.1b-P05.4 | 90 judged queries; Recall@10 >=85% overall and >=80% per language/subgroup |
| P05.7 reproduction/acceptance | Coordinator | READY | P05.0-P05.6 | Commands/hashes reproduced; redacted evidence linked; P05 marked DONE |
| P10a portable snapshot codec | Codex Luna | DONE | P09 host work | [Deterministic validated ZIP preserves graph rows and portable vault files](evidence/P10/result.md) |
| P10b conflict-aware merge planner | Codex Luna | DONE | P10a row contract | [Stable IDs classify insert/unchanged/conflict without overwrite](evidence/P10/result.md) |
| P10c transactional round trip | Coordinator | DONE | P10a,P10b | [Fresh restore, idempotent re-import, conflict retention, rollback on failure](evidence/P10/result.md) |
| P11a1 note persistence adapter | Codex Luna | DONE | P08,P10 | [Stable node + parented revision + queues](evidence/P11a/result.md) |
| P11a2 editor save integration | Coordinator | DONE | P11a1 | [DB failure keeps editor dirty and restores the prior file](evidence/P11a/result.md) |
| P11b shared mutation integration | Coordinator | DONE | P11a2 | [Existing task/status/rating/repair buttons create durable revisions](evidence/P11a/result.md) |
| P11c creation/import routing | Coordinator + Codex Luna | DONE | P11b | [Created files have matching initial nodes/revisions; failures leave no phantom file](evidence/P11c/result.md) |
| P11d deletion contract | Coordinator + Codex Luna | DONE | P11a2 | [Immutable tombstone revision; article delete routed](evidence/P11a/result.md) |
| P12a one maintenance listing | Codex Luna | DONE | P11 | [One recursive vault listing per pass; index/validation/sweep results unchanged](evidence/P12a/result.md) |
| P12b non-blocking startup cache | Coordinator | DONE | P12a | [Editor readiness no longer decodes the full cache on the root isolate](evidence/P12b/result.md) |
| P12c 50-row keyset query | Coordinator | DONE | P09,P11 | Completeness marker plus indexed node-summary pages; no offset pagination |
| P12d paged list surfaces | Coordinator | DONE | P12c | Picker, Library, and Articles use bounded SQLite pages with live-index fallback |
| P12e latency acceptance | Coordinator | HOST COMPLETE / DEVICE PENDING | P12a-P12d | Host p95 gates recorded; release/profile Android samples remain |

Dispatch rule: at most two implementation subagents plus one reviewer. Each subagent owns disjoint files, runs its focused check, and does not commit. The coordinator reviews, integrates, runs the broader checks, updates this ledger, then commits and pushes the accepted checkpoint.

## Next tickets

- P01b: DONE; actual A024 backup and independent verification recorded in [evidence](evidence/P01/result.md).
- P04b: DONE; the existing scanner plus `/usr/bin/time` supplies the timing/memory runner, and the privacy-safe aggregate manifest covers production and fixtures.
- P08: DONE; content, immutable revision, outbox and derived invalidation commit atomically.
- P09: RUNNING; host work through P09d4 is complete, while P09d5 requires the private A024 vault.
- P10: DONE; UI routing for portable export/import belongs to P11.
- P11: DONE; every current edit, creation, import, mutation, and delete route uses durable storage.
- P12: RUNNING; first remove repeated full-vault listings, then remove root-isolate cache decoding and route list surfaces through 50-row keyset pages.
- Break later milestones into owned execution tickets before dispatch. Do not infer implementation details missing from the contract, especially P16 conflict materialization.
