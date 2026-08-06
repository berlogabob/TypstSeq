# Graph Report - .  (2026-08-06)

## Corpus Check
- 75 files · ~198,534 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 4787 nodes · 6569 edges · 197 communities (157 shown, 40 thin omitted)
- Extraction: 99% EXTRACTED · 1% INFERRED · 0% AMBIGUOUS · INFERRED: 37 edges (avg confidence: 0.87)
- Token cost: 81,171 input · 0 output

## Community Hubs (Navigation)
- Rich Editor Widgets
- Mobile App Shell
- Vault Scanner & Writer
- FRB Bindings (Dart)
- Nextcloud Sync
- FRB Codecs (Native)
- FRB Codecs (Web)
- Graph View
- Workspace Controller
- FRB Bindings (Rust)
- Controlled Editor
- Typst Compile Engine
- Core Models & Clock Entries
- Voronoi Layout
- Markdown Article Import
- Vault Worker Isolate
- Knowledge Graph Builder
- Voronoi View
- Vault Registry
- Sync Tests
- TyLog CLI
- Logseq Vault Import
- Android SAF Bridge
- Knowledge & Problems Screen
- Vault Facade
- Work Surface
- Native & Entity Tests
- Markdown to Typst Converter
- Journal & Calendar Feed
- Reading Mode
- Sync Attribution Test
- Sync Dashboard
- Entity Header
- Workspace Controller Test
- Setup
- Desktop Updater
- Editor Autocomplete
- Vault
- Vault Import
- Search Index
- Vault Worker
- Frb Generated
- Links Panel
- Frb Generated
- Typst
- Dialogs
- Settings Sheet
- Typst View
- Journal Feed Test
- My Application
- Vault Storage
- Widget Test
- Core Test
- Nextcloud Sync Native Test
- Storage
- Bibliography
- Typst Document Viewer
- Rich Editor Test
- Document
- Rich Editor Native Test
- Vault Import
- Logseq Import
- Property Select Chip
- Graph Layout Test
- Graph Label
- Package Release Machinery Test
- Cli Typst Inspector
- Release
- SyncForegroundService
- Frb Generated
- Month Calendar
- Scanner Cache Test
- Linked References
- Saved Searches
- README
- Task Scheduler
- Editor Panel
- Report
- Scan Repro
- Report
- Editor Widgets
- Roundtrip Audit Test
- Tylog Format V1
- Dedupe Test
- Frb Generated
- Validation
- Vault Service
- Markdown Import
- AppDelegate
- Compiler
- RunnerTests
- RunnerTests
- Tylog Format V1
- PreviewProvider
- Tylog Assets
- Markdown Import
- AppDelegate
- Scanner Task Mutation Test
- Scanner Legacy Tags Test
- Typst Flutter
- Quicklook Ffi
- Pubspec
- Tylog Ecosystem
- Tylog Ecosystem
- GeneratedPluginRegistrant
- VaultLookup
- Agenda Filter Test
- Vault Storage Test
- Articles Shelf Test
- Vault Lock
- Task Checkbox
- Today Page Test
- Exceptions
- Search Index Test
- Nextcloud Sync
- App Mobile
- Platform File Actions
- Date Format
- Voronoi View Test
- Markdown Import
- Frb Generated
- Frb Generated
- Frb Generated
- Sync Status
- Cli Typst Inspector
- Setup Typst Native
- Graph
- Nextcloud Sync
- Frb Generated
- Frb Generated
- Frb Generated
- Relink Strip Test
- Frb Generated Io
- Graph
- Graph Label Test
- VaultLookup
- Vault Storage
- CMakeLists
- Nextcloud Sync Test
- PLAN
- USER MANUAL
- Analysis Options
- Frb Generated Web
- Graph
- Frb Generated Io
- Integration Test
- Package
- Values
- Workspace Controller
- Nextcloud Sync
- Knowledge Screen
- Knowledge Screen
- Pkms Registry
- Search Index
- TypstFlutter
- Editing Controller
- Assert Source Built
- AGENTS
- AGENTS
- Unsourced Nodes
- Unsourced Nodes
- README
- Unsourced Nodes
- Unsourced Nodes
- Unsourced Nodes
- Unsourced Nodes
- Unsourced Nodes
- Unsourced Nodes
- Unsourced Nodes
- Pubspec
- Unsourced Nodes
- Unsourced Nodes
- Unsourced Nodes
- Unsourced Nodes
- Unsourced Nodes
- Unsourced Nodes
- Unsourced Nodes
- Unsourced Nodes
- Unsourced Nodes
- Unsourced Nodes
- Unsourced Nodes
- Unsourced Nodes

## God Nodes (most connected - your core abstractions)
1. `_` - 159 edges
2. `SafBridge` - 32 edges
3. `SimpleWorld` - 30 edges
4. `()` - 27 edges
5. `convert_logseq_note()` - 18 edges
6. `preprocess()` - 17 edges
7. `convert_vault_note()` - 15 edges
8. `extract_logseq_metadata()` - 15 edges
9. `extract_tasks()` - 15 edges
10. `TypstInspector` - 14 edges

