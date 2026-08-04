# Graph Report - TypstSeq  (2026-08-03)

## Corpus Check
- 209 files · ~172,121 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 4237 nodes · 5677 edges · 156 communities (134 shown, 22 thin omitted)
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS · INFERRED: 15 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `81860554`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- Rich Text Editor
- Mobile App Shell
- Vault Scanner & Index
- FRB Generated Bindings
- Nextcloud Sync Engine
- Graph View UI
- FRB IO Codec
- FRB Web Codec
- Workspace Controller
- Magic Edit Engine
- Markdown Article Import
- Voronoi Layout Core
- Note Graph Model
- Voronoi View UI
- Nextcloud Sync Tests
- Vault Registry
- Rust SSE Codec
- Vault Worker & Scheduler
- Core Data Models
- Android SAF Bridge
- Build & Release Pipeline
- Work Surface UI
- Vault Facade
- Reading Mode
- TyLog CLI
- Typst Engine API
- Sync Dashboard
- Shared Widget Library
- Workspace Controller Tests
- Widget Test Suite
- Desktop Updater
- Rust Markdown Converter
- Rust-Dart ABI Glue
- Calendar & Journal Feed
- Typst Inspector Contract
- Native Artifact Setup
- App Screen States
- Knowledge Screen
- Core Vault Storage
- Rust Typst Compiler
- Search Index
- Rust SSE Encoders
- Rust SSE Decoders
- Typst View Widget
- Integration Tests
- Linux Runner
- Vault Worker Tests
- Import & JSON Tests
- Vault Storage Abstraction
- Settings Sheet
- Notification Tests
- Sync Native Tests
- Core Storage Layer
- Bibliography
- Core Test Utilities
- Typst Document Viewer
- Rust Typst World
- Typst Document Model
- Editor Autocomplete
- Editor Native Tests
- Property Select Chip
- Rust Engine Internals
- Scan Repro Harness
- Vault Service
- Widget Smoke Tests
- Vaults Sheet
- tylog_core Exports
- Android Sync Service
- Editor Panel
- Scanner Cache Tests
- Typst Compiler Wrapper
- App Entry Point
- Linked References
- Storage & Audit Tests
- Month Calendar
- Task Scheduler
- Report Core
- Report UI
- Graph Layout Tests
- Links Panel
- Roundtrip Audit Tests
- iOS & macOS Runners
- Editor Widget Tests
- Vault Validation
- Markdown Import Bindings
- macOS App Delegate
- QuickLook Preview
- Rust PageInfo ABI
- Native Vault Tests
- Registry & Attribution Tests
- Model Edge-Case Tests
- macOS Window Lifecycle
- QuickLook FFI
- macOS Plugin Registrant
- Dialog Helpers
- macOS Flutter Window
- QuickLook Preview Provider
- Asset Helpers
- typst_flutter Exports
- Typst Exceptions
- Search Index Tests
- Date Formatting
- Voronoi View Tests
- Release Machinery Tests
- FRB Impl Classes
- RustLib API Surface
- Voronoi Math Tests
- Sync Exceptions
- Sync Status Model
- CLI Typst Inspector
- Markdown Import Result
- Vault Lookup
- FRB Platform Wire
- Custom Painters
- Markdown Result ABI
- Storage Test Doubles
- RenderResult ABI
- Diagnostic ABI
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

## God Nodes (most connected - your core abstractions)
1. `_` - 143 edges
2. `SafBridge` - 32 edges
3. `SimpleWorld` - 30 edges
4. `()` - 26 edges
5. `TypstInspector` - 13 edges
6. `TypstRenderer` - 13 edges
7. `VaultIndex` - 12 edges
8. `convert_markdown()` - 12 edges
9. `CompiledDocument` - 12 edges
10. `SyncForegroundService` - 11 edges

## Surprising Connections (you probably didn't know these)
- `tylog_core Lints Configuration` --semantically_similar_to--> `Root Analyzer Configuration`  [INFERRED] [semantically similar]
  packages/tylog_core/analysis_options.yaml → analysis_options.yaml
