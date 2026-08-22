# Graph Report - /tmp/tylog-audit-corpus  (2026-08-22)

## Corpus Check
- Corpus is ~4,611 words - fits in a single context window. You may not need a graph.

## Summary
- 116 nodes · 176 edges · 11 communities (9 shown, 2 thin omitted)
- Extraction: 73% EXTRACTED · 27% INFERRED · 1% AMBIGUOUS · INFERRED: 47 edges (avg confidence: 0.85)
- Token cost: 21,400 input · 6,100 output

## Community Hubs (Navigation)
- Donor Sharing and Schema Gating
- Execution Contexts and CLI
- Conflict Incident Scope
- Sync Cost Measurement
- Conflict Auto-Resolution Rules
- Resolve Path and ETag Guard
- Silent Failures and Bulk Resolve
- Typst Inspection and Fallback
- Sync State Format
- Editor Save Loss
- Test Quality

## God Nodes (most connected - your core abstractions)
1. `Failure shape 1: a fix applied to some of N equivalent paths` - 10 edges
2. `_system/index/<device>.json (donor index)` - 9 edges
3. `Donor reuse (inherit facts instead of recompiling)` - 7 edges
4. `Phase 2: auto-resolve the provably-lossless cases` - 7 edges
5. `Failure shape 2: 'absent' read as 'current'` - 6 edges
6. `_index/index.json (vault index)` - 6 edges
7. `.tylog/sync_state.json` - 6 edges
8. `.tylog/conflicts/*.json (conflict record)` - 6 edges
9. `1a: the laptop produces no index at all` - 6 edges
10. `Execution context: UI / root isolate` - 5 edges

## Surprising Connections (you probably didn't know these)
- `Proposed: share one directory listing between sync and the scan that follows` --semantically_similar_to--> `Donor reuse (inherit facts instead of recompiling)`  [INFERRED] [semantically similar]
  2026-08-21-findings-and-fixes.md → 2026-08-22-audit-findings.md
- `SafBridge recursive listing (one ContentResolver.query per directory)` --conceptually_related_to--> `Execution context: UI / root isolate`  [INFERRED]
  2026-08-21-findings-and-fixes.md → 2026-08-22-audit-findings.md
- `1a: the laptop produces no index at all` --references--> `Capability: donor publish`  [INFERRED]
  2026-08-21-findings-and-fixes.md → 2026-08-22-audit-findings.md
- `P0-3: self-heal compared two frozen snapshots and deleted live conflicts` --semantically_similar_to--> `Phase 3c: on ETag mismatch refresh and re-decide instead of throwing`  [INFERRED] [semantically similar]
  2026-08-22-audit-findings.md → 2026-08-21-sync-conflict-recovery.md
- `P2-14: IndexDonorStore.publish swallowed every failure` --semantically_similar_to--> `syncError banner losing its slot to the 'Syncing…' card`  [INFERRED] [semantically similar]
  2026-08-22-audit-findings.md → 2026-08-21-sync-conflict-recovery.md

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Findings that are all 'a fix applied to some of N equivalent paths'** — 2026_08_22_audit_findings_shape_partial_path_fix, 2026_08_22_audit_findings_p0_2, 2026_08_22_audit_findings_p1_7, 2026_08_22_audit_findings_p2_11, 2026_08_22_audit_findings_p2_12, 2026_08_21_findings_and_fixes_1a_laptop_no_index [EXTRACTED 1.00]
- **Capabilities the Android background service lacked** — 2026_08_22_audit_findings_background_service, 2026_08_22_audit_findings_temp_sweep, 2026_08_21_sync_conflict_recovery_phase1_per_path_gate, 2026_08_22_audit_findings_p0_2, 2026_08_22_audit_findings_p2_12 [INFERRED 0.85]
- **Four execution contexts writing one vault under inconsistent locking** — 2026_08_22_audit_findings_ui_isolate, 2026_08_22_audit_findings_worker_isolate, 2026_08_22_audit_findings_background_service, 2026_08_22_audit_findings_cli, 2026_08_22_audit_findings_vault_lock, 2026_08_22_audit_findings_open_locking_inconsistent [EXTRACTED 1.00]

## Communities (11 total, 2 thin omitted)

### Community 0 - "Donor Sharing and Schema Gating"
Cohesion: 0.13
Nodes (22): 1b: a schema bump invalidates every donor at once, 1c: stale donors are never collected, Donor version gate: indexVersion != kVaultIndexVersion → skip, IndexDonorStore.pruneUnusable, Shared index / 'hard computing on the laptop', Audit of the 0.4.x batch — findings and outcomes, _system/index/<device>.json (donor index), Capability: donor load (+14 more)

### Community 1 - "Execution Contexts and CLI"
Cohesion: 0.15
Nodes (21): 1a: the laptop produces no index at all, 3: orphan temp files left by the atomic-write path, CliTypstInspector, tylog index (packages/tylog_core/bin/tylog.dart:49), _writeIndexDonor (lib/vault.dart:319), Execution context: Android background service, Execution context: CLI (tylog), _index/index.json (vault index) (+13 more)

