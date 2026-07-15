# Graph Report - TypstSeq  (2026-07-15)

## Corpus Check
- 138 files · ~112,158 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 2847 nodes · 3869 edges · 126 communities (91 shown, 35 thin omitted)
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS · INFERRED: 6 edges (avg confidence: 0.88)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `21f407b5`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- app_mobile.dart
- frb_generated.dart
- rich_editor.dart
- frb_generated.web.dart
- frb_generated.io.dart
- typst.rs
- nextcloud_sync.dart
- graph.dart
- controlled_editor.dart
- scanner.dart
- .sse_decode
- GeneratedPluginRegistrant.swift
- vault.dart
- files.dart
- exceptions.dart
- typst.dart
- FFI Plugin Platforms
- typst_document_viewer.dart
- typst_view.dart
- setup.dart
- vault_registry.dart
- my_application.cc
- frb_generated.rs
- document.dart
- dart:io
- dart:convert
- SseDecode
- nextcloud_sync_test.dart
- IntoDart
- StatelessWidget
- compiler.dart
- knowledge_screen.dart
- .into_dart
- State
- widget_test.dart
- validation.dart
- typst_compiler_provider.dart
- graph_test.dart
- SseSerializer
- TyLog v5 user handbook
- typst_flutter.dart
- rich_editor_native_test.dart
- CompiledDocumentImpl
- RustLib
- workspace_controller.dart
- TyLog Linux Build Configuration
- Flutter Linux Build Step
- models.dart
- markdown_article_import.dart
- String
- RustLibApiImplPlatform
- workspace_controller_test.dart
- SafBridge
- RustLibWasmModule
- BaseWire
- PackageDescription
- GraphPainter
- tylog.dart
- search_index.dart
- flutter_export_environment.sh
- TypstFlutter.swift
- setup_typst_native.sh
- README.md
- DateTime
- PageInfo?
- TypstSeverity
- TypstSourceLocation?
- Research Journals as Scientific Infrastructure
- GitHub Actions Run 28754170425
- GitHub Issue 42
- Local typst_flutter Fork
- Namespaced Typst Interface
- Nextcloud Sync Behavior
- Reproducible Typst Reports
- Schema-v5 Vault
- Local-first Typst-first Workspace
- Make Verify Release Gates
- Backup and Index Rebuild
- Bibliography-backed Citations
- Magic Actions
- Nextcloud Sync
- Reproducible Reports
- Today-first Workspace
- vault_storage.dart
- storage.dart
- vault.dart
- tylog_core.dart
- month_calendar.dart
- graph.dart
- vault_storage_test.dart
- report.dart
- markdown_import.dart
- task_scheduler.dart
- tylog_assets.dart
- fonts.dart
- bibliography.dart
- core_test.dart
- TypstInspector
- platform_file_actions.dart
- Verifying TyLog on macOS
- Exception
- cli_test.dart
- @internal
- CompiledDocument
- AGENTS.md
- WorkspaceController
- TypstCompileError
- GraphView
- TyLogEditingController
- README.md
- crate::api::typst::RenderResult
- crate::api::typst::TypstCompileError

## God Nodes (most connected - your core abstractions)
1. `String` - 35 edges
2. `SimpleWorld` - 29 edges
3. `SafBridge` - 27 edges
4. `TypstRenderer` - 13 edges
5. `convert_markdown()` - 12 edges
6. `CompiledDocument` - 12 edges
7. `SyncForegroundService` - 11 edges
8. `TypstDiagnostic` - 10 edges
9. `crate::api::markdown_import::MarkdownImportDiagnostic` - 10 edges
10. `crate::api::markdown_import::MarkdownTypstResult` - 10 edges

## Surprising Connections (you probably didn't know these)
- `Native Compiler Setup Step` --semantically_similar_to--> `Explicit Native Compiler Setup`  [INFERRED] [semantically similar]
  .github/workflows/linux.yml → README.md
- `FlutterTypstInspector` --implements--> `TypstInspector`  [EXTRACTED]
  lib/flutter_typst_inspector.dart → packages/tylog_core/lib/src/scanner.dart
- `AndroidTreeVaultStorage` --inherits--> `VaultStorage`  [EXTRACTED]
  lib/vault_storage.dart → packages/tylog_core/lib/src/storage.dart