- `_LatencyStorage` --inherits--> `LocalVaultStorage`  [EXTRACTED]
  test/search_index_saf_latency_test.dart → packages/tylog_core/lib/src/storage.dart
- `On-device Profiling (Android profile build)` --conceptually_related_to--> `Android Release Job`  [AMBIGUOUS]
  AGENTS.md → .github/workflows/release.yml
- `AndroidTreeVaultStorage` --inherits--> `VaultStorage`  [EXTRACTED]
  lib/vault_storage.dart → packages/tylog_core/lib/src/storage.dart
- `_FakeInspector` --implements--> `TypstInspector`  [EXTRACTED]
  test/workspace_controller_test.dart → packages/tylog_core/lib/src/scanner.dart

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Multi-platform Release Pipeline** — _github_workflows_ci_workflow, _github_workflows_release_android_job, _github_workflows_release_linux_appimage_job, _github_workflows_release_apple_job, _github_workflows_release_publish_job [EXTRACTED 1.00]
- **TypstInspector Contract and Adapters** — docs_tylog_ecosystem_typstinspector, docs_tylog_ecosystem_fluttertypstinspector, docs_tylog_ecosystem_clitypstinspector [EXTRACTED 1.00]
- **Format v1 Shared Metadata Contract** — spec_tylog_format_v1_format_v1, typst_tylog_readme_typst_package, packages_tylog_core_pubspec_tylog_core_package, pubspec_tylog_app_package, docs_tylog_ecosystem_repository_cli [EXTRACTED 1.00]

## Communities (156 total, 22 thin omitted)

### Community 0 - "Rich Text Editor"
Cohesion: 0.01
Nodes (258): bool? mono,
  Object?, editor_autocomplete.dart, FocusNode, GlobalKey, LayerLink, atom, copyWith, document (+250 more)

### Community 1 - "Mobile App Shell"
Cohesion: 0.01
Nodes (217): bibliography.dart, DateTime? get, desktop_updater.dart, knowledge_screen.dart, _acceptRichSource, _applyMagic, _askPageTitle, _askText (+209 more)

### Community 2 - "Vault Scanner & Index"
Cohesion: 0.01
Nodes (192): int? modifiedMillis,
  Map, activeInspector, _add, _aliases, allProblems, attachmentBacklinks, attachmentCalls, attachments (+184 more)

### Community 3 - "FRB Generated Bindings"
Cohesion: 0.01
Nodes (182): ApiImplConstructor, ExternalLibraryLoaderConfig get, frb_generated.io.dart, addFonts, apiImplConstructor, codegenVersion, compile, crateApiMarkdownImportConvertMarkdown (+174 more)

### Community 4 - "Nextcloud Sync Engine"
Cohesion: 0.01
Nodes (164): InputFileStream, action, base, canSkipPoll, checkpointInterval, _client, close, config (+156 more)

### Community 5 - "Graph View UI"
Cohesion: 0.01
Nodes (142): _bannerDismissed, boundsCanvas, build, _canvas, clusterAggregates, _clusterColor, clusterCount, clustered (+134 more)

### Community 6 - "FRB IO Codec"
Cohesion: 0.01
Nodes (136): CrossPlatformFinalizerArg
  get, package:flutter_rust_bridge/flutter_rust_bridge_for_generated_io.dart, dco_decode_Auto_Owned_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerCompiledDocument, dco_decode_Auto_Owned_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerTypstEngine, dco_decode_Auto_Ref_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerCompiledDocument, dco_decode_Auto_RefMut_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerTypstEngine, dco_decode_box_autoadd_i_64, dco_decode_box_autoadd_typst_source_location (+128 more)

### Community 7 - "FRB Web Codec"
Cohesion: 0.01
Nodes (135): api/markdown_import.dart, api/typst.dart, external RustLibWasmModule get, package:flutter_rust_bridge/flutter_rust_bridge_for_generated_web.dart, _, dco_decode_Auto_Owned_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerCompiledDocument, dco_decode_Auto_Owned_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerTypstEngine, dco_decode_Auto_Ref_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerCompiledDocument (+127 more)