## Surprising Connections (you probably didn't know these)
- `make verify Release Gate` --semantically_similar_to--> `Release Workflow`  [INFERRED] [semantically similar]
  README.md → .github/workflows/release.yml
- `Safe Fallback Source Parser` --semantically_similar_to--> `Refuse to Ship a Downloaded Native Library`  [INFERRED] [semantically similar]
  docs/tylog-ecosystem.md → .github/workflows/release.yml
- `On-device Profiling (Android profile build)` --conceptually_related_to--> `Android Release Job`  [AMBIGUOUS]
  AGENTS.md → .github/workflows/release.yml
- `tylog_core Lints Configuration` --semantically_similar_to--> `Root Analyzer Configuration`  [INFERRED] [semantically similar]
  packages/tylog_core/analysis_options.yaml → analysis_options.yaml
- `Voronoi Treemap View` --shares_data_with--> `tylog_core (Flutter-independent core)`  [INFERRED]
  USER_MANUAL.md → docs/tylog-ecosystem.md

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Format v1 Metadata Pipeline (vault to derived index)** — docs_tylog_ecosystem_vault, docs_tylog_ecosystem_typst_package, docs_tylog_ecosystem_format_v1_metadata, docs_tylog_ecosystem_typstinspector, docs_tylog_ecosystem_tylog_core, spec_tylog_format_v1_query_metadata [EXTRACTED 1.00]
- **Dual-Runtime TypstInspector Contract Parity** — docs_tylog_ecosystem_typstinspector, docs_tylog_ecosystem_fluttertypstinspector, docs_tylog_ecosystem_clitypstinspector, docs_tylog_ecosystem_native_integration_test, docs_tylog_ecosystem_fallback_parser [EXTRACTED 1.00]
- **Release Artifact Integrity Gates (silent-failure defenses)** — _github_workflows_release_refuse_downloaded_native_library, _github_workflows_release_bundle_framework_gate, _github_workflows_release_fail_on_unmatched_files, _github_workflows_release_assert_source_built_sh, _github_workflows_release_disable_swift_package_manager [EXTRACTED 1.00]

## Communities (197 total, 40 thin omitted)

### Community 0 - "Rich Editor Widgets"
Cohesion: 0.01
Nodes (276): bool? mono,
  Object?, editor_autocomplete.dart, FocusNode, GlobalKey, LayerLink, atom, copyWith, document (+268 more)

### Community 1 - "Mobile App Shell"
Cohesion: 0.01
Nodes (255): bibliography.dart, DateTime? get, desktop_updater.dart, EditorState, knowledge_screen.dart, _acceptRichSource, _applyMagic, _askPageTitle (+247 more)

### Community 2 - "Vault Scanner & Writer"
Cohesion: 0.01
Nodes (229): int? modifiedMillis,
  Map, activeInspector, _add, _aliases, allProblems, _appendDictEntry, _appendTaskField, attachmentBacklinks (+221 more)

### Community 3 - "FRB Bindings (Dart)"
Cohesion: 0.01
Nodes (199): ApiImplConstructor, ExternalLibraryLoaderConfig get, frb_generated.io.dart, addFonts, apiImplConstructor, codegenVersion, compile, crateApiMarkdownImportConvertMarkdown (+191 more)

### Community 4 - "Nextcloud Sync"
Cohesion: 0.01
Nodes (169): InputFileStream, action, base, canSkipPoll, checkpointInterval, _client, close, config (+161 more)

### Community 5 - "FRB Codecs (Native)"
Cohesion: 0.01
Nodes (151): CrossPlatformFinalizerArg
  get, package:flutter_rust_bridge/flutter_rust_bridge_for_generated_io.dart, dco_decode_Auto_Owned_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerCompiledDocument, dco_decode_Auto_Owned_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerTypstEngine, dco_decode_Auto_Ref_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerCompiledDocument, dco_decode_Auto_RefMut_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerTypstEngine, dco_decode_box_autoadd_i_64, dco_decode_box_autoadd_typst_source_location (+143 more)

### Community 6 - "FRB Codecs (Web)"
Cohesion: 0.01
Nodes (151): api/markdown_import.dart, api/typst.dart, api/vault_import.dart, external RustLibWasmModule get, package:flutter_rust_bridge/flutter_rust_bridge_for_generated_web.dart, _, dco_decode_Auto_Owned_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerCompiledDocument, dco_decode_Auto_Owned_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerTypstEngine (+143 more)

### Community 7 - "Graph View"
Cohesion: 0.01
Nodes (144): GraphEdgeKind, _bannerDismissed, boundsCanvas, build, _canvas, clusterAggregates, _clusterColor, clusterCount (+136 more)

### Community 8 - "Workspace Controller"
Cohesion: 0.02
Nodes (99): ChangeNotifier, Directory? get, _activeScan, _autosave, bibliographySource, cancelPendingWork, cancelRebuild, _cancelTimers (+91 more)

### Community 9 - "FRB Bindings (Rust)"
Cohesion: 0.06
Nodes (31): bool, f32, f64, i32, i64, Option<crate::api::typst::TypstSourceLocation>, Option<crate::api::vault_import::VaultNoteResult>, Option<i64> (+23 more)

