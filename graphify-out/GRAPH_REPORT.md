# Graph Report - .  (2026-07-04)

## Corpus Check
- 111 files · ~138,218 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 914 nodes · 1037 edges · 34 communities (30 shown, 4 thin omitted)
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS · INFERRED: 2 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_App Mobile|App Mobile]]
- [[_COMMUNITY_Scanner|Scanner]]
- [[_COMMUNITY_Nextcloud Sync|Nextcloud Sync]]
- [[_COMMUNITY_Graph|Graph]]
- [[_COMMUNITY_Pkms Registry|Pkms Registry]]
- [[_COMMUNITY_Knowledge Screen|Knowledge Screen]]
- [[_COMMUNITY_Search Index|Search Index]]
- [[_COMMUNITY_unnamed|]]
- [[_COMMUNITY_Vault|Vault]]
- [[_COMMUNITY_Models|Models]]
- [[_COMMUNITY_Vault Registry|Vault Registry]]
- [[_COMMUNITY_My Application|My Application]]
- [[_COMMUNITY_Open File Mac.Podspec|Open File Mac.Podspec]]
- [[_COMMUNITY_File Picker.Podspec|File Picker.Podspec]]
- [[_COMMUNITY_Typst Flutter.Podspec|Typst Flutter.Podspec]]
- [[_COMMUNITY_Nextcloud Sync Test|Nextcloud Sync Test]]
- [[_COMMUNITY_App Mobile|App Mobile]]
- [[_COMMUNITY_None|None]]
- [[_COMMUNITY_None|None]]
- [[_COMMUNITY_Manifest|Manifest]]
- [[_COMMUNITY_App Web|App Web]]
- [[_COMMUNITY_Pods-Runner-Frameworks|Pods-Runner-Frameworks]]
- [[_COMMUNITY_Generatedpluginregistrant|Generatedpluginregistrant]]
- [[_COMMUNITY_None|None]]
- [[_COMMUNITY_None|None]]
- [[_COMMUNITY_None|None]]
- [[_COMMUNITY_Mainactivity|Mainactivity]]
- [[_COMMUNITY_None|None]]
- [[_COMMUNITY_None|None]]
- [[_COMMUNITY_Flutter Export Environment|Flutter Export Environment]]
- [[_COMMUNITY_None|None]]

## God Nodes (most connected - your core abstractions)
1. `Cocoa` - 8 edges
2. `_MyApplication` - 7 edges
3. `Foundation` - 6 edges
4. `map` - 5 edges
5. `install_framework()` - 5 edges
6. `GeneratedPluginRegistrant` - 4 edges
7. `_HomeScreenState` - 4 edges
8. `my_application_local_command_line()` - 4 edges
9. `FlutterMacOS` - 4 edges
10. `AppDelegate` - 4 edges

## Surprising Connections (you probably didn't know these)
- `main()` --calls--> `my_application_new()`  [INFERRED]
  linux/runner/main.cc → linux/runner/my_application.cc

## Import Cycles
- None detected.

## Communities (34 total, 4 thin omitted)

### Community 0 - "App Mobile"
Cohesion: 0.01
Nodes (175): dart:async, double?, graph.dart, IconData, knowledge_screen.dart, 40, activeVaultId, activity (+167 more)

### Community 1 - "Scanner"
Cohesion: 0.02
Nodes (102): if, _add, _aliases, allProblems, backlinks, _balancedEnd, buildVaultIndex, calls (+94 more)

### Community 2 - "Nextcloud Sync"
Cohesion: 0.03
Nodes (69): DateTime, int?, action, _appendTrace, _cleanResolvedConflictCopies, _client, config, conflicts (+61 more)

### Community 3 - "Graph"
Cohesion: 0.03
Nodes (64): dart:math, build, buildLocalNoteGraph, buildNoteGraph, _canvas, center, colorScheme, createState (+56 more)

### Community 4 - "Pkms Registry"
Cohesion: 0.03
Nodes (60): bool get, int get, aliases, bibliographyPath, cacheConflicts, collections, copyWith, count (+52 more)

### Community 5 - "Knowledge Screen"
Cohesion: 0.04
Nodes (46): KnowledgeScreen, HomeScreen, _HomeScreenState, GraphView, _GraphViewState, build, collections, _collectionsTab (+38 more)

### Community 6 - "Search Index"
Cohesion: 0.05
Nodes (43): add, bibliography, byId, compiler, _escape, exportPkmsCollection, helper, helperFile (+35 more)

### Community 7 - ""
Cohesion: 0.05
Nodes (26): Bool, Cocoa, file_picker, FlutterAppDelegate, FlutterMacOS, FlutterPluginRegistry, Foundation, RegisterGeneratedPlugins() (+18 more)

### Community 8 - "Vault"
Cohesion: 0.06
Nodes (35): Directory, Directory get, File get, assets, configured, _day, defaultVaultDirectory, ensureCreated (+27 more)