### Community 8 - "Workspace Controller"
Cohesion: 0.02
Nodes (99): ChangeNotifier, Directory? get, _activeScan, _autosave, bibliographySource, cancelPendingWork, cancelRebuild, _cancelTimers (+91 more)

### Community 9 - "Magic Edit Engine"
Cohesion: 0.03
Nodes (71): action, _addBlocks, applyMagicEdit, _atMention, _balancedParenEnd, _balancedSquareEnd, _block, _blockMentions (+63 more)

### Community 10 - "Markdown Article Import"
Cohesion: 0.03
Nodes (68): aliases, base, baseUrl, builder, buildMarkdownArticleDraft, bytes, candidate, _canonicalDate (+60 more)

### Community 11 - "Voronoi Layout Core"
Cohesion: 0.03
Nodes (67): Float64List, graph.dart, Int32List, a, add, avgArea, boundary, buildVoronoiRequest (+59 more)

### Community 12 - "Note Graph Model"
Cohesion: 0.03
Nodes (64): activity, addedByPath, addedDay, _addEntityNodes, adj, allDays, articles, buildConceptMap (+56 more)

### Community 13 - "Voronoi View UI"
Cohesion: 0.03
Nodes (61): Animation, AnimationController, ColorScheme, abs, _animateTo, _apply, area, _areaOf (+53 more)

### Community 14 - "Nextcloud Sync Tests"
Cohesion: 0.03
Nodes (61): String? interruptGetOnce,
  bool, String? remoteModifiedValue,
  String, activeTransfers, archiveChanged, archiveGets, armContent, armPath, buffer (+53 more)

### Community 15 - "Vault Registry"
Cohesion: 0.03
Nodes (60): active, activeId, add, addTree, backupPath, candidates, cloud, completeOnboarding (+52 more)

### Community 16 - "Rust SSE Codec"
Cohesion: 0.06
Nodes (29): bool, f32, f64, i32, i64, Option<crate::api::typst::TypstSourceLocation>, Option<i64>, Option<std::collections::HashMap<String, String>> (+21 more)

### Community 17 - "Vault Worker & Scheduler"
Cohesion: 0.04
Nodes (59): Isolate, VaultEntry, _boot, _busy, cancel, cancelled, CancelWorkCommand, commands (+51 more)

### Community 18 - "Core Data Models"
Cohesion: 0.03
Nodes (57): aliases, assignees, attachmentBacklinksByPath, AttachmentRef, attachments, backlinksByTarget, CalendarItem, CalendarItemKind (+49 more)

### Community 19 - "Android SAF Bridge"
Cohesion: 0.09
Nodes (18): android, FlutterEngine, MainActivity, Intent, T, OpenRequest, SafBridge, BackgroundSync (+10 more)

### Community 20 - "Build & Release Pipeline"
Cohesion: 0.07
Nodes (41): CI Workflow, Android Release Job, Apple (macOS/iOS) Release Job, Linux AppImage Job, GitHub Release Publish Job, Release Workflow, On-device Profiling (Android profile build), Root Analyzer Configuration (+33 more)

### Community 21 - "Work Surface UI"
Cohesion: 0.05
Nodes (43): calendar_tab.dart, _bucket, build, child, createState, dispose, due, editor (+35 more)

### Community 22 - "Vault Facade"
Cohesion: 0.05
Nodes (42): article, bibliographyPath, clearStaleNotes, configured, dailyNote, storage, day, defaultVaultDirectory (+34 more)

### Community 23 - "Reading Mode"
Cohesion: 0.06
Nodes (37): double get, base, build, canRate, createState, dispose, factor, fontScale (+29 more)

### Community 24 - "TyLog CLI"
Cohesion: 0.05
Nodes (37): 0, args, assets, command, configured, current, currentHelper, _doctor (+29 more)

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

