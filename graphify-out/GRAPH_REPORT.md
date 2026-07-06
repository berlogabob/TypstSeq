# Graph Report - typstseq-graphify.xW7q7L  (2026-07-06)

## Corpus Check
- 92 files · ~52,785 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1941 nodes · 2549 edges · 96 communities (65 shown, 31 thin omitted)
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS · INFERRED: 6 edges (avg confidence: 0.88)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Community 0|Community 0]]
- [[_COMMUNITY_Community 1|Community 1]]
- [[_COMMUNITY_Community 2|Community 2]]
- [[_COMMUNITY_Community 3|Community 3]]
- [[_COMMUNITY_Community 4|Community 4]]
- [[_COMMUNITY_Community 5|Community 5]]
- [[_COMMUNITY_Community 6|Community 6]]
- [[_COMMUNITY_Community 7|Community 7]]
- [[_COMMUNITY_Community 8|Community 8]]
- [[_COMMUNITY_Community 9|Community 9]]
- [[_COMMUNITY_Community 10|Community 10]]
- [[_COMMUNITY_Community 11|Community 11]]
- [[_COMMUNITY_Community 12|Community 12]]
- [[_COMMUNITY_Community 13|Community 13]]
- [[_COMMUNITY_Community 14|Community 14]]
- [[_COMMUNITY_Community 15|Community 15]]
- [[_COMMUNITY_Community 16|Community 16]]
- [[_COMMUNITY_Community 17|Community 17]]
- [[_COMMUNITY_Community 18|Community 18]]
- [[_COMMUNITY_Community 19|Community 19]]
- [[_COMMUNITY_Community 20|Community 20]]
- [[_COMMUNITY_Community 21|Community 21]]
- [[_COMMUNITY_Community 22|Community 22]]
- [[_COMMUNITY_Community 23|Community 23]]
- [[_COMMUNITY_Community 24|Community 24]]
- [[_COMMUNITY_Community 25|Community 25]]
- [[_COMMUNITY_Community 26|Community 26]]
- [[_COMMUNITY_Community 27|Community 27]]
- [[_COMMUNITY_Community 28|Community 28]]
- [[_COMMUNITY_Community 29|Community 29]]
- [[_COMMUNITY_Community 30|Community 30]]
- [[_COMMUNITY_Community 31|Community 31]]
- [[_COMMUNITY_Community 32|Community 32]]
- [[_COMMUNITY_Community 33|Community 33]]
- [[_COMMUNITY_Community 34|Community 34]]
- [[_COMMUNITY_Community 35|Community 35]]
- [[_COMMUNITY_Community 36|Community 36]]
- [[_COMMUNITY_Community 37|Community 37]]
- [[_COMMUNITY_Community 38|Community 38]]
- [[_COMMUNITY_Community 39|Community 39]]
- [[_COMMUNITY_Community 40|Community 40]]
- [[_COMMUNITY_Community 41|Community 41]]
- [[_COMMUNITY_Community 42|Community 42]]
- [[_COMMUNITY_Community 43|Community 43]]
- [[_COMMUNITY_Community 44|Community 44]]
- [[_COMMUNITY_Community 45|Community 45]]
- [[_COMMUNITY_Community 46|Community 46]]
- [[_COMMUNITY_Community 47|Community 47]]
- [[_COMMUNITY_Community 48|Community 48]]
- [[_COMMUNITY_Community 49|Community 49]]
- [[_COMMUNITY_Community 50|Community 50]]
- [[_COMMUNITY_Community 51|Community 51]]
- [[_COMMUNITY_Community 52|Community 52]]
- [[_COMMUNITY_Community 53|Community 53]]
- [[_COMMUNITY_Community 54|Community 54]]
- [[_COMMUNITY_Community 55|Community 55]]
- [[_COMMUNITY_Community 56|Community 56]]
- [[_COMMUNITY_Community 57|Community 57]]
- [[_COMMUNITY_Community 58|Community 58]]
- [[_COMMUNITY_Community 59|Community 59]]
- [[_COMMUNITY_Community 61|Community 61]]
- [[_COMMUNITY_Community 66|Community 66]]
- [[_COMMUNITY_Community 70|Community 70]]
- [[_COMMUNITY_Community 71|Community 71]]
- [[_COMMUNITY_Community 72|Community 72]]
- [[_COMMUNITY_Community 73|Community 73]]
- [[_COMMUNITY_Community 74|Community 74]]
- [[_COMMUNITY_Community 80|Community 80]]
- [[_COMMUNITY_Community 81|Community 81]]
- [[_COMMUNITY_Community 82|Community 82]]
- [[_COMMUNITY_Community 83|Community 83]]
- [[_COMMUNITY_Community 84|Community 84]]
- [[_COMMUNITY_Community 85|Community 85]]
- [[_COMMUNITY_Community 86|Community 86]]
- [[_COMMUNITY_Community 87|Community 87]]
- [[_COMMUNITY_Community 88|Community 88]]
- [[_COMMUNITY_Community 89|Community 89]]
- [[_COMMUNITY_Community 90|Community 90]]
- [[_COMMUNITY_Community 91|Community 91]]
- [[_COMMUNITY_Community 92|Community 92]]
- [[_COMMUNITY_Community 93|Community 93]]
- [[_COMMUNITY_Community 94|Community 94]]
- [[_COMMUNITY_Community 95|Community 95]]