- `_FakeInspector` --implements--> `TypstInspector`  [EXTRACTED]
  test/workspace_controller_test.dart → packages/tylog_core/lib/src/scanner.dart
- `_MemoryStorage` --inherits--> `VaultStorage`  [EXTRACTED]
  test/workspace_controller_test.dart → packages/tylog_core/lib/src/storage.dart

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **TyLog v5 Vault Architecture** — plan_schema_v5_vault, readme_local_first_typst_first_workspace, user_manual_vault_format [INFERRED 0.85]
- **Native Typst Compiler Integration** — github_workflows_linux_native_compiler_setup, readme_explicit_native_compiler_setup, plan_local_typst_flutter_fork, packages_typst_flutter_linux_cmakelists_prebuilt_typst_flutter_library, packages_typst_flutter_pubspec_ffi_plugin_platforms [INFERRED 0.95]
- **Release Verification Pipeline** — github_workflows_linux_linux_build, plan_release_verification, readme_make_verify [INFERRED 0.85]

## Communities (126 total, 35 thin omitted)

### Community 0 - "app_mobile.dart"
Cohesion: 0.01
Nodes (228): bibliography.dart, DateTime? get, double? get, graph.dart, IconData, knowledge_screen.dart, _acceptRichSource, activeVaultId (+220 more)

### Community 1 - "frb_generated.dart"
Cohesion: 0.01
Nodes (182): ApiImplConstructor, ExternalLibraryLoaderConfig get, frb_generated.io.dart, addFonts, apiImplConstructor, codegenVersion, compile, crateApiMarkdownImportConvertMarkdown (+174 more)

### Community 2 - "rich_editor.dart"
Cohesion: 0.01
Nodes (146): FocusNode, _addTextSpans, _addUndo, applyMagic, aSources, atom, _atomLabel, block (+138 more)

### Community 3 - "frb_generated.web.dart"
Cohesion: 0.01
Nodes (135): api/markdown_import.dart, api/typst.dart, external RustLibWasmModule get, package:flutter_rust_bridge/flutter_rust_bridge_for_generated_web.dart, dco_decode_Auto_Owned_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerCompiledDocument, dco_decode_Auto_Owned_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerTypstEngine, dco_decode_Auto_Ref_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerCompiledDocument, dco_decode_Auto_RefMut_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerTypstEngine (+127 more)

### Community 4 - "frb_generated.io.dart"
Cohesion: 0.01
Nodes (136): CrossPlatformFinalizerArg
  get, package:flutter_rust_bridge/flutter_rust_bridge_for_generated_io.dart, dco_decode_Auto_Owned_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerCompiledDocument, dco_decode_Auto_Owned_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerTypstEngine, dco_decode_Auto_Ref_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerCompiledDocument, dco_decode_Auto_RefMut_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerTypstEngine, dco_decode_box_autoadd_i_64, dco_decode_box_autoadd_typst_source_location (+128 more)

### Community 5 - "typst.rs"
Cohesion: 0.08
Nodes (48): Bytes, DiagSpan, Duration, FileError, FileId, Font, FontBook, HashMap (+40 more)

### Community 6 - "nextcloud_sync.dart"
Cohesion: 0.02
Nodes (126): action, _appendTrace, base, _cleanResolvedConflictCopies, _client, config, conflicts, connectionRetryDelays (+118 more)

### Community 7 - "graph.dart"
Cohesion: 0.04
Nodes (50): ColorScheme, dart:math, build, _canvas, center, colorScheme, createState, currentPath (+42 more)

### Community 8 - "controlled_editor.dart"
Cohesion: 0.03
Nodes (65): action, _addBlocks, applyMagicEdit, _balancedParenEnd, _balancedSquareEnd, _block, blocks, bodyStart (+57 more)

### Community 9 - "scanner.dart"
Cohesion: 0.02
Nodes (123): Object?, _add, _aliases, allProblems, attachmentBacklinks, attachmentCalls, attachments, backlinks (+115 more)

### Community 10 - ".sse_decode"
Cohesion: 0.07
Nodes (20): bool, f64, Option<crate::api::typst::TypstSourceLocation>, Option<i64>, Option<std::collections::HashMap<String, String>>, Option<String>, Option<usize>, Self (+12 more)