### Community 29 - "Widget Test Suite"
Cohesion: 0.06
Nodes (28): json, main, normalized, _normalizedMetadata, _normalizedValue, _stableIndex, value, package:flutter/foundation.dart (+20 more)

### Community 30 - "Desktop Updater"
Cohesion: 0.06
Nodes (35): a, appPath, at, b, build, current, downloadAndApply, exe (+27 more)

### Community 31 - "Rust Markdown Converter"
Cohesion: 0.17
Nodes (26): AstNode, ListType, collect_plain_text(), convert_markdown(), converts_core_gfm_to_editable_typst(), converts_nested_structure_and_line_markup(), escape_markup(), escapes_typst_and_reports_unsupported_content() (+18 more)

### Community 32 - "Rust-Dart ABI Glue"
Cohesion: 0.10
Nodes (14): IntoDart, IntoDartExceptPrimitive, MarkdownImportDiagnostic, crate::api::markdown_import::MarkdownImportDiagnostic, crate::api::typst::PageInfo, crate::api::typst::TypstCompileError, crate::api::typst::TypstDiagnostic, crate::api::typst::TypstSeverity (+6 more)

### Community 33 - "Calendar & Journal Feed"
Cohesion: 0.08
Nodes (24): _bootstrapping, build, createState, _days, didUpdateWidget, dispose, _extentAtGrow, _growing (+16 more)

### Community 34 - "Typst Inspector Contract"
Cohesion: 0.10
Nodes (24): FlutterTypstInspector, RecoverableInspector, TypstInspector, calls, _delegate, _FailingInspector, _FileCapturingInspector, fileKeys (+16 more)

### Community 35 - "Native Artifact Setup"
Cohesion: 0.06
Nodes (34): package:archive/archive_io.dart, package:path/path.dart, androidArtifacts, _Artifact, _artifactsForPlatform, body, bodyBytes, client (+26 more)

### Community 36 - "App Screen States"
Cohesion: 0.16
Nodes (18): _NativeMagicHarness, _NativeMagicHarnessState, TyLogApp, _TyLogAppState, SyncDashboardScreen, _SyncDashboardScreenState, _ArticlesShelf, _ArticlesShelfState (+10 more)

### Community 37 - "Knowledge Screen"
Cohesion: 0.06
Nodes (32): build, _canFix, createState, dispose, _expandedCodes, fixableCodes, _fixing, _fixLabel (+24 more)

### Community 38 - "Core Vault Storage"
Cohesion: 0.06
Nodes (32): bibliography, createIfMissing, currentVersions, _deleteFilesShallowly, directories, entries, entryCount, export (+24 more)

### Community 39 - "Rust Typst Compiler"
Cohesion: 0.13
Nodes (23): DiagSpan, CompiledDocument, get_typst_version(), map_diagnostic(), map_errors(), PageInfo, RenderResult, resolve_span() (+15 more)

### Community 40 - "Search Index"
Cohesion: 0.06
Nodes (30): aliases, buildStorage, _documents, empty, fileKind, fingerprint, frequencies, fromJson (+22 more)

### Community 41 - "Rust SSE Encoders"
Cohesion: 0.26
Nodes (3): DartAbi, crate::api::typst::VirtualFile, VirtualFile

### Community 42 - "Rust SSE Decoders"
Cohesion: 0.21
Nodes (27): c_void, MessagePort, (), frbgen_typst_flutter_rust_arc_decrement_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerCompiledDocument(), frbgen_typst_flutter_rust_arc_decrement_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerTypstEngine(), frbgen_typst_flutter_rust_arc_increment_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerCompiledDocument(), frbgen_typst_flutter_rust_arc_increment_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerTypstEngine(), pde_ffi_dispatcher_primary_impl() (+19 more)

### Community 43 - "Typst View Widget"
Cohesion: 0.07
Nodes (26): BoxFit, package:flutter_svg/flutter_svg.dart, build, _buildWrapper, createState, didChangeDependencies, _didInit, didUpdateWidget (+18 more)