## God Nodes (most connected - your core abstractions)
1. `SimpleWorld` - 29 edges
2. `String` - 17 edges
3. `CompiledDocument` - 12 edges
4. `TypstDiagnostic` - 10 edges
5. `crate::api::typst::PageInfo` - 10 edges
6. `crate::api::typst::RenderResult` - 10 edges
7. `crate::api::typst::TypstCompileError` - 10 edges
8. `crate::api::typst::TypstDiagnostic` - 10 edges
9. `crate::api::typst::TypstSeverity` - 10 edges
10. `crate::api::typst::TypstSourceLocation` - 10 edges

## Surprising Connections (you probably didn't know these)
- `Native Compiler Setup Step` --semantically_similar_to--> `Explicit Native Compiler Setup`  [INFERRED] [semantically similar]
  .github/workflows/linux.yml → README.md
- `Flutter Linux Build Step` --implements--> `Release Verification`  [INFERRED]
  .github/workflows/linux.yml → PLAN.md
- `GeneratedPluginRegistrant` --references--> `String`  [EXTRACTED]
  android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java → packages/typst_flutter/rust/src/frb_generated.rs
- `Flutter Recommended Lints` --references--> `flutter_lints Dependency`  [EXTRACTED]
  analysis_options.yaml → pubspec.yaml
- `typst_flutter Path Dependency` --references--> `Local typst_flutter Package Fork`  [EXTRACTED]
  pubspec.yaml → packages/typst_flutter/pubspec.yaml

## Import Cycles
- 1-file cycle: `packages/typst_flutter/rust/src/api/typst.rs -> packages/typst_flutter/rust/src/api/typst.rs`

## Hyperedges (group relationships)
- **TyLog v5 Vault Architecture** — plan_schema_v5_vault, readme_local_first_typst_first_workspace, user_manual_vault_format [INFERRED 0.85]
- **Native Typst Compiler Integration** — github_workflows_linux_native_compiler_setup, readme_explicit_native_compiler_setup, plan_local_typst_flutter_fork, packages_typst_flutter_linux_cmakelists_prebuilt_typst_flutter_library, packages_typst_flutter_pubspec_ffi_plugin_platforms [INFERRED 0.95]
- **Release Verification Pipeline** — github_workflows_linux_linux_build, plan_release_verification, readme_make_verify [INFERRED 0.85]

## Communities (96 total, 31 thin omitted)

### Community 0 - "Community 0"
Cohesion: 0.01
Nodes (188): bibliography.dart, bool get, Completer, double?, graph.dart, IconData, knowledge_screen.dart, 40 (+180 more)

### Community 1 - "Community 1"
Cohesion: 0.01
Nodes (160): ExternalLibraryLoaderConfig get, frb_generated.io.dart, addFonts, apiImplConstructor, codegenVersion, compile, crateApiTypstCompiledDocumentExportPdf, crateApiTypstCompiledDocumentExportSvg (+152 more)

### Community 2 - "Community 2"
Cohesion: 0.02
Nodes (125): _add, _aliases, allProblems, attachmentBacklinks, attachmentCalls, attachments, backlinks, _balancedContentEnd (+117 more)

### Community 3 - "Community 3"
Cohesion: 0.02
Nodes (117): api/typst.dart, CrossPlatformFinalizerArg
  get, external RustLibWasmModule get, package:flutter_rust_bridge/flutter_rust_bridge_for_generated_web.dart, dco_decode_Auto_Owned_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerCompiledDocument, dco_decode_Auto_Owned_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerTypstEngine, dco_decode_Auto_Ref_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerCompiledDocument, dco_decode_Auto_RefMut_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerTypstEngine (+109 more)

