# Graph Report - TypstSeq  (2026-08-04)

## Corpus Check
- 222 files · ~186,024 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 4543 nodes · 6223 edges · 166 communities (142 shown, 24 thin omitted)
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS · INFERRED: 17 edges (avg confidence: 0.84)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `5e3821ac`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- rich_editor.dart
- app_mobile.dart
- src/scanner.dart
- frb_generated.dart
- Nextcloud Sync Engine
- Graph View UI
- frb_generated.io.dart
- _
- Workspace Controller
- controlled_editor.dart
- Markdown Article Import
- voronoi.dart
- Note Graph Model
- voronoi_view.dart
- Nextcloud Sync Tests
- vault_registry.dart
- Self
- vault_worker.dart
- Core Data Models
- Android SAF Bridge
- Build & Release Pipeline
- work_surface.dart
- Vault Facade
- Reading Mode
- tylog.dart
- Typst Engine API
- Sync Dashboard
- Shared Widget Library
- Workspace Controller Tests
- pkms_native_test.dart
- Desktop Updater
- tylog_import_core/src/lib.rs
- IntoDart
- journal_feed.dart
- core_test.dart
- setup.dart
- State
- knowledge_screen.dart
- Core Vault Storage
- typst.rs
- Search Index
- .into_dart
- .sse_decode
- Typst View Widget
- package:flutter_test/flutter_test.dart
- Linux Runner
- dart:io
- dart:convert
- Vault Storage Abstraction
- Settings Sheet
- Notification Tests
- nextcloud_sync_native_test.dart
- Core Storage Layer
- Bibliography
- package:tylog_core/tylog_core.dart
- Typst Document Viewer
- src/vault_import.rs
- document.dart
- Editor Autocomplete
- rich_editor_native_test.dart
- Property Select Chip
- logseq_import.rs
- Scan Repro Harness
- vault_service.dart
- widget_test.dart
- Vaults Sheet
- tylog_core Exports
- Android Sync Service
- Editor Panel
- Scanner Cache Tests
- compiler.dart
- App Entry Point
- linked_references.dart
- vault_storage_test.dart
- month_calendar.dart
- Task Scheduler
- src/report.dart
- lib/report.dart
- dart:typed_data
- links_panel.dart
- Roundtrip Audit Tests
- iOS & macOS Runners
- rich_editor_test.dart
- models.dart
- api/markdown_import.dart
- macOS App Delegate
- QuickLook Preview
- IntoIntoDart
- api/vault_import.dart
- scanner_legacy_tags_test.dart
- package:tylog_core/models.dart
- macOS Window Lifecycle
- compile_pdf
- GeneratedPluginRegistrant.swift
- Dialog Helpers
- MainFlutterWindow
- QuickLook Preview Provider
- Asset Helpers
- typst_flutter.dart
- List
- Search Index Tests
- Date Formatting
- Voronoi View Tests
- _HomeScreenState
- FRB Impl Classes
- RustLib API Surface
- Voronoi Math Tests
- Exception
- return
- Vec
- String
- Vault Lookup
- FRB Platform Wire
- Custom Painters
- Markdown Result ABI
- LocalVaultStorage
- graph_label.dart
- saved_searches.dart
- Wasm Module Bindings
- Layout Messages
- Rust Wire Base
- Scanner Exports
- Integration Test Driver
- Swift Package Manifests
- Value Parsing Helpers
- Poll Tick Hook
- WebDAV Exceptions
- PKMS Validation Export
- Search Index Export
- Swift Plugin Package
- Graphify Workflow Doc
- pxpipe Cost Proxy
- Stray Mention (@bar)
- Stray Mention (@Fer)
- iOS Launch Assets
- DateTime Type Stub
- Duration Type Stub
- PageInfo Type Stub
- Generic Type Stub
- TypstSeverity Stub
- SourceLocation Stub
- dedupe_test.dart
- articles_shelf_test.dart
- static const
- platform_file_actions.dart
- package:typst_flutter/src/rust/frb_generated.dart
- dart:math
- crate::api::markdown_import::MarkdownImportDiagnostic
- crate::api::markdown_import::MarkdownTypstResult
- crate::api::typst::TypstCompileError
- Path

## God Nodes (most connected - your core abstractions)
1. `_` - 159 edges
2. `SafBridge` - 32 edges
3. `SimpleWorld` - 30 edges
4. `()` - 27 edges
5. `convert_vault_note()` - 15 edges
6. `TypstInspector` - 14 edges
7. `convert_markdown()` - 13 edges
8. `TypstRenderer` - 13 edges
9. `VaultIndex` - 12 edges
10. `extract_logseq_metadata()` - 12 edges