### Community 44 - "Integration Tests"
Cohesion: 0.09
Nodes (19): dart:isolate, main, package:flutter_test/flutter_test.dart, package:tylog/bibliography.dart, package:tylog/editor_autocomplete.dart, package:tylog/pkms_registry.dart, package:tylog/scanner.dart, package:tylog/vault_storage.dart (+11 more)

### Community 45 - "Linux Runner"
Cohesion: 0.09
Nodes (22): FlPluginRegistry, FlView, GApplication, gboolean, gchar, GObject, GtkApplication, fl_register_plugins() (+14 more)

### Community 46 - "Vault Worker Tests"
Cohesion: 0.12
Nodes (24): main, frame, main, notes, frame, main, notes, seed (+16 more)

### Community 47 - "Import & JSON Tests"
Cohesion: 0.07
Nodes (31): dart:convert, dart:io, dart:typed_data, main, smokeValue, main, compiler, compileSourcePdf (+23 more)

### Community 48 - "Vault Storage Abstraction"
Cohesion: 0.08
Nodes (25): AndroidTreeSelection, args, cancelBackgroundSoon, channel, createDirectory, delete, deleteRoot, exists (+17 more)

### Community 49 - "Settings Sheet"
Cohesion: 0.08
Nodes (26): app_version.dart, NextcloudConfig, build, cloud, createState, icon, _mode, onChanged (+18 more)

### Community 50 - "Notification Tests"
Cohesion: 0.08
Nodes (24): class _FakeNotificationsPlatform extends, MockPlatformInterfaceMixin, package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart, package:plugin_platform_interface/plugin_platform_interface.dart, base, cancelAll, deadline, delete (+16 more)

### Community 51 - "Sync Native Tests"
Cohesion: 0.06
Nodes (30): HttpServer, archiveGets, bytes, close, config, etag, files, filler (+22 more)

### Community 52 - "Core Storage Layer"
Cohesion: 0.08
Nodes (23): int?, package:crypto/crypto.dart, createDirectory, delete, exists, hash, isDirectory, list (+15 more)

### Community 53 - "Bibliography"
Cohesion: 0.08
Nodes (23): author, _bibFields, braceDepth, comma, document, entries, fields, first (+15 more)

### Community 54 - "Core Test Utilities"
Cohesion: 0.09
Nodes (20): dart:math, package:test/test.dart, package:tylog_core/tylog_core.dart, index, main, _note, main, _repairTests (+12 more)

### Community 55 - "Typst Document Viewer"
Cohesion: 0.08
Nodes (23): package:typst_flutter/src/compiler.dart, build, _compileDocument, _compiler, createState, date, didChangeDependencies, _didInit (+15 more)

### Community 56 - "Rust Typst World"
Cohesion: 0.15
Nodes (14): Bytes, Font, FontBook, HashMap, LazyHash, Library, Datetime, Duration (+6 more)

### Community 57 - "Typst Document Model"
Cohesion: 0.09
Nodes (22): CompiledDocument get, dart:ui, Image?, bytes, _cachedImage, _checkNotDisposed, _decodeImage, dispose (+14 more)

### Community 58 - "Editor Autocomplete"
Cohesion: 0.09
Nodes (22): AutocompleteTrigger, AutocompleteTriggerKind, detectTrigger, _detectWikiLink, hashCode, id, index, _isWhitespace (+14 more)

### Community 59 - "Editor Native Tests"
Cohesion: 0.06
Nodes (32): EditableText, EditableTextState, build, controller, createState, dispose, end, errors (+24 more)

### Community 60 - "Property Select Chip"
Cohesion: 0.10
Nodes (20): Color, articleStatusLabels, articleStatusOptions, articleStatusStage, backgroundColor, build, foregroundColor, indexOf (+12 more)

### Community 61 - "Rust Engine Internals"
Cohesion: 0.20
Nodes (13): FileError, FileId, project_rooted_fileid_resolution_unchanged(), resolves_package_rooted_fileid_via_name_version_key(), Result, Self, test_export_svg_out_of_bounds(), test_query() (+5 more)