### Community 11 - "GeneratedPluginRegistrant.swift"
Cohesion: 0.05
Nodes (30): Any, Cocoa, file_picker, Flutter, flutter_local_notifications, flutter_secure_storage_darwin, flutter_timezone, FlutterAppDelegate (+22 more)

### Community 12 - "vault.dart"
Cohesion: 0.05
Nodes (36): Directory? get, article, bibliographyPath, configured, dailyNote, storage, day, defaultVaultDirectory (+28 more)

### Community 13 - "files.dart"
Cohesion: 0.06
Nodes (41): @immutable, @internal, Equatable, initial, initialize, nextTaskReminder, plugin, reconcile (+33 more)

### Community 14 - "exceptions.dart"
Cohesion: 0.32
Nodes (7): package:typst_flutter/src/rust/api/typst.dart, diagnostics, message, toString, TypstCompileException, TypstException, TypstRenderException

### Community 15 - "typst.dart"
Cohesion: 0.06
Nodes (31): addFonts, bytes, column, compile, diagnostics, exportPdf, exportSvg, getTypstVersion (+23 more)

### Community 16 - "FFI Plugin Platforms"
Cohesion: 0.29
Nodes (7): Flutter Recommended Lints, Prebuilt typst_flutter Linux Library, FFI Plugin Platforms, Local typst_flutter Package Fork, flutter_lints Dependency, TyLog Flutter Application Package, typst_flutter Path Dependency

### Community 17 - "typst_document_viewer.dart"
Cohesion: 0.06
Nodes (31): Color, color, package:typst_flutter/src/widgets/typst_compiler_provider.dart, package:typst_flutter/src/widgets/typst_view.dart, _activeDocument, build, _compileDocument, _compiler (+23 more)

### Community 18 - "typst_view.dart"
Cohesion: 0.07
Nodes (29): BoxFit, package:flutter_svg/flutter_svg.dart, build, _buildWrapper, _compiler, createState, date, didChangeDependencies (+21 more)

### Community 19 - "setup.dart"
Cohesion: 0.06
Nodes (30): dart:isolate, package:archive/archive_io.dart, package:http/http.dart, package:path/path.dart, androidArtifacts, _Artifact, _artifactsForPlatform, destination (+22 more)

### Community 20 - "vault_registry.dart"
Cohesion: 0.05
Nodes (43): File, NextcloudConfig, active, activeId, add, addTree, backupPath, cloud (+35 more)

### Community 21 - "my_application.cc"
Cohesion: 0.09
Nodes (22): FlPluginRegistry, FlView, GApplication, gboolean, gchar, GObject, GtkApplication, fl_register_plugins() (+14 more)

### Community 22 - "frb_generated.rs"
Cohesion: 0.20
Nodes (26): c_void, MessagePort, frbgen_typst_flutter_rust_arc_decrement_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerCompiledDocument(), frbgen_typst_flutter_rust_arc_decrement_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerTypstEngine(), frbgen_typst_flutter_rust_arc_increment_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerCompiledDocument(), frbgen_typst_flutter_rust_arc_increment_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerTypstEngine(), pde_ffi_dispatcher_primary_impl(), pde_ffi_dispatcher_sync_impl() (+18 more)

### Community 23 - "document.dart"
Cohesion: 0.08
Nodes (24): CompiledDocument get, dart:ui, Image?, bytes, _cachedImage, _checkNotDisposed, _decodeImage, dispose (+16 more)

### Community 24 - "dart:io"
Cohesion: 0.11
Nodes (18): controlled_editor.dart, dart:typed_data, flutter_typst_inspector.dart, _compiler, create, dispose, inspect, compiler (+10 more)

### Community 25 - "dart:convert"
Cohesion: 0.09
Nodes (26): dart:convert, dart:io, main, smokeValue, json, main, normalized, _normalizedMetadata (+18 more)

### Community 26 - "SseDecode"
Cohesion: 0.11
Nodes (10): f32, i32, i64, u32, u8, usize, Vec<crate::api::markdown_import::MarkdownImportDiagnostic>, SseDecode (+2 more)

### Community 27 - "nextcloud_sync_test.dart"
Cohesion: 0.06
Nodes (34): HttpException, LocalVaultStorage, String? remoteModifiedValue,
  String, bytes, _CheckpointCountingStorage, checkpointWrites, _config, etag (+26 more)