## Surprising Connections (you probably didn't know these)
- `tylog_core Lints Configuration` --semantically_similar_to--> `Root Analyzer Configuration`  [INFERRED] [semantically similar]
  packages/tylog_core/analysis_options.yaml → analysis_options.yaml
- `On-device Profiling (Android profile build)` --conceptually_related_to--> `Android Release Job`  [AMBIGUOUS]
  AGENTS.md → .github/workflows/release.yml
- `AndroidTreeVaultStorage` --inherits--> `VaultStorage`  [EXTRACTED]
  lib/vault_storage.dart → packages/tylog_core/lib/src/storage.dart
- `_FakeInspector` --implements--> `TypstInspector`  [EXTRACTED]
  test/workspace_controller_test.dart → packages/tylog_core/lib/src/scanner.dart
- `_MemoryStorage` --inherits--> `VaultStorage`  [EXTRACTED]
  test/workspace_controller_test.dart → packages/tylog_core/lib/src/storage.dart

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Multi-platform Release Pipeline** — _github_workflows_ci_workflow, _github_workflows_release_android_job, _github_workflows_release_linux_appimage_job, _github_workflows_release_apple_job, _github_workflows_release_publish_job [EXTRACTED 1.00]
- **TypstInspector Contract and Adapters** — docs_tylog_ecosystem_typstinspector, docs_tylog_ecosystem_fluttertypstinspector, docs_tylog_ecosystem_clitypstinspector [EXTRACTED 1.00]
- **Format v1 Shared Metadata Contract** — spec_tylog_format_v1_format_v1, typst_tylog_readme_typst_package, packages_tylog_core_pubspec_tylog_core_package, pubspec_tylog_app_package, docs_tylog_ecosystem_repository_cli [EXTRACTED 1.00]

## Communities (166 total, 24 thin omitted)

### Community 0 - "rich_editor.dart"
Cohesion: 0.01
Nodes (262): bool? mono,
  Object?, editor_autocomplete.dart, FocusNode, GlobalKey, LayerLink, atom, copyWith, document (+254 more)

### Community 1 - "app_mobile.dart"
Cohesion: 0.01
Nodes (244): bibliography.dart, DateTime? get, desktop_updater.dart, knowledge_screen.dart, _acceptRichSource, _applyMagic, _askPageTitle, _askText (+236 more)

### Community 2 - "src/scanner.dart"
Cohesion: 0.01
Nodes (193): int? modifiedMillis,
  Map, activeInspector, _add, _aliases, allProblems, attachmentBacklinks, attachmentCalls, attachments (+185 more)

### Community 3 - "frb_generated.dart"
Cohesion: 0.01
Nodes (199): ApiImplConstructor, ExternalLibraryLoaderConfig get, frb_generated.io.dart, addFonts, apiImplConstructor, codegenVersion, compile, crateApiMarkdownImportConvertMarkdown (+191 more)

### Community 4 - "Nextcloud Sync Engine"
Cohesion: 0.01
Nodes (164): InputFileStream, action, base, canSkipPoll, checkpointInterval, _client, close, config (+156 more)

### Community 5 - "Graph View UI"
Cohesion: 0.01
Nodes (142): _bannerDismissed, boundsCanvas, build, _canvas, clusterAggregates, _clusterColor, clusterCount, clustered (+134 more)

### Community 6 - "frb_generated.io.dart"
Cohesion: 0.01
Nodes (151): api/markdown_import.dart, package:flutter_rust_bridge/flutter_rust_bridge_for_generated_io.dart, dco_decode_Auto_Owned_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerCompiledDocument, dco_decode_Auto_Owned_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerTypstEngine, dco_decode_Auto_Ref_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerCompiledDocument, dco_decode_Auto_RefMut_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerTypstEngine, dco_decode_box_autoadd_i_64, dco_decode_box_autoadd_typst_source_location (+143 more)

### Community 7 - "_"
Cohesion: 0.01
Nodes (151): api/typst.dart, api/vault_import.dart, CrossPlatformFinalizerArg
  get, external RustLibWasmModule get, package:flutter_rust_bridge/flutter_rust_bridge_for_generated_web.dart, _, dco_decode_Auto_Owned_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerCompiledDocument, dco_decode_Auto_Owned_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerTypstEngine (+143 more)

### Community 8 - "Workspace Controller"
Cohesion: 0.02
Nodes (99): ChangeNotifier, Directory? get, _activeScan, _autosave, bibliographySource, cancelPendingWork, cancelRebuild, _cancelTimers (+91 more)

### Community 9 - "controlled_editor.dart"
Cohesion: 0.03
Nodes (72): action, _addBlocks, applyMagicEdit, _atMention, _balancedParenEnd, _balancedSquareEnd, _block, _blockMentions (+64 more)