### Community 4 - "Community 4"
Cohesion: 0.02
Nodes (117): package:flutter_rust_bridge/flutter_rust_bridge_for_generated_io.dart, dco_decode_Auto_Owned_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerCompiledDocument, dco_decode_Auto_Owned_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerTypstEngine, dco_decode_Auto_Ref_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerCompiledDocument, dco_decode_Auto_RefMut_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerTypstEngine, dco_decode_box_autoadd_i_64, dco_decode_box_autoadd_typst_source_location, dco_decode_f_32 (+109 more)

### Community 5 - "Community 5"
Cohesion: 0.07
Nodes (52): GeneratedPluginRegistrant, Bytes, DiagSpan, Duration, FileError, FileId, FlutterEngine, Font (+44 more)

### Community 6 - "Community 6"
Cohesion: 0.03
Nodes (71): action, _appendTrace, _cleanResolvedConflictCopies, _client, config, conflicts, decideSyncAction, decisions (+63 more)

### Community 7 - "Community 7"
Cohesion: 0.03
Nodes (64): dart:math, build, buildLocalNoteGraph, buildNoteGraph, _canvas, center, colorScheme, createState (+56 more)

### Community 8 - "Community 8"
Cohesion: 0.03
Nodes (60): action, _addBlocks, applyMagicEdit, _balancedParenEnd, _block, blocks, bodyStart, boundedLineEnd (+52 more)

### Community 9 - "Community 9"
Cohesion: 0.04
Nodes (56): int?, aliases, assignees, attachmentBacklinksByPath, AttachmentRef, attachments, backlinksByTarget, CalendarItem (+48 more)

### Community 10 - "Community 10"
Cohesion: 0.09
Nodes (16): Option<crate::api::typst::TypstSourceLocation>, Option<i64>, Option<std::collections::HashMap<String, String>>, Self, RustOpaqueMoi<flutter_rust_bridge::for_generated::RustAutoOpaqueInner<CompiledDocument>>, RustOpaqueMoi<flutter_rust_bridge::for_generated::RustAutoOpaqueInner<TypstEngine>>, std::collections::HashMap<String, String>, (String, String) (+8 more)

### Community 11 - "Community 11"
Cohesion: 0.05
Nodes (31): Any, Cocoa, file_picker, Flutter, flutter_local_notifications, flutter_timezone, FlutterAppDelegate, FlutterImplicitEngineBridge (+23 more)

### Community 12 - "Community 12"
Cohesion: 0.04
Nodes (47): Directory, Directory get, File get, article, articles, assets, bibliographyFile, cache (+39 more)

### Community 13 - "Community 13"
Cohesion: 0.06
Nodes (42): @immutable, @internal, Equatable, map, initial, initialize, nextTaskReminder, plugin (+34 more)

### Community 14 - "Community 14"
Cohesion: 0.05
Nodes (39): Exception, _RemoteChanged, IndexBuildCancelled, aliases, build, _documents, empty, fileKind (+31 more)

### Community 15 - "Community 15"
Cohesion: 0.05
Nodes (37): frb_generated.dart, FrbException, addFonts, bytes, column, compile, CompiledDocument, diagnostics (+29 more)

### Community 16 - "Community 16"
Cohesion: 0.29
Nodes (7): Flutter Recommended Lints, Prebuilt typst_flutter Linux Library, FFI Plugin Platforms, Local typst_flutter Package Fork, flutter_lints Dependency, TyLog Flutter Application Package, typst_flutter Path Dependency

### Community 17 - "Community 17"
Cohesion: 0.06
Nodes (31): dart:async, color, package:typst_flutter/src/widgets/typst_compiler_provider.dart, package:typst_flutter/src/widgets/typst_view.dart, _activeDocument, build, _compileDocument, _compiler (+23 more)

### Community 18 - "Community 18"
Cohesion: 0.07
Nodes (29): BoxFit, package:flutter_svg/flutter_svg.dart, build, _buildWrapper, _compiler, createState, date, didChangeDependencies (+21 more)

### Community 19 - "Community 19"
Cohesion: 0.06
Nodes (30): dart:isolate, package:archive/archive_io.dart, package:http/http.dart, package:path/path.dart, androidArtifacts, _Artifact, _artifactsForPlatform, destination (+22 more)