### Community 10 - "Controlled Editor"
Cohesion: 0.03
Nodes (75): action, _addBlocks, applyMagicEdit, _atMention, _balancedParenEnd, _balancedSquareEnd, _block, _blockMentions (+67 more)

### Community 11 - "Typst Compile Engine"
Cohesion: 0.08
Nodes (50): Bytes, DiagSpan, FileError, FileId, Font, FontBook, LazyHash, Library (+42 more)

### Community 12 - "Core Models & Clock Entries"
Cohesion: 0.03
Nodes (71): ClockEntry? get, Duration get, aliases, assignees, attachmentBacklinksByPath, AttachmentRef, attachments, backlinksByTarget (+63 more)

### Community 13 - "Voronoi Layout"
Cohesion: 0.03
Nodes (69): Float64List, Int32List, a, add, avgArea, boundary, buildVoronoiRequest, byTag (+61 more)

### Community 14 - "Markdown Article Import"
Cohesion: 0.03
Nodes (67): aliases, base, baseUrl, builder, buildMarkdownArticleDraft, bytes, candidate, _canonicalDate (+59 more)

### Community 15 - "Vault Worker Isolate"
Cohesion: 0.03
Nodes (64): FlutterTypstInspector?, Isolate, _boot, _busy, cancel, cancelled, CancelWorkCommand, commands (+56 more)

### Community 16 - "Knowledge Graph Builder"
Cohesion: 0.03
Nodes (64): activity, addedByPath, addedDay, _addEntityNodes, adj, allDays, articles, buildConceptMap (+56 more)

### Community 17 - "Voronoi View"
Cohesion: 0.03
Nodes (63): Animation, AnimationController, ColorScheme, CommunityMap, graph.dart, abs, _animateTo, _apply (+55 more)

### Community 18 - "Vault Registry"
Cohesion: 0.03
Nodes (61): active, activeId, add, addTree, backupPath, candidates, cloud, completeOnboarding (+53 more)

### Community 19 - "Sync Tests"
Cohesion: 0.03
Nodes (61): String? interruptGetOnce,
  bool, String? remoteModifiedValue,
  String, activeTransfers, archiveChanged, archiveGets, armContent, armPath, buffer (+53 more)

### Community 20 - "TyLog CLI"
Cohesion: 0.03
Nodes (59): 0, apply, args, assets, aStem, bStem, command, _compareArticleOwners (+51 more)

### Community 21 - "Logseq Vault Import"
Cohesion: 0.09
Nodes (53): HashMap, assemble_note(), body_is_empty(), collect_same_file_blocks(), convert_logseq_note(), convert_vault_note(), ConvertedNote, converts_logseq_highlights() (+45 more)

### Community 22 - "Android SAF Bridge"
Cohesion: 0.09
Nodes (18): android, FlutterEngine, MainActivity, Intent, T, OpenRequest, SafBridge, BackgroundSync (+10 more)

### Community 23 - "Knowledge & Problems Screen"
Cohesion: 0.04
Nodes (51): _activePreset, build, byTarget, _canFix, capitalised, count, createState, defaultKindForTarget (+43 more)

### Community 24 - "Vault Facade"
Cohesion: 0.04
Nodes (45): flutter_typst_inspector.dart, article, bibliographyPath, clearStaleNotes, configured, dailyNote, day, defaultVaultDirectory (+37 more)

### Community 25 - "Work Surface"
Cohesion: 0.04
Nodes (44): calendar_tab.dart, _bucket, build, child, continueReadingEligible, createState, dispose, due (+36 more)

### Community 26 - "Native & Entity Tests"
Cohesion: 0.06
Nodes (31): json, main, normalized, _normalizedMetadata, _normalizedValue, _stableIndex, value, main (+23 more)

### Community 27 - "Markdown to Typst Converter"
Cohesion: 0.13
Nodes (30): AstNode, ListType, collect_inline_text(), collect_plain_text(), convert_markdown(), converts_allowlisted_inline_html_and_drops_other_tags(), converts_core_gfm_to_editable_typst(), converts_nested_structure_and_line_markup() (+22 more)

### Community 28 - "Journal & Calendar Feed"
Cohesion: 0.06
Nodes (38): date_format.dart, Vault, build, CalendarTab, _CalendarTabState, createState, index, indexing (+30 more)

### Community 29 - "Reading Mode"
Cohesion: 0.05
Nodes (39): DateTime, double get, base, build, canRate, createState, dispose, factor (+31 more)

### Community 30 - "Sync Attribution Test"
Cohesion: 0.07
Nodes (28): dart:convert, dart:io, Directory, main, smokeValue, main, checkpointEvery, main (+20 more)

### Community 31 - "Sync Dashboard"
Cohesion: 0.05
Nodes (36): SyncResult, backupPath, build, cloud, cloudConfigured, color, configured, conflicts (+28 more)

### Community 32 - "Entity Header"
Cohesion: 0.06
Nodes (35): bool get, IconData, GraphLegend, _LegendEntry, _Avatar, _avatarPath, build, _Chips (+27 more)

### Community 33 - "Workspace Controller Test"
Cohesion: 0.06
Nodes (35): Completer, package:tylog/workspace_controller.dart, _armed, armGate, calls, config, createDirectory, deadline (+27 more)