### Community 10 - "Markdown Article Import"
Cohesion: 0.03
Nodes (68): aliases, base, baseUrl, builder, buildMarkdownArticleDraft, bytes, candidate, _canonicalDate (+60 more)

### Community 11 - "voronoi.dart"
Cohesion: 0.03
Nodes (69): Float64List, Int32List, a, add, avgArea, boundary, buildVoronoiRequest, byTag (+61 more)

### Community 12 - "Note Graph Model"
Cohesion: 0.03
Nodes (64): activity, addedByPath, addedDay, _addEntityNodes, adj, allDays, articles, buildConceptMap (+56 more)

### Community 13 - "voronoi_view.dart"
Cohesion: 0.03
Nodes (62): Animation, AnimationController, ColorScheme, graph.dart, abs, _animateTo, _apply, area (+54 more)

### Community 14 - "Nextcloud Sync Tests"
Cohesion: 0.03
Nodes (61): String? interruptGetOnce,
  bool, String? remoteModifiedValue,
  String, activeTransfers, archiveChanged, archiveGets, armContent, armPath, buffer (+53 more)

### Community 15 - "vault_registry.dart"
Cohesion: 0.03
Nodes (61): active, activeId, add, addTree, backupPath, candidates, cloud, completeOnboarding (+53 more)

### Community 16 - "Self"
Cohesion: 0.06
Nodes (31): bool, f32, f64, i32, i64, Option<crate::api::typst::TypstSourceLocation>, Option<crate::api::vault_import::VaultNoteResult>, Option<i64> (+23 more)

### Community 17 - "vault_worker.dart"
Cohesion: 0.03
Nodes (60): Isolate, _boot, _busy, cancel, cancelled, CancelWorkCommand, commands, communities (+52 more)

### Community 18 - "Core Data Models"
Cohesion: 0.03
Nodes (57): aliases, assignees, attachmentBacklinksByPath, AttachmentRef, attachments, backlinksByTarget, CalendarItem, CalendarItemKind (+49 more)

### Community 19 - "Android SAF Bridge"
Cohesion: 0.09
Nodes (18): android, FlutterEngine, MainActivity, Intent, T, OpenRequest, SafBridge, BackgroundSync (+10 more)

### Community 20 - "Build & Release Pipeline"
Cohesion: 0.07
Nodes (41): CI Workflow, Android Release Job, Apple (macOS/iOS) Release Job, Linux AppImage Job, GitHub Release Publish Job, Release Workflow, On-device Profiling (Android profile build), Root Analyzer Configuration (+33 more)

### Community 21 - "work_surface.dart"
Cohesion: 0.04
Nodes (44): calendar_tab.dart, _bucket, build, child, continueReadingEligible, createState, dispose, due (+36 more)

### Community 22 - "Vault Facade"
Cohesion: 0.05
Nodes (42): article, bibliographyPath, clearStaleNotes, configured, dailyNote, storage, day, defaultVaultDirectory (+34 more)

### Community 23 - "Reading Mode"
Cohesion: 0.06
Nodes (37): double get, base, build, canRate, createState, dispose, factor, fontScale (+29 more)

### Community 24 - "tylog.dart"
Cohesion: 0.03
Nodes (59): 0, apply, args, assets, aStem, bStem, command, _compareArticleOwners (+51 more)

### Community 25 - "Typst Engine API"
Cohesion: 0.06
Nodes (36): FrbException, addFonts, bytes, column, compile, CompiledDocument, diagnostics, exportPdf (+28 more)

### Community 26 - "Sync Dashboard"
Cohesion: 0.05
Nodes (36): SyncResult, backupPath, build, cloud, cloudConfigured, color, configured, conflicts (+28 more)

### Community 27 - "Shared Widget Library"
Cohesion: 0.06
Nodes (35): bool get, IconData, GraphLegend, _LegendEntry, _Avatar, _avatarPath, build, _Chips (+27 more)

### Community 28 - "Workspace Controller Tests"
Cohesion: 0.06
Nodes (35): Completer, package:tylog/workspace_controller.dart, _armed, armGate, calls, config, createDirectory, deadline (+27 more)

### Community 29 - "pkms_native_test.dart"
Cohesion: 0.10
Nodes (17): json, main, normalized, _normalizedMetadata, _normalizedValue, _stableIndex, value, package:tylog_core/cli_typst_inspector.dart (+9 more)

### Community 30 - "Desktop Updater"
Cohesion: 0.06
Nodes (35): a, appPath, at, b, build, current, downloadAndApply, exe (+27 more)