### Community 62 - "Scan Repro Harness"
Cohesion: 0.10
Nodes (20): AndroidTreeVaultStorage, VaultStorage, _CountingStorage, createDirectory, current, delete, exists, hash (+12 more)

### Community 63 - "Vault Service"
Cohesion: 0.10
Nodes (18): @pragma, importPlatformFile, openPlatformFile, uri, writeBytes, cloud, entry, registry (+10 more)

### Community 64 - "Widget Smoke Tests"
Cohesion: 0.06
Nodes (28): Icon, checkpointEvery, main, paths, KnowledgeView, appVersion, LinearProgressIndicator, MaterialApp (+20 more)

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

### Community 70 - "Typst Compiler Wrapper"
Cohesion: 0.12
Nodes (15): dart:ffi, Finalizable, package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart, package:typst_flutter/src/document.dart, package:typst_flutter/src/exceptions.dart, package:typst_flutter/src/rust/api/markdown_import.dart, package:typst_flutter/src/rust/frb_generated.dart, compile (+7 more)

### Community 71 - "App Entry Point"
Cohesion: 0.12
Nodes (13): app_mobile.dart, double?, main, iconForKind, listTileRadius, structuralNoteKinds, build, LoadingIndicator (+5 more)

### Community 72 - "Linked References"
Cohesion: 0.12
Nodes (17): ../controlled_editor.dart, Future, backlinks, build, createState, _expanded, index, kind (+9 more)

### Community 73 - "Storage & Audit Tests"
Cohesion: 0.13
Nodes (15): dart:async, File, _bucketError, l, line, main, _checkPermission, _CorruptingStorage (+7 more)

### Community 74 - "Month Calendar"
Cohesion: 0.11
Nodes (18): build, createState, _dayCell, _dot, index, initialMonth, initState, _iso (+10 more)

### Community 75 - "Task Scheduler"
Cohesion: 0.12
Nodes (16): hash, initial, initialize, nextTaskReminder, plugin, problems, reconcile, requestPermission (+8 more)

### Community 76 - "Report Core"
Cohesion: 0.12
Nodes (16): articleStatus, from, generateReportSource, includeZotero, kinds, output, project, ReportFilter (+8 more)

### Community 77 - "Report UI"
Cohesion: 0.29
Nodes (6): class, _compiler, create, dispose, inspect, recover

### Community 78 - "Graph Layout Tests"
Cohesion: 0.17
Nodes (10): CustomPaint, InteractiveViewer, package:tylog/graph.dart, RenderBox, _dist, dx, dy, main (+2 more)

### Community 79 - "Links Panel"
Cohesion: 0.12
Nodes (16): constants.dart, backlinks, build, current, dayItems, _EmptyHint, fileRefs, index (+8 more)

### Community 80 - "Roundtrip Audit Tests"
Cohesion: 0.12
Nodes (15): checkEdits, checkIdentity, cursor, editByPattern, editExample, editRevert, editTried, _esc (+7 more)

### Community 81 - "iOS & macOS Runners"
Cohesion: 0.16
Nodes (9): BackgroundTasks, Flutter, FlutterSceneDelegate, SceneDelegate, RunnerTests, RunnerTests, UIKit, XCTest (+1 more)

### Community 82 - "Editor Widget Tests"
Cohesion: 0.15
Nodes (13): date_format.dart, build, CalendarTab, _CalendarTabState, createState, index, indexing, onOpenDay (+5 more)

### Community 83 - "Vault Validation"
Cohesion: 0.13
Nodes (14): count, _duplicates, isSafeVaultPath, listing, owners, PkmsValidationReport, presentPaths, priorities (+6 more)

### Community 84 - "Markdown Import Bindings"
Cohesion: 0.14
Nodes (13): BigInt?, frb_generated.dart, int get, code, convertMarkdown, diagnostics, hashCode, line (+5 more)

### Community 85 - "macOS App Delegate"
Cohesion: 0.22
Nodes (8): Any, BGProcessingTask, FlutterImplicitEngineBridge, FlutterImplicitEngineDelegate, AppDelegate, Bool, FlutterEngine, UIApplication

