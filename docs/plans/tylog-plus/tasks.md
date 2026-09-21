# Execution ledger

Contract: [plan.md](plan.md). Updated 2026-09-20. Coordinator owns this file.

**Main milestones: 13/26 DONE. Active wave: P05 + P09 + P12 + P18–P24. Production handoff: real vault restored; sync pending.** Audit checkpoint `b74f5d2` was pushed before implementation began.

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
| P12 | Paged startup/list reads | P11 | RUNNING | A24 startup/open/save pass; five-minute frame gate remains |
| P13 | Incremental FTS and filters | P11 | DONE | FTS5, changed-record refresh, UI fallback routing, multilingual latency gate |
| P14 | Persistent jobs | P08 | DONE | Resume/cancel/deduplicate/stale result tests |
| P15 | Revision upload/attachments | P08 | DONE | Revision envelopes and binary assets use the durable Nextcloud file-sync retry path |
| P16 | Transactional receive/conflict handling | P15 | DONE | Revision envelopes are decoded and parent-checked during sync |
| P17 | Snapshot bootstrap/recovery | P16 | DONE | [Archive bootstrap, resumable recovery, and damaged-state rejection](evidence/P17/result.md) |
| P18 | PDF reader/versioned extraction | P07,P14 | RUNNING | In-app PDF reader and persisted selection implementation underway; native smoke pending |
| P19 | Durable annotations/navigation | P18 | RUNNING | Versioned storage and reader reassignment action landed; sync and corpus acceptance remain |
| P20 | Chunking/offline embeddings | P05,P14,P18 | RUNNING | Deterministic chunks, resumable jobs, and native ORT adapter landed; isolate/device/quality gates remain |
| P21 | Hybrid retrieval/cited navigation | P13,P19,P20 | RUNNING | SQLite-backed vector bridge and bounded hybrid seam land; query embedding, ID mapping, UI/citations, and Dart/device gates remain |
| P22 | Evidence relations/bounded graph | P07,P12 | RUNNING | [Cycle-safe traversal, durable edge edits, and deterministic SVG export](evidence/P22/result.md) |
| P23 | Complete research workflow | P19,P21,P22 | RUNNING | Host filter-to-vault report path now integrated; retrieval/UI/native workflow acceptance remains |
| P24 | Migration rehearsal/integrated failures | P10,P12,P17,P23 | RUNNING | [Host rehearsal covers restore, interruption, permissions, migration, and regression paths](evidence/P24/result.md) |
| P25 | Production migration/release acceptance | P03,P24 | BLOCKED | [Ready-to-run release acceptance; blocked by real Nextcloud/release acceptance](evidence/P25/result.md) |
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
| P20a embedding batch seam | Coordinator | DONE | P20 chunk contract | [Bounded callback runner retries pending chunks after failure](evidence/P20/result.md) |
| P20b native ORT adapter | Coordinator | DONE | P05.4b,P20a | [Pinned Android embed API feeds Float32-compatible batch vectors](evidence/P20/result.md) |
| P21c stored-vector bridge | Coordinator | DONE | P20a,P21b | [Bounded SQLite candidate loading and model-safe top-K search](evidence/P21/result.md) |
| P21d bounded hybrid seam | Coordinator | DONE | P21c | [Stored vectors and keyword IDs share one async fusion entry point](evidence/P21/result.md) |
| P23b report write integration | Coordinator | DONE | P23 helper coverage | [Filtered notes produce deterministic Typst in the vault](evidence/P23/result.md) |
| P22c graph query-plan gate | Coordinator | DONE | P22b | [Both bounded edge endpoints retain indexed query plans](evidence/P22/result.md) |
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
| P12e latency acceptance | Coordinator | DEVICE TIMING PASS / FRAME BLOCKED | P12a-P12d | Normal profile VM timeline now confirms interactive long-note stalls: human-paced typing p95 39.88 ms, 31/68 frames over 16.7 ms; full-document editor path remains the blocker |
| P12f editor mode gate | Coordinator | DEVICE VERIFIED / FRAME BLOCKED | P12e | 46 KB / 220-block SAF fixture selects the stock TextField path, but p95 39.01 ms and 33/114 over-budget frames show full-document RenderEditable still fails the gate |
| P12g virtualized block editor | Coordinator | DEVICE VERIFIED / FRAME BLOCKED | P12f | `VirtualPlainEditor` renders one visible `EditText`, and A24 typing/Enter/Backspace/undo work; p95 37.83 ms with 32/120 over-budget frames still fails the gate |
| P12h editor parity + frame gate | Coordinator | TODO | P12g | Host editor suite passes; A24 five-minute workload reaches <=1% dropped-frame equivalents and no feature-regression checks fail |
| P12i model update benchmark | Coordinator | DONE | P12e | 1,200 long-note appends: p50 2.76 ms, p95 9.54 ms, max 13.14 ms; model path is below the 50 ms per-edit ceiling |
| P12j frame-timing gate | Coordinator | HOST HARNESS READY / DEVICE PENDING | P12e | `p12_editor_frame_native_test.dart` now uses Flutter `FrameTiming`; A24 run must collect >=1,000 frames and stay at <=1% dropped-frame equivalents |