### Community 31 - "tylog_import_core/src/lib.rs"
Cohesion: 0.15
Nodes (25): AstNode, ListType, collect_plain_text(), convert_markdown(), converts_core_gfm_to_editable_typst(), converts_nested_structure_and_line_markup(), escape_markup(), escapes_typst_and_reports_unsupported_content() (+17 more)

### Community 32 - "IntoDart"
Cohesion: 0.10
Nodes (14): IntoDart, IntoDartExceptPrimitive, crate::api::typst::PageInfo, crate::api::typst::RenderResult, crate::api::typst::TypstDiagnostic, crate::api::vault_import::VaultNoteProperty, crate::api::vault_import::VaultNoteResult, FrbWrapper<CompiledDocument> (+6 more)

### Community 33 - "journal_feed.dart"
Cohesion: 0.06
Nodes (37): date_format.dart, build, CalendarTab, _CalendarTabState, createState, index, indexing, onOpenDay (+29 more)

### Community 34 - "core_test.dart"
Cohesion: 0.10
Nodes (24): FlutterTypstInspector, RecoverableInspector, TypstInspector, calls, _delegate, _EmptyInspector, _FailingInspector, _FileCapturingInspector (+16 more)

### Community 35 - "setup.dart"
Cohesion: 0.06
Nodes (35): dart:isolate, package:archive/archive_io.dart, package:path/path.dart, androidArtifacts, _Artifact, _artifactsForPlatform, body, bodyBytes (+27 more)

### Community 36 - "State"
Cohesion: 0.17
Nodes (16): TyLogApp, _TyLogAppState, SyncDashboardScreen, _SyncDashboardScreenState, _ArticlesShelf, _ArticlesShelfState, TypstDocumentViewer, _TypstDocumentViewerState (+8 more)

### Community 37 - "knowledge_screen.dart"
Cohesion: 0.06
Nodes (36): _activePreset, build, _canFix, createState, dispose, _expandedCodes, fixableCodes, _fixing (+28 more)

### Community 38 - "Core Vault Storage"
Cohesion: 0.06
Nodes (32): bibliography, createIfMissing, currentVersions, _deleteFilesShallowly, directories, entries, entryCount, export (+24 more)

### Community 39 - "typst.rs"
Cohesion: 0.08
Nodes (49): Bytes, DiagSpan, FileError, FileId, Font, FontBook, HashMap, LazyHash (+41 more)

### Community 40 - "Search Index"
Cohesion: 0.06
Nodes (30): aliases, buildStorage, _documents, empty, fileKind, fingerprint, frequencies, fromJson (+22 more)

### Community 41 - ".into_dart"
Cohesion: 0.24
Nodes (3): DartAbi, crate::api::typst::VirtualFile, VirtualFile

### Community 42 - ".sse_decode"
Cohesion: 0.21
Nodes (28): c_void, MessagePort, (), frbgen_typst_flutter_rust_arc_decrement_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerCompiledDocument(), frbgen_typst_flutter_rust_arc_decrement_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerTypstEngine(), frbgen_typst_flutter_rust_arc_increment_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerCompiledDocument(), frbgen_typst_flutter_rust_arc_increment_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerTypstEngine(), pde_ffi_dispatcher_primary_impl() (+20 more)

### Community 43 - "Typst View Widget"
Cohesion: 0.07
Nodes (26): BoxFit, package:flutter_svg/flutter_svg.dart, build, _buildWrapper, createState, didChangeDependencies, _didInit, didUpdateWidget (+18 more)

### Community 44 - "package:flutter_test/flutter_test.dart"
Cohesion: 0.10
Nodes (16): main, package:flutter_test/flutter_test.dart, package:tylog/bibliography.dart, package:tylog/editor_autocomplete.dart, package:tylog/pkms_registry.dart, package:tylog/saved_searches.dart, package:tylog/vault_storage.dart, main (+8 more)

### Community 45 - "Linux Runner"
Cohesion: 0.09
Nodes (22): FlPluginRegistry, FlView, GApplication, gboolean, gchar, GObject, GtkApplication, fl_register_plugins() (+14 more)

### Community 46 - "dart:io"
Cohesion: 0.11
Nodes (28): dart:async, dart:io, main, main, frame, main, notes, frame (+20 more)

### Community 47 - "dart:convert"
Cohesion: 0.09
Nodes (19): dart:convert, Directory, main, smokeValue, package:tylog_core/storage.dart, package:tylog/desktop_updater.dart, package:tylog/markdown_article_import.dart, package:tylog/tylog_assets.dart (+11 more)

### Community 48 - "Vault Storage Abstraction"
Cohesion: 0.08
Nodes (25): AndroidTreeSelection, args, cancelBackgroundSoon, channel, createDirectory, delete, deleteRoot, exists (+17 more)