### Community 28 - "IntoDart"
Cohesion: 0.15
Nodes (10): IntoDart, IntoDartExceptPrimitive, MarkdownTypstResult, crate::api::markdown_import::MarkdownTypstResult, crate::api::typst::PageInfo, crate::api::typst::TypstSourceLocation, FrbWrapper<CompiledDocument>, FrbWrapper<TypstEngine> (+2 more)

### Community 29 - "StatelessWidget"
Cohesion: 0.10
Nodes (20): _DockButton, _EmptyHint, _LibraryView, _LinksPanel, _PrimaryTasksView, _SectionTitle, _SettingsSheet, _SettingsTile (+12 more)

### Community 30 - "compiler.dart"
Cohesion: 0.10
Nodes (18): dart:ffi, package:typst_flutter/src/document.dart, package:typst_flutter/src/exceptions.dart, package:typst_flutter/src/files.dart, package:typst_flutter/src/fonts.dart, package:typst_flutter/src/rust/api/markdown_import.dart, package:typst_flutter/src/rust/frb_generated.dart, addFonts (+10 more)

### Community 31 - "knowledge_screen.dart"
Cohesion: 0.16
Nodes (10): Intent, start(), stop(), SyncForegroundService, update(), Context, IBinder, Notification (+2 more)

### Community 32 - ".into_dart"
Cohesion: 0.26
Nodes (3): DartAbi, crate::api::typst::VirtualFile, VirtualFile

### Community 33 - "State"
Cohesion: 0.11
Nodes (25): _NativeMagicHarness, _NativeMagicHarnessState, _CalendarTab, _CalendarTabState, _Editor, _EditorState, HomeScreen, _HomeScreenState (+17 more)

### Community 34 - "widget_test.dart"
Cohesion: 0.10
Nodes (17): package:flutter_test/flutter_test.dart, package:tylog/bibliography.dart, package:tylog/controlled_editor.dart, package:tylog/models.dart, package:tylog/pkms_registry.dart, package:tylog/report.dart, package:tylog/search_index.dart, package:tylog/task_scheduler.dart (+9 more)

### Community 35 - "validation.dart"
Cohesion: 0.14
Nodes (13): count, _duplicates, isSafeVaultPath, owners, PkmsValidationReport, priorities, problems, standardKinds (+5 more)

### Community 36 - "typst_compiler_provider.dart"
Cohesion: 0.18
Nodes (10): Finalizable, InheritedWidget, package:flutter/widgets.dart, package:typst_flutter/src/compiler.dart, TypstCompiler, compiler, maybeOf, of (+2 more)

### Community 37 - "graph_test.dart"
Cohesion: 0.12
Nodes (16): KnowledgeView, ListTile, package:tylog/app_mobile.dart, package:tylog/knowledge_screen.dart, package:tylog/main.dart, ensureVisible, _knowledgeScreen, main (+8 more)

### Community 38 - "SseSerializer"
Cohesion: 0.17
Nodes (6): FrbWrapper, IntoIntoDart, MarkdownImportDiagnostic, CompiledDocument, crate::api::markdown_import::MarkdownImportDiagnostic, TypstEngine

### Community 39 - "TyLog v5 user handbook"
Cohesion: 0.06
Nodes (29): Compatibility contract, Components, Flutter-independent core, Repository CLI, Runtime adapters and Flutter app, TyLog ecosystem, Typst package, Verification (+21 more)

### Community 40 - "typst_flutter.dart"
Cohesion: 0.17
Nodes (11): src/compiler.dart, src/document.dart, src/exceptions.dart, src/files.dart, src/fonts.dart, src/markdown_import.dart, src/rust/api/markdown_import.dart, src/rust/api/typst.dart (+3 more)

### Community 41 - "rich_editor_native_test.dart"
Cohesion: 0.11
Nodes (18): build, controller, createState, dispose, end, errors, _initialSource, main (+10 more)

### Community 42 - "CompiledDocumentImpl"
Cohesion: 0.40
Nodes (6): @sealed, CompiledDocument, CompiledDocumentImpl, TypstEngineImpl, RustOpaque, TypstEngine