Dispatch rule: at most two implementation subagents plus one reviewer. Each subagent owns disjoint files, runs its focused check, and does not commit. The coordinator reviews, integrates, runs the broader checks, updates this ledger, then commits and pushes the accepted checkpoint.

## Next tickets

- P01b: DONE; actual A024 backup and independent verification recorded in [evidence](evidence/P01/result.md).
- P04b: DONE; the existing scanner plus `/usr/bin/time` supplies the timing/memory runner, and the privacy-safe aggregate manifest covers production and fixtures.
- P08: DONE; content, immutable revision, outbox and derived invalidation commit atomically.
- P09: RUNNING; host work through P09d4 is complete, while P09d5 requires the private A024 vault.
- P10: DONE; UI routing for portable export/import belongs to P11.
- P11: DONE; every current edit, creation, import, mutation, and delete route uses durable storage.
- P12: RUNNING; database/list latency gates pass, while P12e is blocked by full-document `RenderEditable` layout. Continue with P12f mode gating, P12g visible-block editing, then P12h parity and the A24 <=1% frame gate.
- Break later milestones into owned execution tickets before dispatch. Do not infer implementation details missing from the contract, especially P16 conflict materialization.

## Acceptance correction — 2026-09-20

Independent code review reopened P22–P24. Earlier DONE entries described helper/unit-test coverage, not their full plan acceptance. P22 still needs graph UI wiring; P23 still needs an integrated research workflow; P24 still needs actual process-kill/restart and full rehearsal. The P21 NumPy numbers benchmark a different implementation and cannot validate Dart retrieval. A24 is currently connected; device absence is no longer a blocker. No credentials or account setup were inferred from device availability.

| Ticket | State | Measurable exit |
|---|---|---|
| P10d annotation export repair | DONE | Versions + annotations round-trip unchanged, repeat import no-op, conflict preserves local |
| P18b native PDF reader | REVIEW | Attachment opens in-app; PDFium extraction persisted; image-only PDF readable |
| P19b selection persistence | DONE | Select/save/reopen/navigate on native reader; duplicate quote requires review |
| P19c manual reassignment seam | DONE | Existing annotation identity and offsets update transactionally; visible review action remains |
| P19d reader reassignment action | DONE | Needs-review dialog activates replacement mode; selection and Save highlight update the existing annotation |
| P21b candidate safety | DONE | Duplicate IDs counted once; retained cosine results O(k); same ID namespace documented |
| P22b traversal budget | DONE | At most 200 nodes/500 examined edges; missing seed empty; fanout test passes |
| P24b post-commit process death | DONE | A24 force-stop retains annotation/source version; native reopen/navigation passes |