### Community 49 - "Settings Sheet"
Cohesion: 0.08
Nodes (26): app_version.dart, NextcloudConfig, build, cloud, createState, icon, _mode, onChanged (+18 more)

### Community 50 - "Notification Tests"
Cohesion: 0.08
Nodes (24): class _FakeNotificationsPlatform extends, MockPlatformInterfaceMixin, package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart, package:plugin_platform_interface/plugin_platform_interface.dart, base, cancelAll, deadline, delete (+16 more)

### Community 51 - "nextcloud_sync_native_test.dart"
Cohesion: 0.08
Nodes (23): HttpServer, archiveGets, bytes, close, config, etag, files, filler (+15 more)

### Community 52 - "Core Storage Layer"
Cohesion: 0.08
Nodes (23): int?, package:crypto/crypto.dart, createDirectory, delete, exists, hash, isDirectory, list (+15 more)

### Community 53 - "Bibliography"
Cohesion: 0.08
Nodes (23): author, _bibFields, braceDepth, comma, document, entries, fields, first (+15 more)

### Community 54 - "package:tylog_core/tylog_core.dart"
Cohesion: 0.08
Nodes (23): package:test/test.dart, package:tylog_core/tylog_core.dart, _cli, main, index, main, _note, main (+15 more)

### Community 55 - "Typst Document Viewer"
Cohesion: 0.08
Nodes (23): package:typst_flutter/src/compiler.dart, build, _compileDocument, _compiler, createState, date, didChangeDependencies, _didInit (+15 more)

### Community 56 - "src/vault_import.rs"
Cohesion: 0.13
Nodes (33): assemble_note(), body_is_empty(), convert_logseq_note(), convert_vault_note(), ConvertedNote, converts_logseq_page_end_to_end(), converts_logseq_pipe_alias(), converts_obsidian_note_end_to_end() (+25 more)

### Community 57 - "document.dart"
Cohesion: 0.09
Nodes (21): CompiledDocument get, Image?, bytes, _cachedImage, _checkNotDisposed, _decodeImage, dispose, _disposed (+13 more)

### Community 58 - "Editor Autocomplete"
Cohesion: 0.09
Nodes (22): AutocompleteTrigger, AutocompleteTriggerKind, detectTrigger, _detectWikiLink, hashCode, id, index, _isWhitespace (+14 more)

### Community 59 - "rich_editor_native_test.dart"
Cohesion: 0.10
Nodes (21): build, controller, createState, dispose, end, errors, _initialSource, main (+13 more)

### Community 60 - "Property Select Chip"
Cohesion: 0.10
Nodes (20): Color, articleStatusLabels, articleStatusOptions, articleStatusStage, backgroundColor, build, foregroundColor, indexOf (+12 more)

### Community 61 - "logseq_import.rs"
Cohesion: 0.21
Nodes (20): Box, BTreeSet, assign_output_paths(), collect_typst_stems(), copy_assets(), main(), print_report(), Report (+12 more)

### Community 62 - "Scan Repro Harness"
Cohesion: 0.10
Nodes (20): AndroidTreeVaultStorage, VaultStorage, _CountingStorage, createDirectory, current, delete, exists, hash (+12 more)

### Community 63 - "vault_service.dart"
Cohesion: 0.14
Nodes (13): @pragma, cloud, entry, registry, _runOnce, storage, vault, vaultServiceMain (+5 more)

### Community 64 - "widget_test.dart"
Cohesion: 0.10
Nodes (20): Icon, KnowledgeView, LinearProgressIndicator, MaterialApp, package:tylog/knowledge_screen.dart, package:tylog/main.dart, SingleChildScrollView, ensureVisible (+12 more)

### Community 65 - "Vaults Sheet"
Cohesion: 0.10
Nodes (18): build, onChanged, TaskCheckbox, taskCheckedGlyph, taskUncheckedGlyph, value, activeVaultId, build (+10 more)

### Community 66 - "tylog_core Exports"
Cohesion: 0.10
Nodes (10): src/cli_typst_inspector.dart, src/graph.dart, src/models.dart, src/report.dart, src/scanner.dart, src/search_index.dart, src/storage.dart, src/validation.dart (+2 more)

### Community 67 - "Android Sync Service"
Cohesion: 0.16
Nodes (10): Context, Intent, Notification, start(), stop(), SyncForegroundService, update(), IBinder (+2 more)

### Community 68 - "Editor Panel"
Cohesion: 0.11
Nodes (18): build, controller, createState, dispose, _DockButton, Editor, EditorState, focusNode (+10 more)

### Community 69 - "Scanner Cache Tests"
Cohesion: 0.11
Nodes (18): createDirectory, delete, exists, hash, hashes, inner, inspect, inspected (+10 more)