### Community 86 - "QuickLook Preview"
Cohesion: 0.24
Nodes (8): Error, CompileError, PreviewProvider, Data, QLFilePreviewRequest, QLPreviewingController, QLPreviewProvider, QLPreviewReply

### Community 87 - "Rust PageInfo ABI"
Cohesion: 0.17
Nodes (6): FrbWrapper, IntoIntoDart, MarkdownTypstResult, CompiledDocument, crate::api::markdown_import::MarkdownTypstResult, TypstEngine

### Community 88 - "Native Vault Tests"
Cohesion: 0.18
Nodes (9): _cli, main, calls, _fallbackTasksFor, _fieldFrom, main, note, return (+1 more)

### Community 89 - "Registry & Attribution Tests"
Cohesion: 0.20
Nodes (9): inspect, main, scan, _staleCacheTests, _synonymFileTests, synonyms, _synonymTests, vault (+1 more)

### Community 90 - "Model Edge-Case Tests"
Cohesion: 0.18
Nodes (9): package:tylog/app_mobile.dart, package:tylog_core/models.dart, main, _task, today, _article, body, main (+1 more)

### Community 91 - "macOS Window Lifecycle"
Cohesion: 0.27
Nodes (6): FlutterAppDelegate, AppDelegate, Bool, Notification, NSApplication, NSStatusItem

### Community 92 - "QuickLook FFI"
Cohesion: 0.38
Nodes (8): c_char, compile_pdf(), Result, Vec, string_to_c(), typst_ql_compile_pdf(), typst_ql_free_string(), TypstQlFile

### Community 93 - "macOS Plugin Registrant"
Cohesion: 0.20
Nodes (8): file_picker, flutter_local_notifications, flutter_secure_storage_darwin, flutter_timezone, FlutterPluginRegistry, RegisterGeneratedPlugins(), share_plus, url_launcher_macos

### Community 94 - "Dialog Helpers"
Cohesion: 0.20
Nodes (9): barrierDismissible, cancelLabel, confirmed, confirmLabel, destructive, false, showConfirmDialog, required String message,
  String (+1 more)

### Community 95 - "macOS Flutter Window"
Cohesion: 0.28
Nodes (6): Cocoa, FlutterMacOS, MainFlutterWindow, Bool, NSWindow, NSWindowDelegate

### Community 96 - "QuickLook Preview Provider"
Cohesion: 0.28
Nodes (7): Decodable, Foundation, Storage, Vault, VaultsFile, QuickLookUI, UniformTypeIdentifiers

### Community 97 - "Asset Helpers"
Cohesion: 0.22
Nodes (8): _bytes, _cached, load, text, TylogAssets, Map, package:flutter/widgets.dart, static Future

### Community 98 - "typst_flutter Exports"
Cohesion: 0.22
Nodes (8): src/compiler.dart, src/document.dart, src/exceptions.dart, src/markdown_import.dart, src/rust/api/markdown_import.dart, src/rust/api/typst.dart, src/widgets/typst_document_viewer.dart, src/widgets/typst_view.dart

### Community 99 - "Typst Exceptions"
Cohesion: 0.28
Nodes (8): List, package:typst_flutter/src/rust/api/typst.dart, diagnostics, message, toString, TypstCompileException, TypstException, TypstRenderException

### Community 100 - "Search Index Tests"
Cohesion: 0.25
Nodes (7): _buildIndex, buildStorage, main, _note, notesDir, storage, vault

### Community 101 - "Date Formatting"
Cohesion: 0.29
Nodes (6): compactHumanDate, humanDate, isoDay, label, _monthNames, _weekdayNames

### Community 102 - "Voronoi View Tests"
Cohesion: 0.29
Nodes (6): package:tylog/voronoi_view.dart, communities, host, index, main, _note

### Community 103 - "Release Machinery Tests"
Cohesion: 0.33
Nodes (6): HomeScreen, _HomeScreenState, _DesktopUpdateFlow, _MarkdownImportFlow, _VaultLifecycle, WidgetsBindingObserver