### Community 34 - "Setup"
Cohesion: 0.06
Nodes (35): dart:isolate, package:archive/archive_io.dart, package:path/path.dart, androidArtifacts, _Artifact, _artifactsForPlatform, body, bodyBytes (+27 more)

### Community 35 - "Desktop Updater"
Cohesion: 0.06
Nodes (35): a, appPath, at, b, build, current, downloadAndApply, exe (+27 more)

### Community 36 - "Editor Autocomplete"
Cohesion: 0.06
Nodes (33): AutocompleteTrigger, AutocompleteTriggerKind, create, detectTrigger, _detectWikiLink, hashCode, id, index (+25 more)

### Community 37 - "Vault"
Cohesion: 0.06
Nodes (32): bibliography, createIfMissing, currentVersions, _deleteFilesShallowly, directories, entries, entryCount, export (+24 more)

### Community 38 - "Vault Import"
Cohesion: 0.13
Nodes (32): Fn, asset_basename(), drop_block_refs(), extend_unique(), extract_highlights(), extract_math(), image_destination(), is_image_path() (+24 more)

### Community 39 - "Search Index"
Cohesion: 0.06
Nodes (30): aliases, buildStorage, _documents, empty, fileKind, fingerprint, frequencies, fromJson (+22 more)

### Community 40 - "Vault Worker"
Cohesion: 0.13
Nodes (24): dart:async, main, frame, main, notes, frame, main, notes (+16 more)

### Community 41 - "Frb Generated"
Cohesion: 0.21
Nodes (28): c_void, MessagePort, (), frbgen_typst_flutter_rust_arc_decrement_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerCompiledDocument(), frbgen_typst_flutter_rust_arc_decrement_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerTypstEngine(), frbgen_typst_flutter_rust_arc_increment_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerCompiledDocument(), frbgen_typst_flutter_rust_arc_increment_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerTypstEngine(), pde_ffi_dispatcher_primary_impl() (+20 more)

### Community 42 - "Links Panel"
Cohesion: 0.07
Nodes (27): constants.dart, backlinks, build, current, dayItems, _EmptyHint, fileRefs, index (+19 more)

### Community 43 - "Frb Generated"
Cohesion: 0.10
Nodes (14): IntoDart, IntoDartExceptPrimitive, MarkdownImportDiagnostic, PageInfo, RenderResult, TypstSeverity, crate::api::markdown_import::MarkdownImportDiagnostic, crate::api::typst::PageInfo (+6 more)

### Community 44 - "Typst"
Cohesion: 0.07
Nodes (28): addFonts, bytes, column, compile, CompiledDocument, diagnostics, exportPdf, exportSvg (+20 more)

### Community 45 - "Dialogs"
Cohesion: 0.07
Nodes (22): app_mobile.dart, double?, main, iconForKind, listTileRadius, structuralNoteKinds, barrierDismissible, cancelLabel (+14 more)

### Community 46 - "Settings Sheet"
Cohesion: 0.08
Nodes (26): app_version.dart, NextcloudConfig, build, cloud, createState, icon, _mode, onChanged (+18 more)

### Community 47 - "Typst View"
Cohesion: 0.07
Nodes (26): BoxFit, package:flutter_svg/flutter_svg.dart, build, _buildWrapper, createState, didChangeDependencies, _didInit, didUpdateWidget (+18 more)

### Community 48 - "Journal Feed Test"
Cohesion: 0.08
Nodes (26): class _FakeNotificationsPlatform extends, Duration, MockPlatformInterfaceMixin, package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart, package:plugin_platform_interface/plugin_platform_interface.dart, package:tylog/widgets/journal_feed.dart, base, cancelAll (+18 more)

### Community 49 - "My Application"
Cohesion: 0.09
Nodes (22): FlPluginRegistry, FlView, GApplication, gboolean, gchar, GObject, GtkApplication, fl_register_plugins() (+14 more)

### Community 50 - "Vault Storage"
Cohesion: 0.08
Nodes (25): AndroidTreeSelection, args, cancelBackgroundSoon, channel, createDirectory, delete, deleteRoot, exists (+17 more)

### Community 51 - "Widget Test"
Cohesion: 0.08
Nodes (23): Icon, KnowledgeView, LinearProgressIndicator, MaterialApp, package:tylog/knowledge_screen.dart, package:tylog/main.dart, SingleChildScrollView, _broken (+15 more)

### Community 52 - "Core Test"
Cohesion: 0.10
Nodes (24): FlutterTypstInspector, RecoverableInspector, TypstInspector, calls, _delegate, _EmptyInspector, _FailingInspector, _FileCapturingInspector (+16 more)

### Community 53 - "Nextcloud Sync Native Test"
Cohesion: 0.08
Nodes (23): HttpServer, archiveGets, bytes, close, config, etag, files, filler (+15 more)

### Community 54 - "Storage"
Cohesion: 0.08
Nodes (23): int?, package:crypto/crypto.dart, createDirectory, delete, exists, hash, isDirectory, list (+15 more)