### Community 70 - "compiler.dart"
Cohesion: 0.15
Nodes (12): dart:ffi, Finalizable, package:typst_flutter/src/document.dart, package:typst_flutter/src/exceptions.dart, package:typst_flutter/src/rust/api/typst.dart, compile, create, _dateTimeToSysTime (+4 more)

### Community 71 - "App Entry Point"
Cohesion: 0.12
Nodes (13): app_mobile.dart, double?, main, iconForKind, listTileRadius, structuralNoteKinds, build, LoadingIndicator (+5 more)

### Community 72 - "linked_references.dart"
Cohesion: 0.11
Nodes (18): constants.dart, ../controlled_editor.dart, Future, backlinks, build, createState, _expanded, index (+10 more)

### Community 73 - "vault_storage_test.dart"
Cohesion: 0.10
Nodes (18): checkpointEvery, main, paths, appVersion, package:flutter/services.dart, package:tylog/nextcloud_sync.dart, PlatformException, main (+10 more)

### Community 74 - "month_calendar.dart"
Cohesion: 0.12
Nodes (17): build, createState, _dayCell, _dot, index, initialMonth, initState, _iso (+9 more)

### Community 75 - "Task Scheduler"
Cohesion: 0.12
Nodes (16): hash, initial, initialize, nextTaskReminder, plugin, problems, reconcile, requestPermission (+8 more)

### Community 76 - "src/report.dart"
Cohesion: 0.11
Nodes (17): articleStatus, from, generateReportSource, includeZotero, kinds, output, project, ReportFilter (+9 more)

### Community 77 - "lib/report.dart"
Cohesion: 0.12
Nodes (14): class, _compiler, create, dispose, inspect, recover, compiler, compileSourcePdf (+6 more)

### Community 78 - "dart:typed_data"
Cohesion: 0.12
Nodes (13): CustomPaint, dart:typed_data, InteractiveViewer, package:tylog/graph.dart, package:typst_flutter/src/widgets/typst_view.dart, main, RenderBox, _dist (+5 more)

### Community 79 - "links_panel.dart"
Cohesion: 0.12
Nodes (15): backlinks, build, current, dayItems, _EmptyHint, fileRefs, index, LinksPanel (+7 more)

### Community 80 - "Roundtrip Audit Tests"
Cohesion: 0.12
Nodes (15): checkEdits, checkIdentity, cursor, editByPattern, editExample, editRevert, editTried, _esc (+7 more)

### Community 81 - "iOS & macOS Runners"
Cohesion: 0.16
Nodes (9): BackgroundTasks, Flutter, FlutterSceneDelegate, SceneDelegate, RunnerTests, RunnerTests, UIKit, XCTest (+1 more)

### Community 82 - "rich_editor_test.dart"
Cohesion: 0.09
Nodes (19): EditableText, EditableTextState, package:flutter/foundation.dart, package:flutter/rendering.dart, package:tylog/controlled_editor.dart, package:tylog/rich_editor.dart, package:tylog/task_scheduler.dart, random note with no (+11 more)

### Community 83 - "models.dart"
Cohesion: 0.10
Nodes (19): models.dart, CliTypstInspector, executable, inspect, root, count, _duplicates, isSafeVaultPath (+11 more)

### Community 84 - "api/markdown_import.dart"
Cohesion: 0.13
Nodes (14): BigInt?, frb_generated.dart, int get, package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart, code, convertMarkdown, diagnostics, hashCode (+6 more)

### Community 85 - "macOS App Delegate"
Cohesion: 0.22
Nodes (8): Any, BGProcessingTask, FlutterImplicitEngineBridge, FlutterImplicitEngineDelegate, AppDelegate, Bool, FlutterEngine, UIApplication

### Community 86 - "QuickLook Preview"
Cohesion: 0.24
Nodes (8): Error, CompileError, PreviewProvider, Data, QLFilePreviewRequest, QLPreviewingController, QLPreviewProvider, QLPreviewReply

### Community 87 - "IntoIntoDart"
Cohesion: 0.13
Nodes (8): FrbWrapper, IntoIntoDart, CompiledDocument, crate::api::typst::TypstSeverity, crate::api::typst::TypstSourceLocation, TypstSeverity, TypstSourceLocation, TypstEngine

### Community 88 - "api/vault_import.dart"
Cohesion: 0.09
Nodes (21): aliases, convertVaultNote, date, diagnostics, droppedBlockRefs, hashCode, id, key (+13 more)

### Community 89 - "scanner_legacy_tags_test.dart"
Cohesion: 0.18
Nodes (10): _FailingInspector, inspect, main, scan, _staleCacheTests, _synonymFileTests, synonyms, _synonymTests (+2 more)