### Community 20 - "Community 20"
Cohesion: 0.07
Nodes (28): File, NextcloudConfig, active, activeId, add, cloud, completeOnboarding, copyWith (+20 more)

### Community 21 - "Community 21"
Cohesion: 0.09
Nodes (22): FlPluginRegistry, FlView, GApplication, gboolean, gchar, GObject, GtkApplication, fl_register_plugins() (+14 more)

### Community 22 - "Community 22"
Cohesion: 0.20
Nodes (25): c_void, MessagePort, frbgen_typst_flutter_rust_arc_decrement_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerCompiledDocument(), frbgen_typst_flutter_rust_arc_decrement_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerTypstEngine(), frbgen_typst_flutter_rust_arc_increment_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerCompiledDocument(), frbgen_typst_flutter_rust_arc_increment_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerTypstEngine(), pde_ffi_dispatcher_primary_impl(), pde_ffi_dispatcher_sync_impl() (+17 more)

### Community 23 - "Community 23"
Cohesion: 0.08
Nodes (25): CompiledDocument get, dart:ui, int get, bytes, _cachedImage, _checkNotDisposed, _decodeImage, dispose (+17 more)

### Community 24 - "Community 24"
Cohesion: 0.06
Nodes (33): controlled_editor.dart, dart:typed_data, document, entries, HayagrivaEntry, key, parseHayagrivaBibliography, title (+25 more)

### Community 25 - "Community 25"
Cohesion: 0.15
Nodes (14): dart:convert, dart:io, main, package:flutter_test/flutter_test.dart, package:integration_test/integration_test.dart, package:tylog/bibliography.dart, package:tylog/pkms_registry.dart, package:tylog/scanner.dart (+6 more)

### Community 26 - "Community 26"
Cohesion: 0.11
Nodes (10): f32, f64, i32, i64, u32, u8, usize, () (+2 more)

### Community 27 - "Community 27"
Cohesion: 0.09
Nodes (21): HttpException, package:crypto/crypto.dart, String? remoteModifiedValue,
  String, bytes, _config, etag, hash, interrupted (+13 more)

### Community 28 - "Community 28"
Cohesion: 0.15
Nodes (10): IntoDart, IntoDartExceptPrimitive, crate::api::typst::TypstCompileError, crate::api::typst::TypstDiagnostic, crate::api::typst::TypstSourceLocation, FrbWrapper<CompiledDocument>, FrbWrapper<TypstEngine>, TypstSourceLocation (+2 more)

### Community 29 - "Community 29"
Cohesion: 0.11
Nodes (19): _ConflictVersionCard, _DashboardSection, _DockButton, _EmptyHint, _LibraryView, _LinksPanel, _PrimaryTasksView, _SectionTitle (+11 more)

### Community 30 - "Community 30"
Cohesion: 0.11
Nodes (17): dart:ffi, package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart, package:typst_flutter/src/document.dart, package:typst_flutter/src/exceptions.dart, package:typst_flutter/src/files.dart, package:typst_flutter/src/fonts.dart, package:typst_flutter/src/rust/frb_generated.dart, addFonts (+9 more)

### Community 31 - "Community 31"
Cohesion: 0.11
Nodes (17): KnowledgeScreen, build, createState, index, initialView, _KnowledgeScreenState, onOpenNote, problems (+9 more)

### Community 32 - "Community 32"
Cohesion: 0.28
Nodes (3): DartAbi, crate::api::typst::VirtualFile, VirtualFile

### Community 33 - "Community 33"
Cohesion: 0.15
Nodes (18): _ControlledEditorView, _ControlledEditorViewState, _Editor, _EditorState, HomeScreen, _HomeScreenState, _TodayView, _TodayViewState (+10 more)

### Community 34 - "Community 34"
Cohesion: 0.17
Nodes (11): KnowledgeView, package:tylog/knowledge_screen.dart, package:tylog/main.dart, initialView, _knowledgeScreen, main, openSource, problems (+3 more)

### Community 35 - "Community 35"
Cohesion: 0.17
Nodes (11): count, _duplicates, helper, isSafeVaultPath, owners, PkmsValidationReport, problems, summary (+3 more)

### Community 36 - "Community 36"
Cohesion: 0.18
Nodes (10): Finalizable, InheritedWidget, package:flutter/widgets.dart, package:typst_flutter/src/compiler.dart, TypstCompiler, compiler, maybeOf, of (+2 more)