### Community 55 - "Bibliography"
Cohesion: 0.08
Nodes (23): author, _bibFields, braceDepth, comma, document, entries, fields, first (+15 more)

### Community 56 - "Typst Document Viewer"
Cohesion: 0.08
Nodes (23): package:typst_flutter/src/compiler.dart, build, _compileDocument, _compiler, createState, date, didChangeDependencies, _didInit (+15 more)

### Community 57 - "Rich Editor Test"
Cohesion: 0.09
Nodes (20): EditableText, EditableTextState, package:flutter/foundation.dart, package:flutter/rendering.dart, package:tylog/controlled_editor.dart, package:tylog/rich_editor.dart, package:tylog/task_scheduler.dart, random note with no (+12 more)

### Community 58 - "Document"
Cohesion: 0.09
Nodes (21): CompiledDocument get, Image?, bytes, _cachedImage, _checkNotDisposed, _decodeImage, dispose, _disposed (+13 more)

### Community 59 - "Rich Editor Native Test"
Cohesion: 0.10
Nodes (21): build, controller, createState, dispose, end, errors, _initialSource, main (+13 more)

### Community 60 - "Vault Import"
Cohesion: 0.09
Nodes (21): aliases, convertVaultNote, date, diagnostics, droppedBlockRefs, hashCode, id, key (+13 more)

### Community 61 - "Logseq Import"
Cohesion: 0.22
Nodes (19): Box, BTreeSet, assign_output_paths(), collect_typst_stems(), copy_assets(), main(), print_report(), Report (+11 more)

### Community 62 - "Property Select Chip"
Cohesion: 0.10
Nodes (20): Color, articleStatusLabels, articleStatusOptions, articleStatusStage, backgroundColor, build, foregroundColor, indexOf (+12 more)

### Community 63 - "Graph Layout Test"
Cohesion: 0.10
Nodes (17): CustomPaint, dart:typed_data, InteractiveViewer, package:tylog/graph.dart, package:typst_flutter/src/widgets/typst_view.dart, LocalVaultStorage, main, RenderBox (+9 more)

### Community 64 - "Graph Label"
Cohesion: 0.10
Nodes (18): dart:math, budget, countLine, fontSize, GraphLabelSpec, kGraphCountAlpha, kGraphCountScale, maxLines (+10 more)

### Community 65 - "Package Release Machinery Test"
Cohesion: 0.12
Nodes (15): package:test/test.dart, package:tylog_core/tylog_core.dart, index, main, _note, main, _repairTests, _currentHelper (+7 more)

### Community 66 - "Cli Typst Inspector"
Cohesion: 0.10
Nodes (10): src/cli_typst_inspector.dart, src/graph.dart, src/models.dart, src/report.dart, src/scanner.dart, src/search_index.dart, src/storage.dart, src/validation.dart (+2 more)

### Community 67 - "Release"
Cohesion: 0.16
Nodes (19): Android Release Job, Apple (macOS/iOS) Release Job, assert_source_built.sh, macOS Bundle Framework Gate, CI Workflow (reused test job), Force CocoaPods over Swift Package Manager, fail_on_unmatched_files Release Gate, flutter_rust_bridge Content Hash Check (+11 more)

### Community 68 - "SyncForegroundService"
Cohesion: 0.16
Nodes (10): Context, Intent, Notification, start(), stop(), SyncForegroundService, update(), IBinder (+2 more)

### Community 69 - "Frb Generated"
Cohesion: 0.24
Nodes (3): DartAbi, VirtualFile, crate::api::typst::VirtualFile

### Community 70 - "Month Calendar"
Cohesion: 0.11
Nodes (18): build, createState, _dayCell, _dot, index, initialMonth, initState, _iso (+10 more)

### Community 71 - "Scanner Cache Test"
Cohesion: 0.11
Nodes (18): createDirectory, delete, exists, hash, hashes, inner, inspect, inspected (+10 more)

### Community 72 - "Linked References"
Cohesion: 0.12
Nodes (17): controlled_editor.dart, Future, backlinks, build, createState, _expanded, index, kind (+9 more)

### Community 73 - "Saved Searches"
Cohesion: 0.11
Nodes (17): _castString, fromJson, hashCode, load, name, operator, _path, query (+9 more)

### Community 74 - "README"
Cohesion: 0.17
Nodes (17): Safe Fallback Source Parser, Repository CLI (bin/tylog.dart), tylog_core (Flutter-independent core), TyLog v5 Vault, Clean Schema-v5 Vault, Application Graph Report, TyLog Ecosystem (four components), JSON Limited to Non-Durable State (+9 more)

### Community 75 - "Task Scheduler"
Cohesion: 0.12
Nodes (16): hash, initial, initialize, nextTaskReminder, plugin, problems, reconcile, requestPermission (+8 more)

### Community 76 - "Editor Panel"
Cohesion: 0.12
Nodes (16): build, controller, createState, dispose, _DockButton, Editor, EditorState, focusNode (+8 more)

### Community 77 - "Report"
Cohesion: 0.12
Nodes (16): articleStatus, from, generateReportSource, includeZotero, kinds, output, project, ReportFilter (+8 more)

### Community 78 - "Scan Repro"
Cohesion: 0.12
Nodes (16): createDirectory, current, delete, exists, hash, index, inner, last (+8 more)