### Community 90 - "package:tylog_core/models.dart"
Cohesion: 0.13
Nodes (12): package:tylog/app_mobile.dart, package:tylog_core/models.dart, main, _task, today, _article, body, main (+4 more)

### Community 91 - "macOS Window Lifecycle"
Cohesion: 0.27
Nodes (6): FlutterAppDelegate, AppDelegate, Bool, Notification, NSApplication, NSStatusItem

### Community 92 - "compile_pdf"
Cohesion: 0.38
Nodes (8): c_char, compile_pdf(), Result, Vec, string_to_c(), typst_ql_compile_pdf(), typst_ql_free_string(), TypstQlFile

### Community 93 - "GeneratedPluginRegistrant.swift"
Cohesion: 0.20
Nodes (8): Cocoa, file_picker, flutter_local_notifications, flutter_secure_storage_darwin, flutter_timezone, FlutterMacOS, share_plus, url_launcher_macos

### Community 94 - "Dialog Helpers"
Cohesion: 0.20
Nodes (9): barrierDismissible, cancelLabel, confirmed, confirmLabel, destructive, false, showConfirmDialog, required String message,
  String (+1 more)

### Community 95 - "MainFlutterWindow"
Cohesion: 0.29
Nodes (6): FlutterPluginRegistry, RegisterGeneratedPlugins(), MainFlutterWindow, Bool, NSWindow, NSWindowDelegate

### Community 96 - "QuickLook Preview Provider"
Cohesion: 0.28
Nodes (7): Decodable, Foundation, Storage, Vault, VaultsFile, QuickLookUI, UniformTypeIdentifiers

### Community 97 - "Asset Helpers"
Cohesion: 0.22
Nodes (8): _bytes, _cached, load, text, TylogAssets, Map, package:flutter/widgets.dart, static Future

### Community 98 - "typst_flutter.dart"
Cohesion: 0.18
Nodes (10): src/compiler.dart, src/document.dart, src/exceptions.dart, src/markdown_import.dart, src/rust/api/markdown_import.dart, src/rust/api/typst.dart, src/rust/api/vault_import.dart, src/vault_import.dart (+2 more)

### Community 99 - "List"
Cohesion: 0.32
Nodes (7): List, diagnostics, message, toString, TypstCompileException, TypstException, TypstRenderException

### Community 100 - "Search Index Tests"
Cohesion: 0.25
Nodes (7): _buildIndex, buildStorage, main, _note, notesDir, storage, vault

### Community 101 - "Date Formatting"
Cohesion: 0.29
Nodes (6): compactHumanDate, humanDate, isoDay, label, _monthNames, _weekdayNames

### Community 102 - "Voronoi View Tests"
Cohesion: 0.29
Nodes (6): package:tylog/voronoi_view.dart, communities, host, index, main, _note

### Community 103 - "_HomeScreenState"
Cohesion: 0.29
Nodes (7): HomeScreen, _HomeScreenState, _DesktopUpdateFlow, _MarkdownImportFlow, _VaultImportFlow, _VaultLifecycle, WidgetsBindingObserver

### Community 104 - "FRB Impl Classes"
Cohesion: 0.40
Nodes (6): @sealed, CompiledDocument, CompiledDocumentImpl, TypstEngineImpl, RustOpaque, TypstEngine

### Community 105 - "RustLib API Surface"
Cohesion: 0.40
Nodes (6): BaseApi, BaseEntrypoint, RustLib, RustLibApi, RustLibApiImpl, RustLibApiImplPlatform

### Community 106 - "Voronoi Math Tests"
Cohesion: 0.40
Nodes (5): GraphView, _GraphViewState, VoronoiView, _VoronoiViewState, SingleTickerProviderStateMixin

### Community 107 - "Exception"
Cohesion: 0.29
Nodes (7): Exception, UpdateNotWritable, _RemoteChanged, SyncDeferred, WorkspaceSyncNotConfigured, _UsageException, IndexBuildCancelled

### Community 108 - "return"
Cohesion: 0.33
Nodes (5): changed, syncStatusAction, SyncStatusKind, syncStatusTitle, return

### Community 109 - "Vec"
Cohesion: 0.18
Nodes (20): Fn, asset_basename(), drop_block_refs(), extract_tasks(), image_destination(), is_relative_image(), parse_priority(), preprocess() (+12 more)

### Community 110 - "String"
Cohesion: 0.16
Nodes (18): parse_frontmatter(), Result, sanitize_title(), typst_string(), typst_tuple(), yaml_scalar(), convert_markdown(), MarkdownImportDiagnostic (+10 more)

### Community 111 - "Vault Lookup"
Cohesion: 0.50
Nodes (3): Data, URL, VaultLookup