### Community 43 - "RustLib"
Cohesion: 0.40
Nodes (6): BaseApi, BaseEntrypoint, RustLib, RustLibApi, RustLibApiImpl, RustLibApiImplPlatform

### Community 44 - "workspace_controller.dart"
Cohesion: 0.03
Nodes (70): bool get, double?, SyncResult, _autosave, bibliographySource, cancelPendingWork, cancelRebuild, _cancelTimers (+62 more)

### Community 45 - "TyLog Linux Build Configuration"
Cohesion: 0.40
Nodes (6): Apply Standard Settings, Relocatable Linux Bundle, TyLog Linux Build Configuration, Flutter Assemble Target, Flutter Interface Library, TyLog Linux Runner

### Community 46 - "Flutter Linux Build Step"
Cohesion: 0.40
Nodes (5): Flutter Linux Build Step, Linux Build Workflow, Native Compiler Setup Step, Release Verification, Explicit Native Compiler Setup

### Community 47 - "models.dart"
Cohesion: 0.04
Nodes (55): aliases, assignees, attachmentBacklinksByPath, AttachmentRef, attachments, backlinksByTarget, CalendarItem, CalendarItemKind (+47 more)

### Community 48 - "markdown_article_import.dart"
Cohesion: 0.04
Nodes (54): aliases, base, baseUrl, buildMarkdownArticleDraft, candidate, _canonicalDate, canonicalKeys, classifyMarkdownDuplicate (+46 more)

### Community 49 - "String"
Cohesion: 0.13
Nodes (32): AstNode, ListType, collect_plain_text(), convert_markdown(), converts_core_gfm_to_editable_typst(), converts_nested_structure_and_line_markup(), escape_markup(), escapes_typst_and_reports_unsupported_content() (+24 more)

### Community 50 - "RustLibApiImplPlatform"
Cohesion: 0.67
Nodes (4): BaseApiImpl, RustLibApiImplPlatform, RustLibApiImplPlatform, RustLibWire

### Community 51 - "workspace_controller_test.dart"
Cohesion: 0.11
Nodes (17): AndroidTreeVaultStorage, package:tylog/workspace_controller.dart, VaultStorage, calls, createDirectory, delete, _directories, exists (+9 more)

### Community 52 - "SafBridge"
Cohesion: 0.13
Nodes (12): android, MainActivity, Intent, OpenRequest, SafBridge, ByteArray, Cursor, FlutterActivity (+4 more)

### Community 53 - "RustLibWasmModule"
Cohesion: 0.67
Nodes (3): @anonymous, @JS, RustLibWasmModule

### Community 54 - "BaseWire"
Cohesion: 0.67
Nodes (3): BaseWire, RustLibWire, RustLibWire

### Community 57 - "tylog.dart"
Cohesion: 0.05
Nodes (37): 0, args, assets, command, configured, current, currentHelper, _doctor (+29 more)

### Community 58 - "search_index.dart"
Cohesion: 0.06
Nodes (31): aliases, build, buildStorage, _documents, empty, fileKind, fingerprint, frequencies (+23 more)

### Community 80 - "Research Journals as Scientific Infrastructure"
Cohesion: 0.67
Nodes (3): TyLog Sample Bibliography, Research Journals as Scientific Infrastructure, Research Journals as Scientific Infrastructure

### Community 96 - "vault_storage.dart"
Cohesion: 0.08
Nodes (25): AndroidTreeSelection, args, channel, createDirectory, delete, deleteRoot, exists, hasAccess (+17 more)

### Community 97 - "storage.dart"
Cohesion: 0.09
Nodes (22): package:crypto/crypto.dart, createDirectory, delete, exists, hash, isDirectory, list, modified (+14 more)

### Community 98 - "vault.dart"
Cohesion: 0.09
Nodes (22): bibliography, createIfMissing, directories, entries, entryCount, export, hasSettings, helper (+14 more)

### Community 99 - "tylog_core.dart"
Cohesion: 0.11
Nodes (9): src/cli_typst_inspector.dart, src/graph.dart, src/models.dart, src/report.dart, src/scanner.dart, src/search_index.dart, src/storage.dart, src/validation.dart (+1 more)

### Community 100 - "month_calendar.dart"
Cohesion: 0.12
Nodes (17): build, createState, _dayCell, _dot, index, initialMonth, initState, _iso (+9 more)