### Community 79 - "Report"
Cohesion: 0.12
Nodes (14): class, _compiler, create, dispose, inspect, recover, compiler, compileSourcePdf (+6 more)

### Community 80 - "Editor Widgets"
Cohesion: 0.17
Nodes (16): TyLogApp, _TyLogAppState, SyncDashboardScreen, _SyncDashboardScreenState, _ArticlesShelf, _ArticlesShelfState, TypstDocumentViewer, _TypstDocumentViewerState (+8 more)

### Community 81 - "Roundtrip Audit Test"
Cohesion: 0.12
Nodes (15): checkEdits, checkIdentity, cursor, editByPattern, editExample, editRevert, editTried, _esc (+7 more)

### Community 82 - "Tylog Format V1"
Cohesion: 0.14
Nodes (15): Vault Generation 5 Compatibility Contract, Deferred P2 Platform Work, Deliberate Scope Limits, No Automatic Pre-v5 Vault Migration, clocked Time-Tracking Property, Date Record (<tylog-date>), TyLog Format v1, Legacy Generation-5 Value Compatibility (+7 more)

### Community 83 - "Dedupe Test"
Cohesion: 0.13
Nodes (13): File, _cli, file, files, main, _note, _snapshot, _write (+5 more)

### Community 84 - "Frb Generated"
Cohesion: 0.17
Nodes (6): FrbWrapper, IntoIntoDart, TypstSourceLocation, CompiledDocument, crate::api::typst::TypstSourceLocation, TypstEngine

### Community 85 - "Validation"
Cohesion: 0.13
Nodes (14): count, _duplicates, isSafeVaultPath, listing, owners, PkmsValidationReport, presentPaths, priorities (+6 more)

### Community 86 - "Vault Service"
Cohesion: 0.14
Nodes (13): @pragma, cloud, entry, registry, _runOnce, storage, vault, vaultServiceMain (+5 more)

### Community 87 - "Markdown Import"
Cohesion: 0.14
Nodes (13): BigInt?, frb_generated.dart, int get, code, convertMarkdown, diagnostics, hashCode, line (+5 more)

### Community 88 - "AppDelegate"
Cohesion: 0.22
Nodes (8): Any, BGProcessingTask, FlutterImplicitEngineBridge, FlutterImplicitEngineDelegate, AppDelegate, Bool, FlutterEngine, UIApplication

### Community 89 - "Compiler"
Cohesion: 0.15
Nodes (12): dart:ffi, Finalizable, package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart, package:typst_flutter/src/document.dart, package:typst_flutter/src/exceptions.dart, compile, create, _dateTimeToSysTime (+4 more)

### Community 90 - "RunnerTests"
Cohesion: 0.20
Nodes (8): BackgroundTasks, Flutter, FlutterSceneDelegate, SceneDelegate, RunnerTests, UIKit, XCTest, XCTestCase

### Community 91 - "RunnerTests"
Cohesion: 0.21
Nodes (7): Cocoa, FlutterMacOS, MainFlutterWindow, Bool, RunnerTests, NSWindow, NSWindowDelegate

### Community 92 - "Tylog Format V1"
Cohesion: 0.23
Nodes (12): TyLog Typst Package 0.1.0, Vendored Package Facade (offline compile), Namespaced tylog Typst Interface, Bundled typst/tylog and typst/vault Assets, Standard Note Kinds, Note Record (<tylog-note>), Task Status and Priority Vocabulary, Task Record (<tylog-task>) (+4 more)

### Community 93 - "PreviewProvider"
Cohesion: 0.24
Nodes (8): Error, CompileError, PreviewProvider, Data, QLFilePreviewRequest, QLPreviewingController, QLPreviewProvider, QLPreviewReply

### Community 94 - "Tylog Assets"
Cohesion: 0.17
Nodes (10): _bytes, _cached, load, text, TylogAssets, appVersion, Map, package:flutter/services.dart (+2 more)

### Community 95 - "Markdown Import"
Cohesion: 0.24
Nodes (10): convert_markdown(), MarkdownImportDiagnostic, MarkdownTypstResult, Option, Vec, convert_vault_note(), Option, Vec (+2 more)

### Community 96 - "AppDelegate"
Cohesion: 0.27
Nodes (6): FlutterAppDelegate, AppDelegate, Bool, Notification, NSApplication, NSStatusItem

### Community 97 - "Scanner Task Mutation Test"
Cohesion: 0.18
Nodes (9): _cli, main, calls, _fallbackTasksFor, _fieldFrom, main, note, return (+1 more)

### Community 98 - "Scanner Legacy Tags Test"
Cohesion: 0.18
Nodes (10): _FailingInspector, inspect, main, scan, _staleCacheTests, _synonymFileTests, synonyms, _synonymTests (+2 more)

### Community 99 - "Typst Flutter"
Cohesion: 0.18
Nodes (10): src/compiler.dart, src/document.dart, src/exceptions.dart, src/markdown_import.dart, src/rust/api/markdown_import.dart, src/rust/api/typst.dart, src/rust/api/vault_import.dart, src/vault_import.dart (+2 more)