### Community 104 - "FRB Impl Classes"
Cohesion: 0.40
Nodes (6): @sealed, CompiledDocument, CompiledDocumentImpl, TypstEngineImpl, RustOpaque, TypstEngine

### Community 105 - "RustLib API Surface"
Cohesion: 0.40
Nodes (6): BaseApi, BaseEntrypoint, RustLib, RustLibApi, RustLibApiImpl, RustLibApiImplPlatform

### Community 106 - "Voronoi Math Tests"
Cohesion: 0.40
Nodes (5): GraphView, _GraphViewState, VoronoiView, _VoronoiViewState, SingleTickerProviderStateMixin

### Community 107 - "Sync Exceptions"
Cohesion: 0.33
Nodes (6): Exception, UpdateNotWritable, _RemoteChanged, SyncDeferred, WorkspaceSyncNotConfigured, _UsageException

### Community 108 - "Sync Status Model"
Cohesion: 0.33
Nodes (5): changed, syncStatusAction, SyncStatusKind, syncStatusTitle, nextcloud_sync.dart

### Community 109 - "CLI Typst Inspector"
Cohesion: 0.29
Nodes (6): Directory, CliTypstInspector, executable, inspect, root, scanner.dart

### Community 110 - "Markdown Import Result"
Cohesion: 0.53
Nodes (5): convert_markdown(), MarkdownImportDiagnostic, MarkdownTypstResult, Option, Vec

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

### Community 115 - "Storage Test Doubles"
Cohesion: 0.50
Nodes (4): LocalVaultStorage, _CheckpointCountingStorage, _HashCountingStorage, _MidSyncWriteStorage

### Community 118 - "Wasm Module Bindings"
Cohesion: 0.67
Nodes (3): @anonymous, @JS, RustLibWasmModule

### Community 119 - "Layout Messages"
Cohesion: 0.67
Nodes (3): @immutable, ClusterAgg, LayoutRequest

### Community 120 - "Rust Wire Base"
Cohesion: 0.67
Nodes (3): BaseWire, RustLibWire, RustLibWire

## Ambiguous Edges - Review These
- `Android Release Job` → `On-device Profiling (Android profile build)`  [AMBIGUOUS]
  AGENTS.md · relation: conceptually_related_to

## Knowledge Gaps
- **3071 isolated node(s):** `smokeValue`, `main`, `_NativeRemoteFile`, `_NativeWebDavServer`, `filler` (+3066 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **22 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **What is the exact relationship between `Android Release Job` and `On-device Profiling (Android profile build)`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._
- **Why does `_` connect `FRB Web Codec` to `FRB IO Codec`, `Storage & Audit Tests`, `Import & JSON Tests`, `FRB Platform Wire`, `Markdown Import Bindings`, `Wasm Module Bindings`, `Rust Wire Base`?**
  _High betweenness centrality (0.071) - this node is a cross-community bridge._
- **Why does `VaultIndex` connect `Month Calendar` to `Calendar & Journal Feed`, `Knowledge Screen`, `Linked References`, `Workspace Controller`, `Voronoi View UI`, `Links Panel`, `Vault Worker & Scheduler`, `Editor Widget Tests`, `Core Data Models`, `Work Surface UI`, `TyLog CLI`?**
  _High betweenness centrality (0.008) - this node is a cross-community bridge._
- **Why does `ClusterAgg` connect `Layout Messages` to `Graph View UI`?**
  _High betweenness centrality (0.004) - this node is a cross-community bridge._
- **What connects `smokeValue`, `main`, `_NativeRemoteFile` to the rest of the system?**
  _3071 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Rich Text Editor` be split into smaller, more focused modules?**
  _Cohesion score 0.007722007722007722 - nodes in this community are weakly interconnected._
- **Should `Mobile App Shell` be split into smaller, more focused modules?**
  _Cohesion score 0.009174311926605505 - nodes in this community are weakly interconnected._