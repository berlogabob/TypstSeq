# TyLog rules compliance audit — 2026-10-08

What this repo does: TyLog edits local Typst research notes and syncs ordinary vault files through Nextcloud. It also keeps private SQLite projections, revisions, PDF annotations and search data. Assumed load: one user, several devices, thousands of notes, and large attachments.

This is a source audit, not a fresh runtime acceptance run. Only this report was written. No tests, builds, phones, adb, network requests or external vault reads were performed. Test enforcement below means an existing test asserts the rule; it does not mean that test was run today. “Followed but untested” means the inspected implementation follows the rule but no focused automated assertion was found. It does not mean a demonstrated bug. Findings distinguish code violations, test gaps and stale documentation.

Navigation started with `graphify query "engineering product rules sync tasks writers startup indexing tests"`, then a task/sync query and `graphify explain "Typst Compile-Validation Rule"`. Source confirmed every reported finding. Graph results were truncated; they were used only as navigation. `graphify-out/wiki/index.md` and `FIXLOG.md` are absent. No graph rebuild was performed. `graphify-out/GRAPH_REPORT.md` was already dirty when repository status was checked and was left alone.

Sources inventoried: AGENTS.md, CONTEXT.md, PLAN.md, README.md, USER_MANUAL.md, spec/, docs/ plans/audits/research/evidence, .claude/skills/, and all Markdown memory notes in the requested directory. Normative statements were extracted across that inventory, then deduplicated into the catalog below. Competitor descriptions, historical diagnoses, proposed fixes and waived/deferred features were not treated as current app requirements. Historical evidence does not prove a current test gap closed. External article-pipeline implementations, host configuration and production installations cannot be confirmed within this scope; their operator rules are identified without claiming their external implementation is compliant.