### Community 112 - "FRB Platform Wire"
Cohesion: 0.67
Nodes (4): BaseApiImpl, RustLibApiImplPlatform, RustLibApiImplPlatform, RustLibWire

### Community 113 - "Custom Painters"
Cohesion: 0.50
Nodes (4): CustomPainter, GraphPainter, _SwatchPainter, _VoronoiPainter

### Community 114 - "Markdown Result ABI"
Cohesion: 0.40
Nodes (5): NextcloudSync, _PathSync, _SyncConflicts, _SyncStatePersistence, _WebDavClient

### Community 115 - "LocalVaultStorage"
Cohesion: 0.40
Nodes (5): LocalVaultStorage, _CheckpointCountingStorage, _HashCountingStorage, _MidSyncWriteStorage, _LatencyStorage

### Community 116 - "graph_label.dart"
Cohesion: 0.11
Nodes (16): dart:ui, budget, countLine, fontSize, GraphLabelSpec, kGraphCountAlpha, kGraphCountScale, maxLines (+8 more)

### Community 117 - "saved_searches.dart"
Cohesion: 0.12
Nodes (16): _castString, fromJson, hashCode, load, name, operator, _path, query (+8 more)

### Community 118 - "Wasm Module Bindings"
Cohesion: 0.67
Nodes (3): @anonymous, @JS, RustLibWasmModule

### Community 119 - "Layout Messages"
Cohesion: 0.67
Nodes (3): @immutable, ClusterAgg, LayoutRequest

### Community 120 - "Rust Wire Base"
Cohesion: 0.67
Nodes (3): BaseWire, RustLibWire, RustLibWire

### Community 156 - "dedupe_test.dart"
Cohesion: 0.13
Nodes (13): File, _cli, file, files, main, _note, _snapshot, _write (+5 more)

### Community 157 - "articles_shelf_test.dart"
Cohesion: 0.22
Nodes (8): package:tylog/widgets/property_select_chip.dart, package:tylog/widgets/work_surface.dart, main, plainNote, reading, shelf, summarized, unread

### Community 158 - "static const"
Cohesion: 0.25
Nodes (7): acquire, heldByOther, path, release, staleAfter, VaultLock, static const

### Community 159 - "platform_file_actions.dart"
Cohesion: 0.29
Nodes (6): importPlatformFile, openPlatformFile, uri, writeBytes, package:url_launcher/url_launcher.dart, vault_storage.dart

### Community 160 - "package:typst_flutter/src/rust/frb_generated.dart"
Cohesion: 0.29
Nodes (5): package:typst_flutter/src/rust/api/markdown_import.dart, package:typst_flutter/src/rust/api/vault_import.dart, package:typst_flutter/src/rust/frb_generated.dart, convertMarkdown, convertVaultNote

### Community 161 - "dart:math"
Cohesion: 0.33
Nodes (5): dart:math, _index, main, _note, unitSquare

## Ambiguous Edges - Review These
- `Android Release Job` → `On-device Profiling (Android profile build)`  [AMBIGUOUS]
  AGENTS.md · relation: conceptually_related_to

## Knowledge Gaps
- **3246 isolated node(s):** `smokeValue`, `main`, `_NativeRemoteFile`, `_NativeWebDavServer`, `filler` (+3241 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **24 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **What is the exact relationship between `Android Release Job` and `On-device Profiling (Android profile build)`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._
- **Why does `_` connect `_` to `frb_generated.io.dart`, `dart:io`, `dart:convert`, `FRB Platform Wire`, `api/markdown_import.dart`, `Wasm Module Bindings`, `Rust Wire Base`?**
  _High betweenness centrality (0.072) - this node is a cross-community bridge._
- **Why does `VaultIndex` connect `journal_feed.dart` to `knowledge_screen.dart`, `linked_references.dart`, `Workspace Controller`, `month_calendar.dart`, `voronoi_view.dart`, `links_panel.dart`, `vault_worker.dart`, `Core Data Models`, `work_surface.dart`, `tylog.dart`?**
  _High betweenness centrality (0.008) - this node is a cross-community bridge._
- **Why does `String` connect `String` to `typst.rs`, `Vec`, `Self`, `src/vault_import.rs`, `compile_pdf`, `logseq_import.rs`, `tylog_import_core/src/lib.rs`?**
  _High betweenness centrality (0.006) - this node is a cross-community bridge._
- **What connects `smokeValue`, `main`, `_NativeRemoteFile` to the rest of the system?**
  _3246 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `rich_editor.dart` be split into smaller, more focused modules?**
  _Cohesion score 0.0076045627376425855 - nodes in this community are weakly interconnected._
- **Should `app_mobile.dart` be split into smaller, more focused modules?**
  _Cohesion score 0.00816326530612245 - nodes in this community are weakly interconnected._