### This implementation wave

Luna subagents implemented anchor safety, bounded candidate selection, graph traversal, and the reader storage seam. Coordinator reviewed/integrated, corrected surrogate-overlap progress, repaired export, added reader UI, and executed native tests. Provider token usage was not exposed; one later Luna review hit the account usage limit.

Still required before full acceptance: P05 Android model parity/latency/memory + 90 judged queries; P09 private import rehearsal; P12 startup/open/save/frame measurements; P18 corpus/Mac reader checks; P19 manual reassignment and sync; P20 embedding runtime scheduling; P21 production hybrid pipeline and cited navigation; P22 graph UI/layout/export wiring; P23 end-to-end workflow; P24 integrated failure rehearsal; P25 real Nextcloud/release integrity; P26 seven days of use.

Current wave verification: 736 host tests passed, 2 skipped; targeted analyzer clean; PDF reader native fixture passed on Mac and A24; A24 post-commit force-stop/reopen passed. Normal Android profile build installed over production with registry fingerprint unchanged; normal ARM64 Mac release built and launched. Universal Mac release packaging remains open.

Follow-up checkpoint: P18 no-text vector PDF native acceptance passed on Mac and A24 (2 tests each); P25 repeatable ARM64 release script built successfully. Universal build root cause reproduced directly in local Xcode `lipo`; full milestone gates remain as above. Luna owned the native test addition; coordinator corrected its finder, ran both platforms, and documented the build command.

P12 follow-up: the bounded 30-startup/100-save workload passed on A24 in the debug integration runner (startup p95 6 ms, save p95 9 ms). This does not close P12e because the required profile-build and normal app-startup measurements remain separate gates.

Additional P12 evidence: 30 cold starts of the installed production profile package on A24 measured `TotalTime` p50 417 ms, p95 450 ms, max 452 ms. Startup passes the 2,000 ms gate; normal editor save/open timing remains pending.

The A24 debug integration runner also exercised `WorkspaceController.save()` 100 times with a 50 KB note: p50 11 ms, p95 15 ms, max 179 ms. The p95 gate passed; profile-build repetition remains pending.

Profile repetition completed through `flutter drive --profile`: 100 workspace saves measured p50 3 ms, p95 4 ms, max 23 ms, and 100 normal note opens measured p50 0 ms, p95 0 ms, max 1 ms. P12 startup/open/save timing gates now pass on A24; the five-minute frame-budget workload remains open.

Profile worker attribution also passed on A24 (2,000-note synthetic workload, 12 seconds): worst gaps 26/18/25/16 ms across index, communities, projection, and search phases. This is partial frame evidence only; the five-minute real-editor workload remains open.

The first real-editor frame probe is a blocker: a 36 KB note with edits every 250 ms caused 267 skipped Android frames and made the profile app unresponsive before five minutes. The probe was removed after capture; P12 remains open for editor rebuild/layout remediation and a repeatable five-minute run.

The first remediation removed a full document reparse for plain-note keystrokes. A 30-second follow-up stayed responsive but still recorded 998 late frames out of 1,840 (worst gap 37 ms), so the 1% frame gate remains blocked. The 2026-09-21 follow-up also removed the unconditional full-document undo copy on every keystroke; a repeatable A24 run is required to quantify the gain before deciding whether virtualized/block-level editing is still necessary.

P22 follow-up: graph rendering now caps the UI layout at 200 nodes and 500 edges, retaining the current/high-degree nodes deterministically. Graph tests pass; graph UI interaction/export acceptance remains open.

P22 export wiring: GraphView now offers `Export SVG`, sharing the bounded graph through the existing platform share path as `tylog-graph.svg`. Native share-sheet acceptance remains open.

The graph widget test now covers the visible action and callback handoff; 19 graph tests pass. Native share-target verification remains open.