### Community 37 - "Community 37"
Cohesion: 0.20
Nodes (8): app_mobile.dart, CustomPaint, InteractiveViewer, main, package:flutter/material.dart, package:tylog/graph.dart, RenderBox, main

### Community 38 - "Community 38"
Cohesion: 0.27
Nodes (4): FrbWrapper, IntoIntoDart, CompiledDocument, TypstEngine

### Community 39 - "Community 39"
Cohesion: 0.11
Nodes (15): Check needed, Deliberate limits, Implemented, TyLog v5 implementation status, Verification, Development, Documentation, TyLog (+7 more)

### Community 40 - "Community 40"
Cohesion: 0.20
Nodes (9): src/compiler.dart, src/document.dart, src/exceptions.dart, src/files.dart, src/fonts.dart, src/rust/api/typst.dart, src/widgets/typst_compiler_provider.dart, src/widgets/typst_document_viewer.dart (+1 more)

### Community 41 - "Community 41"
Cohesion: 0.22
Nodes (7): package:tylog/controlled_editor.dart, package:tylog/models.dart, package:tylog/report.dart, package:tylog/task_scheduler.dart, index, main, main

### Community 42 - "Community 42"
Cohesion: 0.40
Nodes (6): @sealed, CompiledDocument, CompiledDocumentImpl, TypstEngineImpl, RustOpaque, TypstEngine

### Community 43 - "Community 43"
Cohesion: 0.40
Nodes (6): BaseApi, BaseEntrypoint, RustLib, RustLibApi, RustLibApiImpl, RustLibApiImplPlatform

### Community 44 - "Community 44"
Cohesion: 0.33
Nodes (5): handle_new_rx_page(), __lldb_init_module(), Intercept NOTIFY_DEBUGGER_ABOUT_RX_PAGES and touch the pages., SBDebugger, SBFrame

### Community 45 - "Community 45"
Cohesion: 0.40
Nodes (6): Apply Standard Settings, Relocatable Linux Bundle, TyLog Linux Build Configuration, Flutter Assemble Target, Flutter Interface Library, TyLog Linux Runner

### Community 46 - "Community 46"
Cohesion: 0.40
Nodes (5): Flutter Linux Build Step, Linux Build Workflow, Native Compiler Setup Step, Release Verification, Explicit Native Compiler Setup

### Community 50 - "Community 50"
Cohesion: 0.67
Nodes (4): BaseApiImpl, RustLibApiImplPlatform, RustLibApiImplPlatform, RustLibWire

### Community 51 - "Community 51"
Cohesion: 0.50
Nodes (3): package:tylog/nextcloud_sync.dart, package:tylog/vault_registry.dart, main

### Community 53 - "Community 53"
Cohesion: 0.67
Nodes (3): @anonymous, @JS, RustLibWasmModule

### Community 54 - "Community 54"
Cohesion: 0.67
Nodes (3): BaseWire, RustLibWire, RustLibWire

### Community 80 - "Community 80"
Cohesion: 0.67
Nodes (3): TyLog Sample Bibliography, Research Journals as Scientific Infrastructure, Research Journals as Scientific Infrastructure

## Knowledge Gaps
- **1299 isolated node(s):** `main`, `flutter_export_environment.sh script`, `+registerWithRegistry`, `_ShellAction`, `vault` (+1294 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **31 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `result` connect `Community 5` to `Community 0`?**
  _High betweenness centrality (0.214) - this node is a cross-community bridge._
- **Why does `String` connect `Community 5` to `Community 10`, `Community 26`?**
  _High betweenness centrality (0.148) - this node is a cross-community bridge._
- **Why does `bool` connect `Community 11` to `Community 10`, `Community 26`?**
  _High betweenness centrality (0.032) - this node is a cross-community bridge._
- **What connects `main`, `Intercept NOTIFY_DEBUGGER_ABOUT_RX_PAGES and touch the pages.`, `flutter_export_environment.sh script` to the rest of the system?**
  _1300 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Community 0` be split into smaller, more focused modules?**
  _Cohesion score 0.010582010582010581 - nodes in this community are weakly interconnected._
- **Should `Community 1` be split into smaller, more focused modules?**
  _Cohesion score 0.012422360248447204 - nodes in this community are weakly interconnected._
- **Should `Community 2` be split into smaller, more focused modules?**
  _Cohesion score 0.015873015873015872 - nodes in this community are weakly interconnected._