### Community 9 - "Models"
Cohesion: 0.06
Nodes (32): aliases, backlinksByTarget, citations, code, copyWith, date, fileBacklinksById, fileRefs (+24 more)

### Community 10 - "Vault Registry"
Cohesion: 0.07
Nodes (27): File, NextcloudConfig, active, activeId, add, cloud, copyWith, delete (+19 more)

### Community 11 - "My Application"
Cohesion: 0.11
Nodes (20): FlView, GApplication, gboolean, gchar, GObject, GtkApplication, main(), first_frame_cb() (+12 more)

### Community 12 - "Open File Mac.Podspec"
Cohesion: 0.09
Nodes (22): authors, crazecoder, dependencies, FlutterMacOS, description, homepage, license, file (+14 more)

### Community 13 - "File Picker.Podspec"
Cohesion: 0.09
Nodes (21): authors, dependencies, FlutterMacOS, description, homepage, license, file, name (+13 more)

### Community 14 - "Typst Flutter.Podspec"
Cohesion: 0.09
Nodes (21): authors, Ajmal, dependencies, FlutterMacOS, description, homepage, license, file (+13 more)

### Community 15 - "Nextcloud Sync Test"
Cohesion: 0.14
Nodes (13): DateTime? remoteModified,
  String, package:crypto/crypto.dart, return, _config, etag, hash, interrupted, main (+5 more)

### Community 16 - "App Mobile"
Cohesion: 0.14
Nodes (14): _ConflictVersionCard, _Editor, _EmptyHint, _LinksPanel, _ModeButton, _PagesPanel, _SectionTitle, _SettingsSheet (+6 more)

### Community 17 - "None"
Cohesion: 0.18
Nodes (11): package:tylog/knowledge_screen.dart, package:tylog/main.dart, package:tylog/models.dart, package:tylog/pkms_registry.dart, package:tylog/search_index.dart, TabBar, main, main (+3 more)

### Community 18 - "None"
Cohesion: 0.25
Nodes (8): dart:convert, dart:io, package:flutter_test/flutter_test.dart, package:tylog/scanner.dart, package:tylog/vault.dart, main, main, main

### Community 19 - "Manifest"
Cohesion: 0.18
Nodes (10): background_color, description, display, icons, name, orientation, prefer_related_applications, short_name (+2 more)

### Community 20 - "App Web"
Cohesion: 0.25
Nodes (6): app_mobile.dart, build, TyLogApp, _WebHome, main, package:flutter/material.dart

### Community 21 - "Pods-Runner-Frameworks"
Cohesion: 0.43
Nodes (6): code_sign_if_enabled(), install_bcsymbolmap(), install_dsym(), install_framework(), Pods-Runner-frameworks.sh script, strip_invalid_archs()

### Community 22 - "Generatedpluginregistrant"
Cohesion: 0.47
Nodes (4): GeneratedPluginRegistrant, String, FlutterEngine, Keep

### Community 23 - "None"
Cohesion: 0.33
Nodes (5): CustomPaint, InteractiveViewer, package:tylog/graph.dart, RenderBox, main

### Community 24 - "None"
Cohesion: 0.33
Nodes (5): dart:typed_data, main, package:integration_test/integration_test.dart, package:tylog/pkms_publisher.dart, package:typst_flutter/typst_flutter.dart

### Community 25 - "None"
Cohesion: 0.50
Nodes (3): package:tylog/nextcloud_sync.dart, package:tylog/vault_registry.dart, main

### Community 27 - "None"
Cohesion: 0.67
Nodes (3): Exception, _RemoteChanged, IndexBuildCancelled

## Knowledge Gaps
- **667 isolated node(s):** `main`, `_CleanSource`, `vault`, `index`, `note` (+662 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **4 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `map` connect `Search Index` to `Models`, `Graph`, `Pkms Registry`, `Scanner`?**
  _High betweenness centrality (0.027) - this node is a cross-community bridge._
- **Why does `VaultIndex` connect `Models` to `App Mobile`, `Knowledge Screen`?**
  _High betweenness centrality (0.012) - this node is a cross-community bridge._
- **Why does `NextcloudConfig` connect `Vault Registry` to `App Mobile`, `Nextcloud Sync`?**
  _High betweenness centrality (0.007) - this node is a cross-community bridge._
- **What connects `main`, `_CleanSource`, `vault` to the rest of the system?**
  _667 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `App Mobile` be split into smaller, more focused modules?**
  _Cohesion score 0.011363636363636364 - nodes in this community are weakly interconnected._
- **Should `Scanner` be split into smaller, more focused modules?**
  _Cohesion score 0.019417475728155338 - nodes in this community are weakly interconnected._
- **Should `Nextcloud Sync` be split into smaller, more focused modules?**
  _Cohesion score 0.02857142857142857 - nodes in this community are weakly interconnected._