Source abbreviations: **S** = `spec/tylog-format-v1.md`; **T** = `docs/plans/2026-10-08-tasks-redesign.md`; **P** = `docs/plans/tylog-plus/plan.md`; **U** = `docs/ui-fix-plan.md`; **E** = `docs/tylog-ecosystem.md`; **M/** = `/Users/berloga/.claude/projects/-Users-berloga-Documents-GitHub-TypstSeq/memory/`. All `file:line` references identify inspected source. Numbered findings use F1–F23.

## Numbered rule catalog

| # | Adopted rule | Rule source | Status and enforcement/evidence |
|---|---|---|---|
| 1 | Task field edits preserve every unrelated byte and unknown field. | M/tylog-taskline-redesign.md:15; T:32 | **Violated** — `lib/app_mobile.dart:2003` clears fields other than the selected chip. F1. Core itself is tested by `task_fields_test.dart`, “set ${entry.key} preserves every other byte”. |
| 2 | Never rebuild an existing task call from a reduced model. | M/tylog-taskline-redesign.md:15 | **Enforced by test** — `packages/tylog_core/test/scanner_task_mutation_test.dart:185`, “replaces only the text field on a full-fat task fixture”. |
| 3 | Writers must compile emitted Typst, not merely parse it back. | `docs/superpowers/plans/2026-08-20-logseq-db-import.md:20`; M/tylog-writers-must-compile.md | **Enforced by test** — `integration_test/pkms_native_test.dart:16`, “native v5 metadata query and report PDF export”, compiles actual generated output at :112; cited output is compiled at `integration_test/p23_research_workflow_native_test.dart:253`. Core task/image writer tests also compile. |
| 4 | Missing or duplicate task IDs cause refusal rather than an arbitrary edit. | T:32; M/tylog-taskline-redesign.md:15 | **Enforced by test** — `packages/tylog_core/test/task_fields_test.dart`, “${writer.key} rejects duplicate id like existing writers” and “rejects unknown id”. |
| 5 | Only full-line pure deletions may remove a task during cross-block text editing. | M/tylog-taskline-redesign.md:16 | **Enforced by test** — `test/rich_editor_test.dart:1693`, “pasting a blank-line paste at the exact end of a task line is refused”; implementation `lib/rich_editor/document_model.dart:459`. Rich-clipboard guard parity is not established by this result; see rule 6. |
| 6 | Rich clipboard paste must retain task/protected-node safety. | M/tylog-taskline-redesign.md:18 (recorded gap); `docs/audits/2026-09-06/tasks.md:127` | **Followed but untested** for the distinct rich-paste path — `lib/rich_editor/editing_controller.dart:1124` calls `_replaceWithParts`, whose start-block protection is at `lib/rich_editor/document_model.dart:1292`. Full task-boundary parity is untested. F9. No data-loss claim is made. |
| 7 | Malformed task calls remain protected source. | M/tylog-taskline-redesign.md:17 | **Enforced by test** — `test/rich_editor_test.dart:1607`, “a structurally malformed task stays a protected chip”. |
| 8 | Todo, Doing, Done and Cancelled remain the four statuses. | S:64; T:27 | **Enforced by test** — `test/task_typing_test.dart:890`, “long press checkbox opens four statuses on the line”. |
| 9 | Priorities remain low, normal, high and urgent. | S:64; `USER_MANUAL.md:73` | **Enforced by test** — `test/task_typing_test.dart:745`, “/$command applies through the existing popup”; validation vocabulary at `packages/tylog_core/lib/src/validation.dart:58`. |
| 10 | Unknown task statuses/priorities are validation errors. | S:65 | **Followed but untested** as a focused validator assertion — `packages/tylog_core/lib/src/validation.dart:149` and :159; current validator fixture covers IDs/text/paths instead (`test/pkms_registry_test.dart:9`). F10. |
| 11 | Every status transition uses applyTaskStatus. | T:34; M/tylog-taskline-redesign.md:21 | **Enforced by test** — `test/widget_test.dart:272`, “list checkbox uses repeat completion and stops the Doing clock”; editor calls it at `lib/rich_editor/editing_controller.dart:1007`. |
| 12 | Doing starts a clock; leaving Doing stops it. | T:26; `USER_MANUAL.md:75` | **Enforced by test** — `packages/tylog_core/test/task_fields_test.dart`, “todo to doing opens a clock”, “doing to $next closes the running clock”. |
| 13 | One running task per vault; starting another demotes the old task to Todo. | T:36 | **Enforced by test** — `test/widget_test.dart:235`, “Doing in the editor stops a running task in another vault note”; same-note core case in `task_fields_test.dart`. |
| 14 | A repeating task completion records an occurrence and remains active. | T:35; `USER_MANUAL.md:71` | **Enforced by test** — `test/task_typing_test.dart:1015`, “editor toggle records repeat occurrence”; list regression at `test/widget_test.dart:272`. |
| 15 | Stop on the running pill returns the task to Todo. | T:71; `USER_MANUAL.md:75` | **Enforced by test** — `test/widget_test.dart:326`, “task clock stop closes the session and the row shows its total”. |
| 16 | Clock sessions live in properties.clocked; open ends are none. | S:33 | **Enforced by test** — `packages/tylog_core/test/writer_compiles_test.dart`, “UTC clock writers preserve Cyrillic and unmodeled fields byte-exactly and compile”. |
| 17 | Clock edits retain other properties, collapse exact duplicates, and accept legacy top-level clocked. | S:46 | **Enforced by test** — `packages/tylog_core/test/scanner_task_mutation_test.dart:372` and clocked group at :371. |
| 18 | Short misfires/runaways do not silently inflate tracked totals. | M/tylog-taskline-redesign.md; `docs/research-tylog-features.md:46` | **Enforced by test** — `test/widget_test.dart:500`, “task clock misfire stop removes the session and Undo restores it without losing edits”; runaway cases at :520. |
| 19 | TODO, [] and [ ] at line start and /todo create typed tasks. | `USER_MANUAL.md:69`; T:48 | **Enforced by test** — `test/task_typing_test.dart:72` trigger matrix and :745 command matrix. |
| 20 | Enter continues tasks; empty Enter exits to plain text. | T:49 | **Enforced by test** — `test/task_typing_test.dart:705`, “Enter continues tasks and empty Enter exits”. |
| 21 | Backspace demotion is one undo restoring all metadata. | T:50; `USER_MANUAL.md:69` | **Enforced by test** — `test/task_typing_test.dart:716`, “demote then undo restores full task metadata in one step”. |
| 22 | Task IDs are fresh, including help-chip and unsaved insertions. | T:78 | **Enforced by test** — `test/widget_test.dart:170`, “Typst help Task chip allocates unique IDs across unsaved insertions”; `test/vault_test.dart:883`, “nextTaskId avoids reserved ids”. |
| 23 | Typed dates support English, Russian, Portuguese and optional times with picker fallback. | T:43; `USER_MANUAL.md:73` | **Enforced by test** — `packages/tylog_core/test/date_words_test.dart`; `test/task_typing_test.dart:809`, “date popup parses $words live”; :945 calendar fallback. |
| 24 | Ctrl/Cmd+Enter cycles Todo → Doing → Done → Todo. | `USER_MANUAL.md:71` | **Enforced by test** — `test/task_typing_test.dart:865`, “Ctrl and Cmd Enter cycle task status”. |
| 25 | Four glyphs and chip strips live outside editable text. | T:64; T:65 | **Enforced by test** — `test/task_typing_test.dart:515`, “all status glyphs edit, demote, undo, round-trip and compile”; :538 chip popup case. |
| 26 | Metadata-only changes refresh the open task line. | T:66 | **Enforced by test** — `test/widget_test.dart:201`, “metadata-only external change updates the open task line”. |
| 27 | Today, Tasks, Journal, Calendar, Search and saved queries use TaskRow. | T:69; `USER_MANUAL.md:77` | **Enforced by test** — `test/task_row_test.dart`, “$surface renders TaskRow and forwards status and fields”. This tests callback forwarding, not the app's destructive field handler (F1). |
| 28 | Row text opens a note; only checkbox/status menu changes status. | U:42 | **Enforced by test** — `test/task_row_test.dart`; implementation `lib/widgets/task_row.dart:91`. |
| 29 | All task filter includes cancelled and old completed tasks. | T:72 | **Enforced by test** — `test/task_agenda_test.dart:48`, “All includes cancelled and older or untimestamped done; Open and Done stay unchanged”. |
| 30 | Quick add takes text literally; date parsing is deferred. | T:8; `CONTEXT.md:21` | **Obsolete or contradicted by a later rule** — original parsing proposal at T:73 is superseded by outcome at T:8. No parsing feature is required. |
| 31 | Session-history UI, imported checklist conversion and additional statuses stay deferred. | T:80; `CONTEXT.md:21` | **Obsolete or contradicted by a later rule** — treated as explicit non-goals, not missing implementations. |
| 32 | Stable nonempty IDs are retained across tools and edits. | S:11 | **Enforced by test** — `test/database/portable_roundtrip_test.dart:176`, “divergent stable ID reports conflict and changes nothing”; ID validation at `test/pkms_registry_test.dart:9`. |
| 33 | Paths stay vault-relative, slash-separated, without traversal. | S:13; E:63 | **Violated** — the validation helper accepts internal backslashes (`packages/tylog_core/lib/src/validation.dart:213`) that storage rejects (`packages/tylog_core/lib/src/storage.dart:185`), and app attachment records contain a leading slash. F7. Storage traversal itself is tested (`packages/tylog_core/test/core_test.dart:501`). |
| 34 | V1 records have schema=1 and matching entity; invalid envelopes are invalid. | S:20; S:69 | **Violated** — `packages/tylog_core/lib/src/scanner.dart:304` silently drops them with no validation problem. F3. |
| 35 | Required metadata fields cannot be silently substituted. | S:25; S:69 | **Violated** — `packages/tylog_core/lib/src/scanner.dart:2116`, :2391 and :2158 substitute title/status/priority/kind. F4. |
| 36 | Date values are ISO calendar dates/date-times. | S:68 | **Violated** as validation — `packages/tylog_core/lib/src/validation.dart:127` checks no task date fields. F5. |
| 37 | Unknown custom properties survive supported readers and edits. | S:15 | **Violated** on task fallback — `packages/tylog_core/lib/src/scanner.dart:2412` omits task properties. F6. Note fallback is tested (`packages/tylog_core/test/core_test.dart:58`). |
| 38 | Standard kinds include note/daily/project/article/research; nonempty extension kinds warn. | S:51 | **Followed but untested** for focused extension-kind validation — `packages/tylog_core/lib/src/validation.dart:81`. F10. |
| 39 | import_format, import_source_name and import_sha256 keep their reserved meanings. | S:56 | **Enforced by test** — `packages/tylog_core/test/dedupe_test.dart` imported identity cases; portable import tests retain attributes. |
| 40 | Legacy generation-5 metadata remains readable; existing source is not upgraded merely for metadata. | S:74; S:76 | **Enforced by test** — `packages/tylog_core/test/core_test.dart:8`, “Format v1 and legacy records decode to the same values”; `test/vault_test.dart:195`, “exact legacy helper upgrades without rewriting notes”. |
| 41 | Query metadata once per document, filtering the six stable labels. | S:80; E:29 | **Enforced by test** — `packages/tylog_core/test/core_test.dart:31`, “scanVaultStorage queries once and matches fallback index content”. |
| 42 | Compile failure warns and preserves fallback links/tasks. | S:82 | **Enforced by test** — `packages/tylog_core/test/core_test.dart:80`, “inspector failure warns and retains fallback backlinks”. Invalid envelopes on a successful query remain the separate gap F3. |
| 43 | note emits semantics/body; document owns global styles. | S:88 | **Enforced by test** — `test/preview_theme_test.dart:105` real Typst page-dimension cases; package contract at `packages/tylog_core/test/package_contract_test.dart:41`. |
| 44 | Canonical task text is a plain string. | S:92 | **Enforced by test** — `packages/tylog_core/test/package_contract_test.dart:41`, “every field TyLog writes is declared by the Typst package”; writer compilation cases. |
| 45 | V5 vault roots and /_system/tylog.typ import remain compatible. | `README.md:79`; S:9 | **Enforced by test** — `test/vault_test.dart:164`, “empty folder becomes a complete v5 vault”; :195 helper upgrade. |
| 46 | Pre-v5 or unmarked nonempty folders are refused without mutation. | `USER_MANUAL.md:24` | **Enforced by test** — `test/vault_test.dart:242`, “missing vault marker is rejected without mutation”; :255 old-vault case. |
| 47 | Managed helper/package updates do not overwrite customized helpers/themes. | E:35; `README.md:37` | **Enforced by test** — `test/vault_test.dart:220`, “custom helper and theme are preserved; package is repaired”; `test/preview_theme_test.dart:14`. |
| 48 | Vendored Typst package is pinned and works offline; registry publication is deferred. | E:36; E:53 | **Enforced by test** — `packages/tylog_core/test/package_release_machinery_test.dart:128`, “typst.toml, helper marker and helper import agree”. |
| 49 | Core remains Flutter-independent; file picking stays in app; Rust handles conversion. | E:57 | **Followed but untested** as a dependency-boundary assertion — imports in `packages/tylog_core/lib/src/scanner.dart:1`; Flutter adapter re-export at `lib/scanner.dart:1`. F11. |
| 50 | JSON is settings/state/diagnostics/derived indexes; notes remain Typst. | `README.md:3` | **Obsolete or contradicted by a later rule** — durable note/revision payloads now also appear in `_system/revisions/*.json` (`lib/database/revision_publisher.dart:90`). Document contradiction F14. |
| 51 | SQLite is absent/deferred. | `PLAN.md:26`; E:134 | **Obsolete or contradicted by a later rule** — P:33 adopts Drift/SQLite, implemented at `lib/database/tylog_database.dart:1287`. F14. |
| 52 | SQLite is the one authoritative store and edits are atomically file/database durable. | P:33; P:34 | **Obsolete or contradicted by a later rule** for file authority — `USER_MANUAL.md:116`, :120 and `lib/workspace_controller.dart:1101` now retain files after projection failure. The original “one authoritative store” promise needs explicit retirement. F14. |
| 53 | Database edit transaction includes revision, outbox and invalidation. | P:34 | **Enforced by test** — `test/database/tylog_atomic_edit_test.dart:21`, “edit commits content, revision, outbox, and invalidation”; :39 rollback. This does not make the preceding filesystem write part of that transaction. |
| 54 | Save/index/database errors keep the authoritative local text and remain visible. | `USER_MANUAL.md:120`; `docs/audits/2026-09-06/tasks.md:127` | **Enforced by test** — `test/workspace_controller_test.dart:1562`, “first save database failure preserves new note bytes and retry markers”; :1516 existing-note case. |
| 55 | Database enables WAL/foreign keys, uses worker connection and versioned migrations. | P:33 | **Enforced by test** — `test/database/tylog_database_test.dart:52`, “WAL pragma enabled on fresh creation”; :65 foreign keys; :92 migration. Worker setup source `lib/database/tylog_database.dart:1287`; lifecycle tests cover closure. |
| 56 | Published revisions/conflict bases are immutable; unpublished local drafts may coalesce within fixed 60-second windows. | `PLAN.md:46`; `CONTEXT.md:38` | **Enforced by test** — `test/database/revision_coalescing_test.dart:119`, “a head referenced by another revision is never replaced”; :134 received-head case; `test/database/tylog_atomic_edit_test.dart:82`, immutable revisions. |
| 57 | Sync uses separate v2 namespace, immutable batches/sequence/device head and transactional cursor. | P:36 | **Obsolete or contradicted by a later rule** — current sync reuses file transport with `_system/revisions/$envelopeId.json` (`lib/database/revision_publisher.dart:90`). Current file-sync docs supersede parts of the plan but do not explain the change. F15. |
| 58 | Concurrency is resolved by ancestry, never wall-clock winner selection. | P:36; `CONTEXT.md:38` | **Enforced by test** — `test/nextcloud_sync_test.dart:903`, “diverged, invalid and cyclic ancestry requires review”; :881/:892 ancestry directions. |
| 59 | Outbox remains pending until upload acknowledgment. | P:34; P:36 | **Enforced by test** — `test/database/revision_outbox_test.dart:7`, “revision upload stays pending until acknowledged”. |
| 60 | FTS uses unicode61/remove_diacritics=2 and refreshes changed records only. | P:35 | **Enforced by test** — `test/database/node_search_fts_test.dart`; tokenizer source `lib/database/tylog_database.dart:1125`. |
| 61 | Lists use bounded keyset pages of 50. | P:34 | **Enforced by test** — `test/database/node_summary_page_test.dart:52`, “summary page rejects unbounded limits”; paging cases at :6. |
| 62 | Jobs deduplicate by revision, resume/cancel and reject stale results. | P:35 | **Enforced by test** — `test/database/tylog_import_schema_test.dart`; `test/retrieval_embedding_jobs_test.dart:12`, “bounded embedding batches resume after a failed item”. |
| 63 | Import/export preserves stable IDs, raw Typst, properties, attachments and conflicts; repeat import is a no-op. | P:34; P:59 | **Enforced by test** — `test/database/portable_roundtrip_test.dart:22`, :99, :176 and :218; `test/database/portable_merge_test.dart`. |
| 64 | Migration retains original/verified backup; recovery cannot reopen stale data over newer edits. | P:37; `USER_MANUAL.md:106` | **Enforced by test** — `test/import/legacy_import_runner_test.dart`; `test/vault_registry_test.dart` verified migration and retained-backup cases. Real-production acceptance is not rerun here. |
| 65 | Never read Logseq db.sqlite/kvs directly; EDN export only. | `docs/superpowers/plans/2026-08-20-logseq-db-import.md:17` | **Obsolete or contradicted by a later rule** as a required feature — this is a planned importer extension, not proof it shipped. Current folder importer tests (`test/import/legacy_import_plan_test.dart`) do not establish EDN delivery. No requirement to add it in this audit. |
| 66 | Logseq/Obsidian input converts to Typst; assets copy; unresolved links are reported. | `USER_MANUAL.md:87`; E:66 | **Enforced by test** — `test/import/legacy_import_runner_test.dart`; `test/vault_import_policy_test.dart`; native conversion exercised by `integration_test/markdown_import_native_test.dart`. |
| 67 | PDFs retain source/version identity and stable annotation anchors. | P:38 | **Enforced by test** — `test/pdf_reader_store_test.dart:55`, “changed bytes retain old version and selection offsets”; :8 source/version identity. |
| 68 | Ambiguous annotation reattachment requires review. | P:38 | **Enforced by test** — `test/pdf_annotation_reattach_test.dart`; native route `integration_test/pdf_reader_review_native_test.dart`. |
| 69 | Password-required/unsupported PDFs fail recoverably; image-only PDFs remain viewable and unsearchable. | P:135 | **Enforced by test** — `test/pdf_extraction_test.dart`; `integration_test/private_pdf_corpus_test.dart`. OCR remains deferred. |
| 70 | Semantic model/tokenizer/dimension/chunker are versioned; normalized vectors and bounded exact search run offline after installation. | P:39 | **Enforced by test** — `test/semantic_model_test.dart:49`, “downloads and verifies the pinned files”; `test/retrieval_cosine_test.dart`; `test/retrieval_native_embedding_test.dart`. |
| 71 | Model download is explicit and corrupt/partial installs are refused. | `docs/plans/tylog-plus/evidence/P21/result.md:93` | **Enforced by test** — `test/semantic_model_test.dart:57`, “sha mismatch leaves no install or part files”; :65 cancellation; :80 required marker. UI confirmation `lib/app_mobile.dart:4214`. |
| 72 | Hybrid FTS/vector hits map to stable entities/source offsets; generated answers are out of scope. | P:39 | **Enforced by test** — `test/semantic_search_controller_test.dart:45`, “indexes notes and maps vector hits to their paths”; `test/widget_test.dart:2628` hybrid ordering. |
| 73 | AI/RAG is wholly absent. | `PLAN.md:26`; `USER_MANUAL.md:126` | **Obsolete or contradicted by a later rule** — offline semantic retrieval ships (`lib/app_mobile.dart:4217`), while generated answers remain excluded (P:39). F16. |
| 74 | Interactive graph caps at 200 nodes and 500 edges; exports SVG; traversal is bounded. | P:40 | **Enforced by test** — `test/graph_test.dart:7`, “boundGraphForLayout caps nodes and edges deterministically”; :559 export; `test/database/bounded_neighborhood_test.dart`. |
| 75 | Startup/open/save/search/frame/memory gates use normal profile/release, measured corpus and actual hardware. | P:50; P:51; P:52; P:54; P:55; P:56 | **Enforced by test** — `integration_test/p12_latency_native_test.dart`, `integration_test/p12_editor_frame_native_test.dart`, `integration_test/p05_exact_search_profile_test.dart`, `integration_test/p22_graph_latency_native_test.dart`; hardware evidence is historical, not refreshed. Gates: ready ≤2 s p95; ≤50 KB open/save ≤150 ms; keyword first 50 ≤200 ms; semantic warm ≤3 s/cold ≤6 s; graph ≤500 ms; <1% over-budget frames; Android ordinary/heavy PSS ≤350/750 MB. |
| 76 | Idle has zero rebuild/content upload/repeated processing notifications; cancel ≤250 ms and starts no later batch. | P:57 | **Enforced by test** for components — `test/workspace_controller_test.dart:1020`, “a scan that changes nothing does not rewrite the search index”; `test/nextcloud_sync_test.dart:1691` no-change requests; job cancellation tests. Ten-minute production acceptance is a separate historical device gate. |
| 77 | Sync converges after duplicates/reordering/interruption; controlled edit arrives ≤10 s p95. | P:58 | **Enforced by test** for convergence — `test/nextcloud_sync_test.dart:199`, “three devices converge without losing written content”; `test/real_account/p24_rehearsal_real_test.dart`. The latency target requires real-account evidence; no new latency result here. |
| 78 | Import/extraction/embedding throughput are measured separately; synthetic chunks cannot substitute for extraction. | P:60 | **Followed but untested** as evidence discipline — separate native harnesses in `integration_test/private_pdf_corpus_test.dart` and `integration_test/p05_embedding_profile_test.dart`. F22. |
| 79 | DONE requires all acceptance evidence; host and device completion are separate; WAIVED is explicit. | P:6; P:27; `docs/audits/2026-09-06/plan.md:81` | **Followed but untested** — P:79 leaves P12 open; P:88 marks P21 waived. F22. |
| 80 | P26 seven-day use starts only after required gates, including P12. | P:6; P:94 | **Followed but untested** — tracker P:94 leaves P26 TODO. F22. |
| 81 | Original retrieval-quality label/Recall gates are waived. | P:53 | **Obsolete or contradicted by a later rule** — waiver 2026-10-06 supersedes earlier P05/P21 acceptance, not a code violation. |
| 82 | No transient UI status may reflow content; use overlays; reserving docks animate. | M/tylog-ui-no-layout-shift.md:11 | **Followed but untested** for shell/graph geometry — `lib/app_mobile.dart:4959` status overlay, `lib/graph.dart:384`, `lib/rich_editor/editor_widgets.dart:1299`; task-strip timing is tested at `test/task_typing_test.dart:623`. F12. |
| 83 | Shared design tokens own brand, palette, radius and kind icons. | U:70; U:91 | **Enforced by test** — `test/design_tokens_test.dart:41`, :54, :69, :87. |
| 84 | Warnings and graph edges have ≥3:1 contrast in both themes. | U:103 | **Enforced by test** — `test/contrast_test.dart:50`, :63, :73. |
| 85 | Property/task chips have at least 48 dp tap targets. | U:107 | **Enforced by test** — `test/property_select_chip_test.dart:21`; task constraints `lib/widgets/task_chip_strip.dart:85`. |
| 86 | Voronoi exposes visible cells with actionable accessibility semantics. | U:114 | **Enforced by test** — `test/voronoi_view_test.dart:69`, “exposes visible cells as semantics nodes”. |
| 87 | Article delete and highlights have tap-only routes; rating shows five stars and explicit discard. | U:47; U:61; U:125 | **Enforced by test** — `test/articles_shelf_test.dart`; `test/widget_test.dart:2192`, “Magic menu exposes the complete command set”; native control sweep remains separate. |
| 88 | Today is capture-first: idle editor ≥80%; populated agenda bounded. | U:133; `docs/ui-fix-status.md:27` | **Enforced by test** — `test/today_page_test.dart:299`, “with nothing due the editor gets the whole page”; :323 bounded agenda. |
| 89 | Journal shows existing pages only; each day's events start collapsed. | `USER_MANUAL.md:59` | **Enforced by test** — `test/journal_feed_test.dart:160`, “journal lists only real pages; a day's events stay collapsed”. |
| 90 | Standalone images use ordinary Typst width/alignment, default 60% center; old inline images stay unchanged until edited. | S:97; `USER_MANUAL.md:81` | **Enforced by test** — `test/image_block_test.dart:182`, “written $align image compiles with the real Typst engine and tylog package”; other block/preservation cases in that file. |
| 91 | Crop writes a hashed sibling PNG, retains original, and refuses a mismatched existing crop path. | S:112; `USER_MANUAL.md:83` | **Enforced by test** — `test/image_crop_test.dart` save/collision tests at :261, :302, :329, :376. |
| 92 | Preview is continuous/refits; PDF uses selected A4/Letter/A5/Legal; customized theme stays intact. | `README.md:32`; `README.md:35` | **Enforced by test** — `test/preview_theme_test.dart:14`, :38, :49, :105, :154. |
| 93 | Reports are reproducible Typst with sibling PDFs; no new export format. | `USER_MANUAL.md:100` | **Enforced by test** for determinism/filtering — `test/report_test.dart:66`, “report source is ordinary deterministic Typst”. Generated reports are compiled in `integration_test/pkms_native_test.dart:112` and `integration_test/p23_research_workflow_native_test.dart:253`. |
| 94 | Failed saves, delayed reads and vault switches cannot silently replace newer edits. | `docs/audits/2026-09-06/tasks.md:127`; `USER_MANUAL.md:120` | **Enforced by test** — `test/workspace_controller_test.dart:1809`, “a note read requested before an edit cannot replace even a saved edit”; `test/widget_test.dart:1438` failed-save navigation. |
| 95 | Dirty-note mutations use serialized shared persistence; routine refresh coalesces, never cancels scans. | `docs/audits/2026-09-06/evidence/T16/result.md:9` | **Enforced by test** — `test/workspace_controller_test.dart:314`, “mutateNote serializes delayed closed-note read-modify-write”; :3338 rating/deletion follow-up. |
| 96 | Bulk rewrites and headerless daily repair snapshot before replacing; keep existing text. | S:124; `USER_MANUAL.md:118` | **Enforced by test** — `test/empty_note_cleanup_test.dart:45`, “failed daily snapshot leaves the original capture untouched”; `test/workspace_controller_test.dart:1214` SAF repair undo; `test/vault_test.dart:445` snapshot failure. |
| 97 | Local saves finish before sync transfers. | `USER_MANUAL.md:108` | **Enforced by test** — `test/nextcloud_sync_test.dart:4344`, “autosave landing between hash and upload stays consistent”; controller guard `lib/workspace_controller.dart:1743`. |
| 98 | Undo copy precedes replacing/deleting unconfirmed local bytes; exclude system/revisions; prune only sync-* after 30 days. | S:118 | **Enforced by test** — `test/nextcloud_sync_test.dart:1430`, :1491, :1619, :1634, :1661. |
| 99 | Sync includes durable v5 roots; excludes .tylog, _index, temp/conflict files and database files. | `USER_MANUAL.md:108`; P:36 | **Enforced by test** — `test/nextcloud_sync_test.dart:3299`, “sync excludes operational state and keeps durable v5 roots”; :771 OS junk. |
| 100 | Compare sync paths by NFC; retain real local spelling; reject equal-NFC collisions. | M/tylog-sync-nfd-names.md; `docs/plans/tylog-plus/evidence/P24/result.md:73` | **Enforced by test** — `test/nextcloud_sync_test.dart:5551`, “NFD local path and NFC remote path are unchanged”; :2050 collision rejection; :497 conflicts. |
| 101 | Confirmed cursor-tracked remote deletion deletes locally; do not resurrect; unconfirmed/untracked upload may retry. | M/tylog-sync-deletion-resurrection.md; `USER_MANUAL.md:110` | **Enforced by test** — `test/nextcloud_sync_test.dart:3968`, “a remote deletion of an unchanged file is honored, not resurrected”; :4417 tracked/untracked distinction. “Remote-missing never re-uploads” without this distinction is not the current rule. |
| 102 | Empty/partial/mass listings cannot wipe a vault. | `USER_MANUAL.md:110`; `docs/2026-08-21-backlog-flood-report.md:66` | **Enforced by test** — `test/nextcloud_sync_test.dart:3803` invalid HTML; :4015 mass remote wipe; :4287 empty local listing; :2309 partial scan. |
| 103 | Uploads become confirmed only after server listing; incomplete folder responses are refused/fall back. | `USER_MANUAL.md:110` | **Enforced by test** — `test/nextcloud_sync_test.dart:1582`, “listed PUT ETags confirm uploads without GETs”; :2142 Depth fallback. |
| 104 | Retain 32 local hash receipts without age expiry; own upload/local ancestry does not create conflicts. | S:128 | **Enforced by test** — `test/vault_test.dart:13`, :54, :83; `test/nextcloud_sync_test.dart:21`, :168, :148. |
| 105 | Pending conflicts gate only their paths, not unrelated sync. | `docs/superpowers/plans/2026-08-21-sync-conflict-recovery.md:9` | **Enforced by test** — `test/nextcloud_sync_test.dart:5007`; `test/workspace_controller_test.dart:3170`. Blanket gate in M/tylog-sync-conflict-gate.md is **obsolete or contradicted by a later rule**. |
| 106 | Conflict snapshots keep both sides; resolution rechecks changed remote and preserves newer local edits. | `USER_MANUAL.md:112` | **Enforced by test** — `test/nextcloud_sync_test.dart:3535`, :4538, :4572, :5091, :5104. A changed ETag with identical bytes may proceed after re-decision. |
| 107 | Dangerous conflict choices are not preselected; errors and per-row progress remain visible. | `docs/superpowers/plans/2026-08-21-sync-conflict-recovery.md:14`; :15 | **Enforced by test** — `test/conflict_choice_test.dart`; `test/sync_dashboard_test.dart`; controller notification case `test/workspace_controller_test.dart:2195`. |
| 108 | Append-only differences may resolve automatically; genuine two-sided edits require review. | `docs/superpowers/plans/2026-08-21-sync-conflict-recovery.md:10` | **Enforced by test** — `test/nextcloud_sync_test.dart:4760`, :4772, :4785. “No automatic conflict merging” at `USER_MANUAL.md:126` is stale. F17. Import-hash-based ownership proposal at the old plan's :97 is explicitly withdrawn at :10. |
| 109 | Polls back off after failure, pause rejected authentication, avoid rebuilds with no content change. | `docs/audits/2026-09-06/tasks.md:239` | **Enforced by test** — `test/workspace_controller_test.dart:3012`, :3086, :2593; `test/nextcloud_sync_test.dart:2367`. |
| 110 | Autosave full sync is throttled; background/manual/close paths are immediate; transient failures stay quiet briefly. | P:8; P:11 | **Enforced by test** — `test/workspace_controller_test.dart:2738`, “autosave throttle allows immediate manual and background sync”; :2657/:2699 error escalation. |
| 111 | Diagnostic log is bounded, complete within its bound and cannot block sync. | `USER_MANUAL.md:112`; `docs/2026-08-22-audit-findings.md:73` | **Enforced by test** — `test/nextcloud_sync_test.dart:4055`, “sync trace is bounded and never blocks synchronization”; dashboard tests. |
| 112 | Desktop-managed Nextcloud yields to desktop client. | `USER_MANUAL.md:104` | **Enforced by test** — `test/nextcloud_sync_test.dart:3323`, “embedded sync yields to a desktop-managed Nextcloud folder”. |
| 113 | Archive extraction frees decompressed content per entry without closing the shared input. | `docs/sync-memory-findings.md:71` | **Followed but untested** for retention — `lib/nextcloud_sync.dart:1566` uses `freeMemory: true`. Archive transfer tests do not assert retained memory. F13. |
| 114 | Indexing runs on worker isolate; search has its own reply channel and does not wait for scanning. | M/tylog-worker-isolate.md:11; :36 | **Enforced by test** — `test/vault_worker_test.dart:44`, “a rebuild round-trips through the worker isolate”; :191 search during rebuild; `test/workspace_controller_test.dart:543` root decode guard. |
| 115 | Worker teardown settles outstanding commands; stale-note signals travel with the scan. | M/tylog-worker-isolate.md:39; `docs/audits/2026-09-06/audit.md:50` | **Enforced by test** — `test/vault_worker_test.dart:216`, “disposing an active worker settles its unread command once”; stale/hash evidence is in `packages/tylog_core/test/hash_matches_parsed_bytes_test.dart`. |
| 116 | Hash corresponds to the exact parsed bytes; donor version/properties/synonyms must match. | `docs/2026-08-22-audit-findings.md:20`; M/tylog-article-pipeline-contract.md:34 | **Enforced by test** — `packages/tylog_core/test/hash_matches_parsed_bytes_test.dart`; `test/vault_test.dart:694`, :762, :792, :819. |
| 117 | Fallback inspection retries are bounded; one bad/hung note cannot poison the whole scan. | `docs/2026-08-22-audit-findings.md:61` | **Enforced by test** — `packages/tylog_core/test/core_test.dart:113`, :214, :344, :379. |
| 118 | Base support files cross once in bounded chunks; image placeholders must really compile. | M/tylog-basics-first-shipped.md:13 | **Enforced by test** — `packages/tylog_core/test/scanner_base_files_test.dart:90`, “base-aware inspector gets the file set once, empty maps per note”, plus `packages/tylog_core/test/scanner_base_files_test.dart:121`, “image placeholders compile under the typst CLI”; `integration_test/vfs_base_files_bench_test.dart`. |
| 119 | UI/service/resolve have one vault owner; lock deadline matches platform run budget. | M/tylog-background-service.md:21; `lib/vault_service.dart:28` | **Enforced by test** — `test/vault_lock_test.dart:10`, :33, :82, :113; `test/workspace_controller_test.dart:2056`, :2100, :2146. |
| 120 | Closed-app Android sync uses WorkManager, never starts FGS from background; schedule soon on pause, cancel on resume. | M/tylog-background-service.md:13; :17 | **Violated** — UI pause path still invokes a background-triggered FGS start (`lib/app_mobile.dart:2314`; `lib/workspace_controller.dart:1724`). F2. WorkManager itself is correctly separate (`android/app/src/main/kotlin/org/tylog/tylog/VaultSyncWorker.kt:25`). |
| 121 | Headless service must not ensureCreated/upgrade managed files; always signals completion and releases owner. | `lib/vault_service.dart:22`; M/tylog-background-service.md:13 | **Followed but untested** for complete headless run — `lib/vault_service.dart:42`, :59, :157. Lock unit tests do not invoke this entrypoint. F20. |
| 122 | WorkManager Room-generated classes survive release shrinking. | M/tylog-background-service.md:27 | **Followed but untested** as a release assertion — `android/app/proguard-rules.pro:4` keeps RoomDatabase subclasses. F20. |
| 123 | macOS close hides rather than destroying its window; iOS headless engine teardown is on main thread. | M/tylog-background-service.md:23; :32 | **Followed but untested** as app-platform lifecycle regression coverage — `macos/Runner/MainFlutterWindow.swift:20`; `ios/Runner/AppDelegate.swift:65`. F20. |
| 124 | macOS direct-distribution builds stay unsandboxed until bookmark support exists. | M/tylog-macos-no-sandbox.md:14 | **Followed but untested** — `macos/Runner/Release.entitlements:5` and `DebugProfile.entitlements:5` are false. F18. |
| 125 | Startup update checks/default database side effects are suppressed in Flutter tests. | M/tylog-flutter-test-rootbundle-wedge.md:15 | **Followed but untested** as an explicit no-side-effect regression — `lib/app_mobile.dart:483`, :552. Widget mounts exercise the guard but do not assert no update request was initiated. F19. |
| 126 | Profile is release-signed for in-place profiling; debug has separate app ID; test harness uses profiletest suffix. | `AGENTS.md:3`; M/tylog-profile-drive-uninstalls-prod.md; `docs/plans/tylog-plus/evidence/P03/result.md:23` | **Followed but untested** for signing/app-ID configuration — `android/app/build.gradle.kts:61`, :79, :83. Signing requires the release keystore to exist. F21. No keystore values were read. |
| 127 | CI builds local native source; never repair bridges by downloading upstream; rebuild after bridge generation. | M/tylog-ci-ships-native-from-source.md:29; `docs/superpowers/plans/2026-08-20-logseq-db-import.md:255` | **Enforced by test** for build guard — `test/release_config_test.dart:41`; `.github/workflows/release.yml:48`, :56. Final packaged-binary provenance is still untested by this guard (F23). |
| 128 | Native setup is explicit, not a build-time download; Android/macOS release, Linux compile, iOS development host. | `README.md:43`; `PLAN.md:15`; `USER_MANUAL.md:57` | **Enforced by test** for release target configuration — `test/release_config_test.dart:6`; release workflows. Signed iOS acceptance is not a current release requirement. |
| 129 | Jank uses real frame/root-isolate metrics and profile, not debug or HWUI decor counts. | M/tylog-worker-isolate.md:20; M/tylog-measure-profile-not-debug.md | **Obsolete or contradicted by a later rule** in part — `AGENTS.md:8` recommends dumpsys gfxinfo for frame timings, contradicting native Flutter metrics at `integration_test/support/editor_frame_metrics.dart`. F22. |
| 130 | Sample CPU and byte identity before diagnosing hangs/loss; inspect sync decisions first. | M/tylog-measure-before-diagnosing.md:26; M/tylog-headerless-daily.md:9 | **Followed but untested** as operator discipline; diagnostics exist in `lib/nextcloud_sync.dart:1643`. F22. No device diagnosis attempted here. |
| 131 | Existing article-pipeline auto-related marker, LLM-link preservation, gzip index and five read stages remain compatible. | M/tylog-article-pipeline-contract.md:24 | **Enforced by test** on app side — `test/relink_strip_test.dart`; `test/articles_shelf_test.dart:10`, “folds legacy and custom status values onto the five stages”; `test/vault_test.dart` index persistence. External producer parity is outside scope; publish the remaining operator contract (F22). |
| 132 | Private corpus/evidence cannot be logged to Git except explicitly redacted; benchmark logs omit source/query text. | P:25; `docs/plans/tylog-plus/evidence/P05/contract.md:73` | **Enforced by test** for tooling — `test/tool/test_tylog_corpus_manifest.py`; `test/tool/test_benchmark_exact_cosine.py`. Review discipline itself is followed but untested (F22); credentials and raw samples were not copied into this report. |
| 133 | One canonical plan, linked evidence, bounded non-overlapping workers; review diffs; coordinate integration checks. | P:3; P:187; `docs/audits/2026-09-06/plan.md:75` | **Followed but untested** as operator discipline. Later task plan explicitly retains historical instructions and outcomes (T:12). F22. This audit delegates no work. |
| 134 | Use existing mechanisms, smallest complete changes, measurement before architecture changes; model whole-app consumers. | M/berloga-improve-not-clone.md:11; M/berloga-system-level-planning.md:11 | **Followed but untested** as engineering discipline. T:30 applies one primitive across consumers. F22. No implementation changes here. |
| 135 | Runtime UI checks foreground the correct macOS window; wait for animation before tapping docks; never confuse mock and real-vault evidence. | `.claude/skills/verify/SKILL.md:21`; M/tylog-ui-no-layout-shift.md:18 | **Followed but untested** as operator discipline — `test/widget_test.dart:62` settles docks. The skill's claim that widget tests never open vaults is contradicted by `test/widget_test.dart:90`. F22. |
| 136 | Device checks preserve data: in-place install, isolated drive harness, cold keyboard replay, no suppressed adb errors. | M/tylog-device-loop-codex.md:9; M/adb-path-check.md:9; T:98 | **Followed but untested** as operator discipline. Current audit prohibits all device actions. M/tylog-taskline-redesign.md:19 discourages adb injection, superseded for A24 by M/tylog-device-loop-codex.md:9. F22. |
| 137 | Delegate mechanical work economically; review every output; Studio only handles small new files after destructive failures. | M/berloga-delegation-preference.md:17; M/local-model-fleet.md:13; T:8 | **Obsolete or contradicted by a later rule** for “Studio writes all code” (T:83); outcome T:8 explicitly switched implementation to Codex. Process preferences, not app defects. |
| 138 | External age backup quiesces writers, streams tar→age, atomically publishes outside vault, restores to new directory; no format encryption. | `docs/age-encrypted-backup.md:5`; :7; :47 | **Obsolete or contradicted by a later rule** in the catalog sense of a deferred design, not an implemented app requirement. No backup implementation was claimed or tested. External workflows remain outside audit scope. |
| 139 | Graphify query comes first; use wiki if present; code changes require update. | `AGENTS.md:28` | **Followed but untested** as operator discipline. Query/explain performed; wiki absent; no code changed, so update rule was not triggered. F22. |
| 140 | pxpipe is optional session-launch proxy; exact IDs/secrets remain text. | `AGENTS.md:11` | **Followed but untested** as operator discipline; not used in this session. F22. |
| 141 | No collaboration/plugin/Kanban/generated answers/cloud DB without measured need; OCR and optional vector extension remain deferred. | `PLAN.md:26`; P:39; P:41 | **Obsolete or contradicted by a later rule** only for blanket SQLite/AI exclusion (rules 51/73). Other explicit deferrals remain non-goals, not defects. |
| 142 | Domain words preserve node/edge/source/revision meaning; source bytes create versions, not new source identity. | `CONTEXT.md:26`; :31; :36; :41 | **Enforced by test** for source identity — `test/pdf_reader_store_test.dart:55`. Documentation vocabulary is followed but untested (F22); current note-oriented user labels are not treated as a forbidden product UI. |
| 143 | Large Dart file splits keep public methods on classes, use a shim for protected State methods, and place part directives after imports/exports. | M/tylog-megafile-split-recipe.md:16 | **Followed but untested** as refactor discipline — `lib/app_mobile.dart:476` provides the State shim; shared-library parts remain in `lib/rich_editor.dart`. F22. |
| 144 | Dates are navigable indexed knowledge: marked month grid, journal targets and linked references use VaultIndex.calendar. | M/tylog-logseq-calendar-model.md:10; :14 | **Enforced by test** for indexed marks — `test/models_test.dart:5`, “calendarDayMarks separates journal days from reference-only days”; `test/calendar_feeds_test.dart:88`, “event creation reuses page and preserves written body”. |
| 145 | Parser/cache semantic changes require an index-version bump. | M/tylog-tag-clustering.md; `packages/tylog_core/lib/src/models.dart:510` | **Followed but untested** as change-review discipline; current version is 11 at :505. F22. |
| 146 | Output is concise, plain and result-first; task-specific report requirements take precedence. | M/berloga-terse-output.md:17 | **Followed but untested** as operator discipline. This requested full report is the explicit exception; final verdict remains bounded. F22. |
| 147 | Timeline legend includes Read; More sheet groups Maintenance actions. | U:119; U:132 | **Followed but untested** as focused visual/control assertions — `lib/graph.dart:1474` contains Read; `lib/app_mobile.dart:4151` contains Maintenance. These controls require a focused regression rather than counting the old plan as test evidence. F22. |

## Findings ranked by user impact

### F1 — High — A list chip edit deletes unrelated task metadata

Changing priority clears both dates and repeat; changing one date clears the other date and repeat. Evidence: `lib/app_mobile.dart:1999` passes `null` for all unselected nullable fields at :2003–:2005; `packages/tylog_core/lib/src/scanner.dart:1584` defines explicit null as “write none”, and :1604 implements it. The editor handler correctly omits unselected arguments at `lib/rich_editor/editing_controller.dart:1033`.

Smallest fix: switch on the selected field and call `setTaskFields` with only that named argument. Extend the existing shell task tests with one chip edit on a task holding due, scheduled and recurrence. Assert every other byte remains unchanged; forwarding-only tests at `test/task_row_test.dart` cannot catch this.

### F2 — Medium — Pausing can start a foreground service after the app is backgrounded

The hidden/paused lifecycle callback starts a `background` sync that still requests the foreground service. Evidence: `lib/app_mobile.dart:2306`, :2314; `lib/workspace_controller.dart:1724`, :1741; `android/app/src/main/kotlin/org/tylog/tylog/SafBridge.kt:171`; `android/app/src/main/kotlin/org/tylog/tylog/SyncForegroundService.kt:27`. This conflicts with M/tylog-background-service.md:17. Kotlin catches start failures at `SafBridge.kt:181`, so this is not a confirmed crash, but the requested keepalive can fail.

Smallest fix: remove `background` from the FGS-start trigger set and use the already scheduled WorkManager catch-up (`lib/app_mobile.dart:2324`). Add one controller/lifecycle assertion that a background-triggered sync makes no FGS start call. Keep immediate local save intact.

### F3 — Medium — Invalid metadata envelopes disappear without an error

A task record with schema 1 and the wrong entity is removed before validation, so the task disappears and the promised invalid-record error is absent. Evidence: S:69; `packages/tylog_core/lib/src/scanner.dart:303`, :304 and :291; validator only sees surviving tasks at `packages/tylog_core/lib/src/validation.dart:127`. A valid note envelope alongside the bad task need not trigger a note fallback warning.

Smallest fix: retain a validation problem when rejecting an envelope. Add one fixture with a valid note and a mismatched task entity to the existing metadata tests. Reuse PkmsProblem; add no new validation layer.

### F4 — Medium — Missing V1 required fields are silently defaulted

A V1 task lacking status/priority becomes Todo/normal and a V1 note lacking title/kind receives inferred values, so malformed metadata looks valid. Evidence: S:25 and :69; `packages/tylog_core/lib/src/scanner.dart:2116`, :2112, :2391, :2392, :2158; `packages/tylog_core/lib/src/validation.dart:149` checks only the substituted values.

Smallest fix: check required keys on V1 dictionaries before applying legacy defaults and append validation problems. Retain legacy generation-5 compatibility. One missing-field fixture is enough to pin the distinction.

### F5 — Medium — Invalid task dates escape validation

A task with due `banana` receives no invalid-date error and cannot reliably participate in date views. Evidence: S:68; `packages/tylog_core/lib/src/scanner.dart:2394` retains date strings, while the entire task-validation loop at `packages/tylog_core/lib/src/validation.dart:127` checks only ID, text, status and priority. The chip itself falls back to displaying the raw value (`lib/widgets/task_chip_strip.dart:54`).

Smallest fix: check non-null date fields with one shared strict ISO-format/date validity check in the existing validator. Include malformed text and an impossible calendar day; Dart DateTime parsing alone normalizes some impossible dates.

### F6 — Medium — Fallback task reading drops supported custom properties

When Typst inspection fails, task custom properties disappear from the derived task model even though that model supports them. Evidence: S:15; successful reading copies properties at `packages/tylog_core/lib/src/scanner.dart:2406`, but `_fallbackTasks` at :2412 never copies them. This is a derived-data loss claim, not a claim that source bytes are rewritten.

Smallest fix: reuse the existing properties parser used by note fallback for task fallback. Add one failed-inspection task containing a custom property to the existing core fallback test.

### F7 — Medium — Attachment and path rules disagree across writers and validation

A normal attached file is emitted with `/assets/...`, then reported as unsafe by the validator, while an internal backslash path can pass validation but fail storage access. Evidence: `lib/app_mobile.dart:3963`; `lib/controlled_editor.dart:476`; `typst/tylog/lib.typ:84` emits the path unchanged; `packages/tylog_core/lib/src/scanner.dart:2157` retains it; `packages/tylog_core/lib/src/validation.dart:209`, :213; storage rejects backslashes at `packages/tylog_core/lib/src/storage.dart:185`. S:13 forbids absolute record paths but S:105 explicitly documents leading-slash source paths and passthrough metadata.

Smallest fix: strip the Typst root slash when producing the metadata record, while keeping the source lookup slash; normalize legacy root-slash records at the reader boundary. Reuse `validateVaultPath` for validation instead of the weaker duplicate helper. Add an attach→query→validate fixture.

### F8 — Medium — The one-store and atomic-save documentation promises conflicting behavior

The active plan calls SQLite authoritative and promises an atomic durable edit, while current code deliberately keeps a successful file write after database failure. Evidence: P:33, :34; `lib/workspace_controller.dart:1080`, :1085, :1101; current handbook describes that recovery correctly at `USER_MANUAL.md:120`. Database transaction tests only cover database writes (`test/database/tylog_atomic_edit_test.dart:21`).

Smallest fix: replace the obsolete fixed decision with the actual file-authority/projection retry contract and distinguish filesystem success from projection success. Keep the existing file-preservation behavior; do not add a distributed transaction to satisfy old prose. This is documentation drift, not a request to undo the safety fix. Catalog rules 52–54.

### F9 — Medium — Rich-paste task-boundary safety has no focused regression

The rich clipboard path bypasses the cross-block task guard and has only a start-block protection check, leaving the memory's recorded safety gap without direct coverage. Evidence: M/tylog-taskline-redesign.md:18; `lib/rich_editor/editing_controller.dart:1124`; `lib/rich_editor/document_model.dart:1292`; the normal guard is at :459. The rich path clamps selection to the first block at :1298, so the old memory's implicit whole-span destructive behavior is not established by source.

Smallest fix: add one existing-editor test that rich-pastes over a selection crossing a task boundary and asserts preservation or a visible safe refusal. Fix only a failing case; do not rewrite clipboard architecture preemptively.

### F10 — Medium — Validator vocabulary rules lack focused assertions

The invalid-status/priority and extension-kind branches are present, but the validator regression does not exercise them, so these agreed format rules can drift unnoticed. Evidence: `packages/tylog_core/lib/src/validation.dart:81`, :149, :159; `test/pkms_registry_test.dart:9` checks missing/unsafe attachments and empty IDs/text only. Rules 10 and 38.

Smallest fix: add one parameterized validator fixture for unknown status, priority and extension kind. Assert errors for the first two and a warning retaining the last.

### F11 — Low — The core dependency boundary has no automated check

The documented Flutter-independent core currently follows the boundary, but nothing focused prevents a future Flutter import from breaking the headless CLI. Evidence: E:57; core scanner imports at `packages/tylog_core/lib/src/scanner.dart:1`; the Flutter adapter remains outside core (`lib/scanner.dart:2`). Core tests validate behavior, not dependency imports.

Smallest fix: add a small import/dependency assertion to the existing package-contract test. No new package or architectural wrapper.

### F12 — Low — Shell and graph layout stability is untested

Transient status uses overlays today, but no focused geometry assertion protects the adopted no-layout-shift rule for shell and graph banners. Evidence: M/tylog-ui-no-layout-shift.md:16; `lib/graph.dart:384`, :386; `lib/app_mobile.dart:4959` status-pill overlay; `lib/rich_editor/editor_widgets.dart:1299`. The task-strip regression at `test/task_typing_test.dart:623` covers only task timing.

Smallest fix: record editor/canvas bounds in existing widget tests, toggle a transient status/banner, and assert bounds stay equal. Document the AnimatedSize exception for space-reserving docks.

### F13 — Low — Archive memory-release behavior has no regression assertion

Archive reads correctly free per-entry content now, but transfer-count tests do not pin the memory-release behavior that fixed gigabyte retention. Evidence: `lib/nextcloud_sync.dart:1566`; archive restore tests `test/nextcloud_sync_test.dart:5999`, :6037. The historical mechanism is described at `docs/sync-memory-findings.md:24`.

Smallest fix: add one focused archive-entry test proving content is released after a read and a second entry remains readable. Avoid a flaky process-memory threshold.

### F14 — Low — Current overview docs wrongly exclude SQLite and durable revision JSON

PLAN and ecosystem deferrals say SQLite is absent, and README restricts JSON to operational/derived data, although the app opens SQLite and materializes durable revision payloads. Evidence: `PLAN.md:26`; E:134; `README.md:3`; `lib/database/tylog_database.dart:1287`; `lib/database/revision_publisher.dart:90`, :93, :99. Rules 50–52.

Smallest fix: delete SQLite from the exclusions and list private database projections and revision envelopes explicitly. Point to the file-authority contract described in F8.

### F15 — Low — Revision transport no longer matches the plan's fixed decisions

The active plan promises separate v2 immutable batches/device-head publication, but shipping publication uses mutable session envelopes in the ordinary `_system/revisions` tree. Evidence: P:36; `lib/database/revision_publisher.dart:57`, :90, :95; `lib/workspace_controller.dart:1767`. Published revision payloads are sealed; that is different from the advertised transport format.

Smallest fix: replace the old transport decision with the implemented envelope/coalescing/ancestry contract, including what a failed write leaves pending. Keep existing transport; do not implement a second sync protocol for stale prose.

### F16 — Low — “No AI/RAG” hides the shipped offline semantic-search feature

The broad exclusion makes users and contributors miss an explicit model download and vector retrieval already in the app. Evidence: `PLAN.md:26`; `USER_MANUAL.md:126`; `docs/research-tylog-features.md:121`; `lib/app_mobile.dart:4217`, :4233; `test/semantic_search_controller_test.dart:45`.

Smallest fix: replace “no AI/RAG” with “no generated answers” and describe optional offline semantic search. Keep external article generation separate from the app.

### F17 — Low — The handbook says conflicts never merge automatically

The handbook's blanket statement contradicts append-only conflict resolution already covered by tests. Evidence: `USER_MANUAL.md:126`; `docs/superpowers/plans/2026-08-21-sync-conflict-recovery.md:10`; `test/nextcloud_sync_test.dart:4760`, :4772 and :4785 assert the implementation's longer-side adoption and genuine conflict preservation.

Smallest fix: describe automatic identical/append-only/ancestry handling and explicit review for genuine divergent edits. Remove the blanket prohibition.

### F18 — Low — macOS no-sandbox policy has no configuration regression

Both entitlements are correctly false, but a one-word configuration change could break persisted folder access without a focused test. Evidence: M/tylog-macos-no-sandbox.md:14; `macos/Runner/Release.entitlements:5`, `macos/Runner/DebugProfile.entitlements:5`; existing `test/release_config_test.dart:6` does not inspect them.

Smallest fix: extend that release-config test to parse both entitlement plists and assert false. Write the policy into repo docs with the bookmarks/App Store exception.

### F19 — Low — Startup test guards have no explicit no-side-effect regression

The database and macOS updater have Flutter-test guards, but the tests do not directly assert that a normal test mount launches neither default disk database opening nor update HTTP work. Evidence: `lib/app_mobile.dart:483`, :552; M/tylog-flutter-test-rootbundle-wedge.md:15. Many widget tests inject startup, including `test/widget_test.dart:104`, so their safe mount alone is weaker evidence.

Smallest fix: add one bounded mount→dispose→asset-read regression with existing injection hooks, asserting no default updater/database call. Promote the guard rule into AGENTS.md.

### F20 — Low — Headless native lifecycle rules lack a focused regression gate

Service completion, no managed-file upgrades, release Room retention and platform window/engine lifecycle are implemented but are not pinned by a test of the complete unattended path. Evidence: `lib/vault_service.dart:42`, :59, :157; `android/app/proguard-rules.pro:4` Room keep rule; `macos/Runner/MainFlutterWindow.swift:20` hide-on-close; `ios/Runner/AppDelegate.swift:65` headless teardown. Existing lock tests at `test/vault_lock_test.dart:10` establish only the run-budget/lock contract.

Smallest fix: add one headless fake-storage regression for completion and zero initialization writes; add configuration checks to the existing release test for Room and entrypoint reachability. Keep manual macOS/iOS lifecycle acceptance explicitly separate.

### F21 — Low — In-place profile signing and test suffix policy are not pinned

The build configuration follows the policy only when a release keystore exists, and no focused test protects the debug/profile app-ID and signing branches. Evidence: `AGENTS.md:3`; `android/app/build.gradle.kts:61`, :66, :79, :83; M/tylog-profile-drive-uninstalls-prod.md. This audit did not inspect signing material or verify installed certificates.

Smallest fix: extend the existing release-config test for `.debug`, profile release signing and optional `.profiletest` suffix. State the keystore prerequisite in AGENTS.md; retain the isolated drive-harness rule separately from normal profile installs.

### F22 — Low — Operator rules and stale guidance have no single maintained home

Several adopted rules exist only in private memory, while current docs retain contradictory claims, so future work can follow an obsolete procedure. Evidence: `AGENTS.md:8` recommends gfxinfo; M/tylog-worker-isolate.md:20 rejects it for Flutter jank; `integration_test/support/editor_frame_metrics.dart` records Flutter frame metrics. `.claude/skills/verify/SKILL.md:30` says widget tests never open vaults, but `test/widget_test.dart:90` initializes fixture vault storage. `CONTEXT.md:19` claims rollback can delete a new note, while `lib/workspace_controller.dart:1101` and `test/workspace_controller_test.dart:1562` preserve it. Rules 78–80, 129–136, 139–140, 143, 145–147 and vocabulary/review discipline have no automatic evidence-review gate. Timeline Read and Maintenance are present at `lib/graph.dart:1474` and `lib/app_mobile.dart:4151`, but their focused visual acceptance remains unpinned.

Smallest fix: consolidate the memory-only operator contracts below in AGENTS.md or the relevant repo spec; delete stale claims and link the existing tests/harnesses. Do not invent tests for human review preferences. Use explicit dated evidence for throughput, hardware, seven-day use and publication gates.

### F23 — Low — Native-source CI gate checks a stamp, not the final artifact

CI asserts that source setup wrote a platform stamp, but the automated release check does not prove that the APK/bundle embeds the source-built library. Evidence: `.github/workflows/release.yml:48`, :56, :68; `tool/assert_source_built.sh:16`, :33; `test/release_config_test.dart:41`; M/tylog-ci-ships-native-from-source.md:36 requires checking the packaged APK. This is an enforcement gap, not a claim the current artifacts contain upstream code.

Smallest fix: after packaging, compare the embedded native library's hash with the source-build output using existing shell/unzip tools. Keep the setup stamp as an early failure check; add no dependency.

## Memory-only instructions to promote into repo docs

These are portable instructions whose explicit policy is still confined to memory, even where code/comments already implement them. Do not copy private host paths, device IDs, raw samples or account details.

| Instruction | Memory evidence | Smallest repo home |
|---|---|---|
| Transient shell/graph status overlays; AnimatedSize only for reserving docks; settle before dock taps. | M/tylog-ui-no-layout-shift.md:16 | AGENTS.md; link task-strip test and add shell/graph geometry assertion. |
| Default test mounts must suppress updater and default database side effects. | M/tylog-flutter-test-rootbundle-wedge.md:15 | AGENTS.md; cite `lib/app_mobile.dart:483`, :552. |
| macOS is deliberately unsandboxed until persistent security-scoped bookmarks exist. | M/tylog-macos-no-sandbox.md:14 | README development section and release-config test. |
| Measure CPU/byte identity/sync decisions before diagnosing hangs or lost text. | M/tylog-measure-before-diagnosing.md:26; M/tylog-headerless-daily.md:9 | Troubleshooting runbook; avoid claiming an external vault diagnosis without observations. |
| root-isolate timing/Flutter frame timings measure Flutter; gfxinfo decor counts cannot establish Flutter jank. | M/tylog-worker-isolate.md:20; M/tylog-device-debugging-gotchas.md:21 | Correct AGENTS.md profiling section; link existing native metric harness. |
| Article producer must use auto-related marker, preserve LLM links, read gzip/plain index safely and emit five-stage status. | M/tylog-article-pipeline-contract.md:24 | `docs/tylog-ecosystem.md`; publish interface only, not external machine setup. |
| Parsing changes require an index-version bump when cache semantics change. | M/tylog-tag-clustering.md; M/tylog-basics-first-shipped.md | AGENTS.md indexing section; link current index/cache tests. |
| Profile integration drive must isolate the package; normal release/profile installs preserve the production package. | M/tylog-profile-drive-uninstalls-prod.md | AGENTS.md; distinguish install from flutter drive. |
| Device editor replay must include cold startup and delayed save; never suppress device tooling errors. | M/tylog-device-loop-codex.md:9; M/adb-path-check.md:9 | Device test runbook; no device identifiers needed. |
| Improve existing mechanisms before changing formats; trace every consumer; review delegated edits. | M/berloga-improve-not-clone.md:11; M/berloga-system-level-planning.md:11; M/berloga-delegation-preference.md:17 | AGENTS.md, as review discipline rather than a new app abstraction. |
| Room retention and hidden macOS window are intentional release/lifecycle requirements. | M/tylog-background-service.md:27; :32 | Platform development notes and release-config checks. |

Already present in repo docs: surgical task writers (T:32), compile-output verification (Logseq import plan:20), NFC sync comparison (P24 evidence:73), per-path conflict gate (conflict recovery outcome:9), worker indexing (audit evidence and tests), and local undo (S:118). Those need prominent links, not duplicate competing versions. The blanket conflict gate and old “adb typing does not work” memory are historical, not rules to promote unchanged.

## Stale and contradictory statements

| Document statement | Current source confirmation | Smallest correction |
|---|---|---|
| CONTEXT.md:7 says 0.12.0+133; README/PLAN say 0.12.2+135; working-tree package declares 0.12.3+136. | `pubspec.yaml:19` and `PLAN.md:3`. | Update or delete the duplicated release line. |
| CONTEXT.md:19 says database rollback may delete a new file. | `lib/workspace_controller.dart:1101`; `test/workspace_controller_test.dart:1562`. | Mark fixed; retain any genuinely open envelope-size issue separately. |
| PLAN.md:26 and E's deferrals say no SQLite. | `lib/database/tylog_database.dart:1287`. | Remove that exclusion. |
| README.md:3 restricts JSON to operational/derived files. | `lib/database/revision_publisher.dart:90`. | Include durable revision envelopes and private projection storage. |
| P:33–:34 promise one SQLite authority/atomic save across app content. | `lib/workspace_controller.dart:1080`, :1085, :1101; `USER_MANUAL.md:120`. | Record file authority and database retry behavior. |
| P:36 promises separate v2 immutable transport batches/device heads. | `lib/database/revision_publisher.dart:90`, :95. | Replace with actual session-envelope transport contract. |
| PLAN.md:26, USER_MANUAL.md:126 and research features:121 say no AI/RAG. | `lib/app_mobile.dart:4217`; `test/semantic_search_controller_test.dart:45`. | Name optional offline semantic search; exclude generated answers precisely. |
| USER_MANUAL.md:126 says no automatic conflict merging. | `test/nextcloud_sync_test.dart:4760`, :4772; recovery outcome:10. | Describe safe append-only adoption and genuine-divergence review. |
| S:13 forbids root-slash records; S:105 says attachment helper emits slash as passed. | `typst/tylog/lib.typ:84`; validator `validation.dart:209`. | Separate Typst lookup paths from canonical metadata paths. |
| AGENTS.md:8 presents gfxinfo as real app frame timing. | `integration_test/support/editor_frame_metrics.dart`; root-isolate jank harness. | Link Flutter frame metrics; qualify gfxinfo's limited platform scope. |
| Verify skill:30 says widget tests never open a vault. | `test/widget_test.dart:90`. | Say default test startup avoids real vaults; injected fixture vaults are supported. |
| Verify skill:31 says eye icon cycles normal→preview→source. | `test/widget_test.dart:897` covers read/preview/source/editor chooser; `lib/app_mobile.dart:4376` includes read/split. | Describe current view chooser. |
| docs/sync-memory-findings.md:3 says none of the investigation is implemented. | `lib/nextcloud_sync.dart:1566` implements its leading memory fix. | Mark fixed items and retain unimplemented suggestions as historical. |
| P:101 says U0 verification still pending; the same plan's current state says verified. | P:6 plus U0 linked evidence; current UI regressions in `test/widget_test.dart`. | Replace old remaining-action paragraph with current evidence link. |
| M/tylog-sync-conflict-gate.md describes a vault-wide suspend. | `lib/workspace_controller.dart:1522`; `lib/vault_service.dart:76`; sync regression :5007. | Mark superseded by per-path gate; do not restore blanket gate. |
| lib/vault_service.dart:23 says it honors a conflict gate like UI. | Its own :76 explicitly removes the blanket gate. | Rewrite the comment to say per-path conflict protection. |
| M/tylog-taskline-redesign.md:19 discourages adb injection. | Later M/tylog-device-loop-codex.md:9 records successful A24 cold replay. | Scope old advice to old device/session; document current supported replay. |
| T original context/execution describe missing triggers, quick-add date parsing and Studio implementation. | T:8 and :12 explicitly preserve the old plan; current writer/UI tests confirm the outcome. | Already labeled historical; no code violation and no rewrite required. |

No stale-performance finding is made from unmeasured external phones or the currently installed macOS app. “macOS app is old” and private production health cannot be confirmed from repository source alone. The old FIXLOG references in memory and verify notes cannot resolve because FIXLOG.md is absent.

## Additional named test references

Catalog entries that name a suite use these inspected tests. Broader suites may assert additional cases; a named test is evidence only for the behavior it checks.

| Suite | Named test |
|---|---|
| `packages/tylog_core/test/dedupe_test.dart:7` | dedupe reports dry-run and safely applies supported duplicate fixes |
| `test/database/node_search_fts_test.dart:12` | incrementally indexes Unicode node text and excludes tombstones |
| `test/database/portable_merge_test.dart:22` | canonical key ordering makes an exact row re-import unchanged |
| `test/import/legacy_import_runner_test.dart:61` | runs bounded batches and accounts outcomes |
| `test/import/legacy_import_runner_test.dart:136` | recreated runner processes exact bounded batches without duplicates |
| `test/import/legacy_import_plan_test.dart:49` | classifies all files, including hidden Obsidian files |
| `test/vault_import_policy_test.dart:32` | assignImportOutputPath suffixes existing and batch collisions |
| `integration_test/markdown_import_native_test.dart:14` | imports, compiles, and queries canonical article metadata |
| `test/pdf_annotation_reattach_test.dart:21` | duplicate quote with equal candidates is marked ambiguous |
| `integration_test/pdf_reader_review_native_test.dart:14` | ambiguous highlight is reassigned through Needs review |
| `test/pdf_extraction_test.dart:20` | image-only pages are explicit unsupported input |
| `integration_test/private_pdf_corpus_test.dart:44` | opt-in redacted private PDF corpus check |
| `test/retrieval_cosine_test.dart:11` | cosine search ranks vectors and breaks ties by id |
| `test/retrieval_native_embedding_test.dart:5` | native passage embedder requires both model assets |
| `test/database/bounded_neighborhood_test.dart:7` | bounded neighborhood terminates on cycles and returns stable depths |
| `test/conflict_choice_test.dart:24` | an append on either side is a superset, not a disagreement |
| `test/sync_dashboard_test.dart:60` | a second conflict resolves while the first is still working |
| `test/relink_strip_test.dart:20` | stripAutoRelated removes an appended block and is idempotent |
| `packages/tylog_core/test/scanner_base_files_test.dart:90` | base-aware inspector gets the file set once, empty maps per note |
| `test/tool/test_tylog_corpus_manifest.py:67` | test_no_paths_in_json_output |
| `test/tool/test_benchmark_exact_cosine.py:48` | test_privacy_and_bad_file |

## Limits and verdict

No credentials were printed or copied. No network or real-account tests were run. Generated database code was used only to locate implementation; detailed native Rust/importer correctness, external producer code, operator host tools and production vaults were outside the requested app/core audit. Test assertions were read; their current pass/fail state is unknown. Proposed/waived features are not counted as bugs. Deferred age workflow has no confirmed implementation to assess. Unconfirmed suspected bugs were dropped.

Verdict: fix the task-chip handler first; keep the tested sync safety behavior.
Findings: 23 total — 1 high, 9 medium, 13 low.
Top 1: F1 — list chip edits erase dates/repeat (high).
Top 2: F2 — pause path attempts background FGS start (medium).
Top 3: F3 — invalid metadata envelopes disappear silently (medium).
Top 4: F4 — missing required fields become valid-looking defaults (medium).
Top 5: F5 — invalid task dates pass validation (medium).
Not checked: test execution, devices, network, real vaults or delivered artifacts.
Risk: coverage labels establish assertions exist, not fresh runtime acceptance.