### Community 100 - "Quicklook Ffi"
Cohesion: 0.38
Nodes (8): c_char, compile_pdf(), Result, Vec, string_to_c(), typst_ql_compile_pdf(), typst_ql_free_string(), TypstQlFile

### Community 101 - "Pubspec"
Cohesion: 0.20
Nodes (10): app_mobile.dart (Flutter UI), WorkspaceController, Styled Tappable Blocks by Default, Local typst_flutter Fork with Explicit Setup, publish_to: none Guard, tylog Flutter Application Package, tylog_core Path Dependency, typst_flutter Path Dependency (+2 more)

### Community 102 - "Tylog Ecosystem"
Cohesion: 0.22
Nodes (10): CliTypstInspector, FlutterTypstInspector, Format v1 Metadata, Native Metadata Parity Integration Test, TypstCompiler (embedded runtime), TypstInspector, GitHub Issue #42 (status:check-needed), Verification Command Gates (+2 more)

### Community 103 - "Tylog Ecosystem"
Cohesion: 0.24
Nodes (10): CLI dedupe Command, tylog_import_core (Rust crate), typst_flutter bridge, VaultStorage, No Markdown Storage (Convert-on-Import), In-App Logseq/Obsidian Vault Import, Attachment Record (<tylog-attachment>), ID Stability and Path Safety Rules (+2 more)

### Community 104 - "GeneratedPluginRegistrant"
Cohesion: 0.20
Nodes (8): file_picker, flutter_local_notifications, flutter_secure_storage_darwin, flutter_timezone, FlutterPluginRegistry, RegisterGeneratedPlugins(), share_plus, url_launcher_macos

### Community 105 - "VaultLookup"
Cohesion: 0.22
Nodes (6): Foundation, Data, URL, VaultLookup, QuickLookUI, UniformTypeIdentifiers

### Community 106 - "Agenda Filter Test"
Cohesion: 0.20
Nodes (7): package:tylog_core/models.dart, package:tylog/editor_autocomplete.dart, main, _task, today, main, _note

### Community 107 - "Vault Storage Test"
Cohesion: 0.24
Nodes (9): _checkPermission, _CorruptingStorage, main, readBytes, _RevocableSafStorage, revoke, _revoked, _SimulatedSafStorage (+1 more)

### Community 108 - "Articles Shelf Test"
Cohesion: 0.22
Nodes (8): package:tylog/widgets/property_select_chip.dart, package:tylog/widgets/work_surface.dart, main, plainNote, reading, shelf, summarized, unread

### Community 109 - "Vault Lock"
Cohesion: 0.25
Nodes (7): acquire, heldByOther, path, release, staleAfter, VaultLock, static const

### Community 110 - "Task Checkbox"
Cohesion: 0.25
Nodes (7): build, onChanged, TaskCheckbox, taskCheckedGlyph, taskUncheckedGlyph, value, ValueChanged

### Community 111 - "Today Page Test"
Cohesion: 0.25
Nodes (5): package:tylog/app_mobile.dart, main, _article, main, main

### Community 112 - "Exceptions"
Cohesion: 0.32
Nodes (7): package:typst_flutter/src/rust/api/typst.dart, diagnostics, message, toString, TypstCompileException, TypstException, TypstRenderException

### Community 113 - "Search Index Test"
Cohesion: 0.25
Nodes (7): _buildIndex, buildStorage, main, _note, notesDir, storage, vault

### Community 114 - "Nextcloud Sync"
Cohesion: 0.29
Nodes (7): Exception, UpdateNotWritable, _RemoteChanged, SyncDeferred, WorkspaceSyncNotConfigured, _UsageException, IndexBuildCancelled

### Community 115 - "App Mobile"
Cohesion: 0.29
Nodes (7): HomeScreen, _HomeScreenState, _DesktopUpdateFlow, _MarkdownImportFlow, _VaultImportFlow, _VaultLifecycle, WidgetsBindingObserver

### Community 116 - "Platform File Actions"
Cohesion: 0.29
Nodes (6): importPlatformFile, openPlatformFile, uri, writeBytes, package:url_launcher/url_launcher.dart, vault_storage.dart

### Community 117 - "Date Format"
Cohesion: 0.29
Nodes (6): compactHumanDate, humanDate, isoDay, label, _monthNames, _weekdayNames

### Community 118 - "Voronoi View Test"
Cohesion: 0.29
Nodes (6): package:tylog/voronoi_view.dart, communities, host, index, main, _note

### Community 119 - "Markdown Import"
Cohesion: 0.29
Nodes (5): package:typst_flutter/src/rust/api/markdown_import.dart, package:typst_flutter/src/rust/api/vault_import.dart, package:typst_flutter/src/rust/frb_generated.dart, convertMarkdown, convertVaultNote

### Community 120 - "Frb Generated"
Cohesion: 0.40
Nodes (6): @sealed, CompiledDocument, CompiledDocumentImpl, TypstEngineImpl, RustOpaque, TypstEngine

### Community 121 - "Frb Generated"
Cohesion: 0.40
Nodes (6): BaseApi, BaseEntrypoint, RustLib, RustLibApi, RustLibApiImpl, RustLibApiImplPlatform