### Community 101 - "graph.dart"
Cohesion: 0.11
Nodes (17): buildLocalNoteGraph, buildNoteGraph, edges, from, frontier, full, GraphEdge, GraphNode (+9 more)

### Community 102 - "vault_storage_test.dart"
Cohesion: 0.14
Nodes (15): dart:async, package:tylog/nextcloud_sync.dart, package:tylog/vault_registry.dart, PlatformException, main, secureStore, _checkPermission, _CorruptingStorage (+7 more)

### Community 103 - "report.dart"
Cohesion: 0.12
Nodes (16): articleStatus, from, generateReportSource, kinds, output, project, ReportFilter, safe (+8 more)

### Community 104 - "markdown_import.dart"
Cohesion: 0.13
Nodes (14): BigInt?, frb_generated.dart, int get, package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart, code, convertMarkdown, diagnostics, hashCode (+6 more)

### Community 105 - "task_scheduler.dart"
Cohesion: 0.12
Nodes (16): build, createState, index, initialView, KnowledgeScreen, _KnowledgeScreenState, onOpenNote, problems (+8 more)

### Community 106 - "tylog_assets.dart"
Cohesion: 0.20
Nodes (9): _bytes, _cached, load, packageVersion, text, TylogAssets, Map, static const (+1 more)

### Community 107 - "fonts.dart"
Cohesion: 0.13
Nodes (12): app_mobile.dart, CustomPaint, EditableText, InteractiveViewer, main, package:flutter/material.dart, package:tylog/graph.dart, package:tylog/rich_editor.dart (+4 more)

### Community 108 - "bibliography.dart"
Cohesion: 0.22
Nodes (8): document, entries, HayagrivaEntry, key, parseHayagrivaBibliography, title, type, package:yaml/yaml.dart

### Community 110 - "TypstInspector"
Cohesion: 0.13
Nodes (15): FlutterTypstInspector, package:test/test.dart, package:tylog_core/tylog_core.dart, CliTypstInspector, TypstInspector, _cli, main, calls (+7 more)

### Community 111 - "platform_file_actions.dart"
Cohesion: 0.33
Nodes (5): importFile, openExternal, PlatformFileActions, package:open_file/open_file.dart, vault_storage.dart

### Community 112 - "Verifying TyLog on macOS"
Cohesion: 0.40
Nodes (4): Drive (Flutter exposes no AX tree — use raw mouse events), Gotchas, Launch, Verifying TyLog on macOS

### Community 113 - "Exception"
Cohesion: 0.40
Nodes (5): Exception, _RemoteChanged, SyncDeferred, WorkspaceSyncNotConfigured, _UsageException

### Community 116 - "CompiledDocument"
Cohesion: 0.67
Nodes (3): CompiledDocument, TypstEngine, RustOpaqueInterface

### Community 124 - "crate::api::typst::RenderResult"
Cohesion: 0.17
Nodes (10): Directory, List, models.dart, package:tylog_core/search_index.dart, package:tylog_core/validation.dart, executable, inspect, root (+2 more)

## Knowledge Gaps
- **1946 isolated node(s):** `smokeValue`, `main`, `normalized`, `value`, `json` (+1941 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **35 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `result` connect `typst.rs` to `app_mobile.dart`?**
  _High betweenness centrality (0.100) - this node is a cross-community bridge._
- **Why does `String` connect `String` to `.sse_decode`, `SseDecode`, `typst.rs`?**
  _High betweenness centrality (0.098) - this node is a cross-community bridge._
- **Why does `crate::api::typst::RenderResult` connect `core_test.dart` to `.into_dart`, `SseDecode`, `IntoDart`, `SseSerializer`?**
  _High betweenness centrality (0.015) - this node is a cross-community bridge._
- **What connects `smokeValue`, `main`, `normalized` to the rest of the system?**
  _1946 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `app_mobile.dart` be split into smaller, more focused modules?**
  _Cohesion score 0.008733624454148471 - nodes in this community are weakly interconnected._
- **Should `frb_generated.dart` be split into smaller, more focused modules?**
  _Cohesion score 0.01092896174863388 - nodes in this community are weakly interconnected._
- **Should `rich_editor.dart` be split into smaller, more focused modules?**
  _Cohesion score 0.013605442176870748 - nodes in this community are weakly interconnected._