### Community 2 - "Conflict Incident Scope"
Cohesion: 0.15
Nodes (14): 3: drain junk gate misses redirect/404 pages, Findings from the 0.3.0+93 device rollout — scope of work, A24 incident: 695 articles behind for four hours, lib/app_mobile.dart:2130 (conflict dialog), article-pipeline drain (rewrites articles/*.typ continuously), Sync conflict recovery — scope of work, Correction: the claimed sync_conflicts fixtures never existed, Vault-wide conflict gate ('Sync is paused until you review the conflicts') (+6 more)

### Community 3 - "Sync Cost Measurement"
Cohesion: 0.15
Nodes (13): A guaranteed-405 MKCOL per run, Two planned optimisations retired by measurement, SafBridge recursive listing (one ContentResolver.query per directory), scan-local (86% of a shortcut pass), Proposed: share one directory listing between sync and the scan that follows, Sync stage timings measured on the P30 (18.1 s no-transfer pass), The local tree was walked twice per pass, Phase 3a: a resolve announces itself and reports on the remote write (+5 more)

### Community 4 - "Conflict Auto-Resolution Rules"
Cohesion: 0.21
Nodes (12): lib/nextcloud_sync/auto_resolve.dart, lib/nextcloud_sync/conflicts.dart, import_sha256 (producer contract field), Phase 2: auto-resolve the provably-lossless cases, Rule 2: fast-forward (one side a strict superset), Rule 1: identical content, different ETag/mtime, Rule 3 (dropped): pipeline-authoritative articles, spec/tylog-format-v1.md (producer contract) (+4 more)

### Community 5 - "Resolve Path and ETag Guard"
Cohesion: 0.24
Nodes (12): ETag guard: StateError('Nextcloud changed again'), Phase 3b: rewrite a deleted-remote conflict to the delete-vs-changed shape, Phase 3c: on ETag mismatch refresh and re-decide instead of throwing, _refreshConflictRemote (lib/nextcloud_sync/conflicts.dart:94), resolveConflict (lib/nextcloud_sync.dart:771), lib/workspace_controller.dart:951 (workspace.resolveConflict), .tylog/conflicts/*.json (conflict record), P0-1: 'Keep Nextcloud's version' could delete the file it claimed to keep (+4 more)

### Community 6 - "Silent Failures and Bulk Resolve"
Cohesion: 0.38
Nodes (7): 1d: donor reuse fails silently, Phase 4: never fail invisibly; resolve in bulk, Resolve all (bulk conflict resolution), syncError banner losing its slot to the 'Syncing…' card, Capability: donor publish, P0-4: bulk resolve reported 'Resolved N' over an untouched vault, P2-14: IndexDonorStore.publish swallowed every failure

### Community 7 - "Typst Inspection and Fallback"
Cohesion: 0.40
Nodes (6): 2: notes referencing not-yet-synced assets fall back unnecessarily, Image placeholder pre-seeded into the VFS, Fallback source parser (fallback-inspected notes), Hardware verification on P30 and A24 after the 0.4.x batch, Open: fallback-inspected notes are never retried on unchanged bytes, Capability: Typst inspector

### Community 8 - "Sync State Format"
Cohesion: 0.40
Nodes (6): Not a bug: absent schema/remoteKey in sync_state.json read as current, remoteKey, rootEtag, SyncCursor, .tylog/sync_state.json, sync_state schema field

## Ambiguous Edges - Review These
- `Failure shape 2: 'absent' read as 'current'` → `P0-3: self-heal compared two frozen snapshots and deleted live conflicts`  [AMBIGUOUS]
  2026-08-22-audit-findings.md · relation: conceptually_related_to

## Knowledge Gaps
- **16 isolated node(s):** `Capability: search-index write guard (derivation stamp)`, `Capability: VaultLock`, `sync_state schema field`, `remoteKey`, `rootEtag` (+11 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **2 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **What is the exact relationship between `Failure shape 2: 'absent' read as 'current'` and `P0-3: self-heal compared two frozen snapshots and deleted live conflicts`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._
- **Why does `Donor reuse (inherit facts instead of recompiling)` connect `Donor Sharing and Schema Gating` to `Sync Cost Measurement`, `Conflict Auto-Resolution Rules`, `Silent Failures and Bulk Resolve`?**
  _High betweenness centrality (0.177) - this node is a cross-community bridge._
- **Why does `Failure shape 1: a fix applied to some of N equivalent paths` connect `Execution Contexts and CLI` to `Donor Sharing and Schema Gating`?**
  _High betweenness centrality (0.151) - this node is a cross-community bridge._
- **Why does `P0-3: self-heal compared two frozen snapshots and deleted live conflicts` connect `Resolve Path and ETag Guard` to `Donor Sharing and Schema Gating`, `Conflict Auto-Resolution Rules`?**
  _High betweenness centrality (0.140) - this node is a cross-community bridge._
- **Are the 3 inferred relationships involving `Donor reuse (inherit facts instead of recompiling)` (e.g. with `Shared index / 'hard computing on the laptop'` and `Proposed: share one directory listing between sync and the scan that follows`) actually correct?**
  _`Donor reuse (inherit facts instead of recompiling)` has 3 INFERRED edges - model-reasoned connections that need verification._
- **Are the 2 inferred relationships involving `Phase 2: auto-resolve the provably-lossless cases` (e.g. with `Conflict auto-resolution (fast-forward and identical-content rules)` and `Conflict self-heal`) actually correct?**
  _`Phase 2: auto-resolve the provably-lossless cases` has 2 INFERRED edges - model-reasoned connections that need verification._
- **What connects `Capability: search-index write guard (derivation stamp)`, `Capability: VaultLock`, `sync_state schema field` to the rest of the system?**
  _16 weakly-connected nodes found - possible documentation gaps or missing edges._