### Community 122 - "Frb Generated"
Cohesion: 0.40
Nodes (3): FrbException, TypstCompileError, crate::api::typst::TypstCompileError

### Community 123 - "Sync Status"
Cohesion: 0.33
Nodes (5): changed, syncStatusAction, SyncStatusKind, syncStatusTitle, nextcloud_sync.dart

### Community 124 - "Cli Typst Inspector"
Cohesion: 0.33
Nodes (5): CliTypstInspector, executable, inspect, root, scanner.dart

### Community 125 - "Setup Typst Native"
Cohesion: 0.60
Nodes (4): CI Workflow, Linux Prebuilt .so Detection, mark_source_built(), setup_typst_native.sh script

### Community 126 - "Graph"
Cohesion: 0.40
Nodes (5): GraphView, _GraphViewState, VoronoiView, _VoronoiViewState, SingleTickerProviderStateMixin

### Community 127 - "Nextcloud Sync"
Cohesion: 0.40
Nodes (5): NextcloudSync, _PathSync, _SyncConflicts, _SyncStatePersistence, _WebDavClient

### Community 131 - "Relink Strip Test"
Cohesion: 0.40
Nodes (4): _article, body, main, marker

### Community 132 - "Frb Generated Io"
Cohesion: 0.67
Nodes (4): BaseApiImpl, RustLibApiImplPlatform, RustLibApiImplPlatform, RustLibWire

### Community 133 - "Graph"
Cohesion: 0.50
Nodes (4): CustomPainter, GraphPainter, _SwatchPainter, _VoronoiPainter

### Community 134 - "Graph Label Test"
Cohesion: 0.50
Nodes (3): dart:ui, package:tylog/widgets/graph_label.dart, main

### Community 135 - "VaultLookup"
Cohesion: 0.83
Nodes (4): Decodable, Storage, Vault, VaultsFile

### Community 136 - "Vault Storage"
Cohesion: 0.50
Nodes (4): AndroidTreeVaultStorage, VaultStorage, _CountingStorage, _TracingStorage

### Community 137 - "CMakeLists"
Cohesion: 0.50
Nodes (4): APPLY_STANDARD_SETTINGS (CMake), tylog Linux Binary Target, flutter_assemble Target, Linux Runner Executable

### Community 138 - "Nextcloud Sync Test"
Cohesion: 0.50
Nodes (4): LocalVaultStorage, _CheckpointCountingStorage, _HashCountingStorage, _MidSyncWriteStorage

### Community 139 - "PLAN"
Cohesion: 0.50
Nodes (4): Selection-Aware Magic Actions, Reproducible Typst Reports and PDF Export, Filtered Reports and Sibling PDF Export, Magic Button and / Palette

### Community 140 - "USER MANUAL"
Cohesion: 0.50
Nodes (4): Today-First Mobile Workspace, Graph Views (Concept map, Focused, All files, Timeline, Voronoi), Today Screen, Voronoi Treemap View

### Community 141 - "Analysis Options"
Cohesion: 0.67
Nodes (3): Root Analyzer Configuration, tylog_core Lints Configuration, typst_flutter Local Fork 2.2.1

### Community 142 - "Frb Generated Web"
Cohesion: 0.67
Nodes (3): @anonymous, @JS, RustLibWasmModule

### Community 143 - "Graph"
Cohesion: 0.67
Nodes (3): @immutable, ClusterAgg, LayoutRequest

### Community 144 - "Frb Generated Io"
Cohesion: 0.67
Nodes (3): BaseWire, RustLibWire, RustLibWire

## Ambiguous Edges - Review These
- `On-device Profiling (Android profile build)` → `Android Release Job`  [AMBIGUOUS]
  AGENTS.md · relation: conceptually_related_to

## Knowledge Gaps
- **3369 isolated node(s):** `smokeValue`, `main`, `_NativeRemoteFile`, `_NativeWebDavServer`, `filler` (+3364 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **40 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **What is the exact relationship between `On-device Profiling (Android profile build)` and `Android Release Job`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._
- **Why does `bool` connect `FRB Bindings (Rust)` to `Workspace Controller`, `Frb Generated`?**
  _High betweenness centrality (0.174) - this node is a cross-community bridge._
- **Why does `String` connect `Vault Import` to `Quicklook Ffi`, `FRB Bindings (Rust)`, `Typst Compile Engine`, `Logseq Vault Import`, `Markdown to Typst Converter`, `Logseq Import`, `Markdown Import`?**
  _High betweenness centrality (0.124) - this node is a cross-community bridge._
- **Why does `run()` connect `Logseq Import` to `Logseq Vault Import`, `PreviewProvider`?**
  _High betweenness centrality (0.035) - this node is a cross-community bridge._
- **What connects `smokeValue`, `main`, `_NativeRemoteFile` to the rest of the system?**
  _3369 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Rich Editor Widgets` be split into smaller, more focused modules?**
  _Cohesion score 0.007220216606498195 - nodes in this community are weakly interconnected._
- **Should `Mobile App Shell` be split into smaller, more focused modules?**
  _Cohesion score 0.0078125 - nodes in this community are weakly interconnected._