import 'widgets/github_project_board.dart';
import 'reading_log.dart';
import 'review_queue.dart';
import 'namespace_migration.dart';
import 'dart:async';
import 'widgets/app_icons.dart';
import 'calendar_feeds.dart';
import 'dart:ui' show AppExitResponse;
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, compute, defaultTargetPlatform, listEquals;
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:typst_flutter/typst_flutter.dart';
import 'package:tylog_audio/tylog_audio.dart'
    show audioDurationMs, peaksFromWav;
import 'package:tylog_core/enrich.dart';
import 'package:tylog_core/tylog_core.dart'
    show Decision, decisionsDir, encodeDecisions, loadDecisions, runClusterStep;
import 'package:tylog_core/values.dart';
import 'package:url_launcher/url_launcher.dart';

import 'ai/ai_settings.dart';
import 'article_jobs.dart';
import 'bibliography.dart';
import 'controlled_editor.dart';
import 'editor_autocomplete.dart' show MentionQueryCache;
import 'entity_kinds.dart';
import 'enrich_ledger_retry.dart';
import 'metadata_lines.dart';
import 'graph.dart';
import 'knowledge_screen.dart';
import 'saved_searches.dart';
import 'markdown_article_import.dart';
import 'screenshots_ocr.dart';
import 'widgets/screenshot_strip.dart';
import 'bot_vault/decisions.dart';
import 'olt/olt_client.dart';
import 'olt/olt_cache.dart';
import 'connectors/olt_connector.dart';
import 'widgets/external_entity_page.dart';
import 'models.dart';
import 'month_calendar.dart';
import 'nextcloud_sync.dart';
import 'nextcloud_sync/conflict_choice.dart';
import 'package:tylog_core/validation.dart';
import 'platform_file_actions.dart';
import 'processing_jobs.dart';
import 'widgets/processing_screen.dart';
import 'pdf/pdf_reader_screen.dart';
import 'report.dart';
import 'retrieval/graph_svg.dart';
import 'retrieval/hybrid_search.dart';
import 'retrieval/semantic_search_controller.dart';
import 'rich_editor.dart';
import 'image_crop.dart';
import 'scanner.dart';
import 'package:tylog_core/search_index.dart';
import 'task_scheduler.dart';
import 'database/tylog_database.dart';
import 'import/legacy_import_plan.dart';
import 'import/legacy_import_runner.dart';
import 'vault.dart';
import 'vault_registry.dart';
import 'vault_storage.dart';
import 'voronoi_view.dart';
import 'widgets/app_version.dart';
import 'widgets/constants.dart';
import 'widgets/date_format.dart';
import 'widgets/note_picker_sheet.dart';
import 'widgets/share_from_sheet.dart';
import 'widgets/entity_header.dart';
import 'widgets/unified_board.dart';
import 'github/send_issue.dart';
import 'widgets/kind_icon_picker.dart';
import 'widgets/enrich_review.dart';
import 'widgets/linked_references.dart';
import 'widgets/entity_timeline.dart';
import 'widgets/entity_relationships.dart';
import 'widgets/dialogs.dart';
import 'widgets/editor_panel.dart';
import 'widgets/journal_feed.dart';
import 'widgets/links_panel.dart';
import 'widgets/loading.dart';
import 'widgets/reading_mode.dart';
import 'widgets/screenshot_view.dart';
import 'audio/audio_note_doc.dart';
import 'audio/audio_note_actions.dart';
import 'audio/processing_policy.dart';
import 'audio/transcript_jobs.dart';
import 'module_pack_io.dart';
import 'github/module_updates.dart';
import 'package:tylog_core/tylog_core.dart'
    show
        InstalledModule,
        ModuleProgress,
        listInstalledModules,
        moduleProgress,
        rescheduleModule;
import 'widgets/audio_inline_card.dart';
import 'widgets/audio_note_screen.dart';
import 'widgets/audio_shelf.dart';
import 'widgets/audio_sheets.dart';
import 'widgets/settings_sheet.dart';
import 'widgets/ds/app_sheet.dart';
import 'widgets/ds/app_section.dart';
import 'widgets/ds/app_tile.dart';
import 'widgets/nextcloud_connect_dialog.dart';
import 'widgets/snack.dart';
import 'desktop_updater.dart' as updater;
import 'widgets/sync_dashboard.dart';
import 'widgets/sync_status.dart';
import 'widgets/idea_hub.dart';
import 'widgets/vaults_sheet.dart';
import 'widgets/work_surface.dart';
import 'widgets/task_clock.dart';
import 'widgets/task_fields.dart' show setOneTaskField;
import 'widgets/virtual_plain_editor.dart';
import 'workspace_controller.dart';
import 'widgets/banner.dart';

export 'widgets/app_version.dart';
export 'widgets/date_format.dart';
export 'widgets/sync_status.dart';
export 'widgets/work_surface.dart'
    show TodayPage, continueReadingEligible, isTaskInTodayAgenda, isTaskOverdue;

part 'app_mobile/desktop_update_flow.dart';
part 'app_mobile/enrich_flow.dart';
part 'app_mobile/incoming_flow.dart';
part 'app_mobile/article_links_flow.dart';
part 'app_mobile/audio_flow.dart';
part 'app_mobile/markdown_import_flow.dart';
part 'app_mobile/module_flow.dart';
part 'app_mobile/vault_import_flow.dart';
part 'app_mobile/vault_lifecycle.dart';
part 'app_mobile/sync_flow.dart';
part 'app_mobile/knowledge_flow.dart';
part 'app_mobile/settings_flow.dart';
part 'app_mobile/magic_flow.dart';
part 'app_mobile/share_flow.dart';
part 'app_mobile/navigation_flow.dart';
part 'app_mobile/reading_flow.dart';

const _autoRelatedMarker = '// tylog:auto-related';

/// Removes the generated `// tylog:auto-related` block so a relink pass can
/// write a fresh one without duplicating.
///
/// Consumes only the block itself — its `== Related` heading and the
/// `#tylog.ref-note(...)` items — and keeps anything that follows. article-pipeline
/// writes the block last, so today nothing follows it in any of the 159 notes
/// that carry one; truncating to EOF was correct only for as long as that
/// holds. The moment a user types below their Related section, a relink would
/// delete what they wrote, with no error and nothing to undo.
/// Image asset paths a note's source references (`"assets/…png"`), as written.
Set<String> referencedAssetPaths(String source) => RegExp(
  r'"(/?assets/[^"]+\.(?:png|jpe?g|gif|svg|webp|bmp))"',
  caseSensitive: false,
).allMatches(source).map((m) => m.group(1)!).toSet();

/// Stable key of [referencedAssetPaths]: equal keys mean no asset to reload.
String referencedAssetKey(String source) =>
    (referencedAssetPaths(source).toList()..sort()).join('\n');

String stripAutoRelated(String source) {
  final marker = RegExp(
    '(?:^|\\n)${RegExp.escape(_autoRelatedMarker)}(?:\\r?\\n|\$)',
  ).firstMatch(source);
  if (marker == null) return source;
  final before = source
      .substring(0, marker.start)
      .replaceFirst(RegExp(r'[\r\n]+$'), '');
  final lines = source.substring(marker.end).split('\n');
  final relatedHeading = RegExp(r'^\s*=+\s');
  final refItem = RegExp(r'^\s*(?:[-+*]\s*)?#tylog\.ref-note\(');
  var i = 0;
  if (i < lines.length && relatedHeading.hasMatch(lines[i])) i++;
  while (i < lines.length &&
      (lines[i].trim().isEmpty || refItem.hasMatch(lines[i]))) {
    i++;
  }
  final tail = lines
      .sublist(i)
      .join('\n')
      .replaceFirst(RegExp(r'^[\r\n]+'), '')
      .trimRight();
  return tail.isEmpty ? before : '$before\n\n$tail';
}

String? refNoteHeading(String source) => RegExp(
  r'heading\s*:\s*"((?:\\.|[^"])*)"',
).firstMatch(source)?.group(1)?.replaceAll(r'\"', '"').replaceAll(r'\\', r'\');

/// The articles a "Relink vault" pass may rewrite.
///
/// An `llm_provider` property means article-pipeline generated that note's
/// auto-related block from a language model. Those suggestions beat
/// [suggestLinkTargets], which only matches tags/citations/titles exactly, and
/// both write the same `// tylog:auto-related` block — so relinking such a
/// note would silently replace better links with worse ones. Leave them alone.
List<NoteRef> relinkCandidates(Iterable<NoteRef> notes) => [
  for (final note in notes)
    if (note.kind == 'article' && !_hasLlmLinks(note)) note,
];

bool _hasLlmLinks(NoteRef note) {
  final provider = note.properties['llm_provider'];
  return provider is String && provider.isNotEmpty;
}

String? vaultEntryLocation(VaultEntry? entry) =>
    entry?.treeUri ??
    (entry == null || entry.path.isEmpty ? entry?.name : entry.path);

ThemeMode themeModeFromName(String name) => switch (name) {
  'light' => ThemeMode.light,
  'dark' => ThemeMode.dark,
  _ => ThemeMode.system,
};

String themeModeName(ThemeMode mode) => switch (mode) {
  ThemeMode.light => 'light',
  ThemeMode.dark => 'dark',
  ThemeMode.system => 'system',
};

class TyLogApp extends StatefulWidget {
  const TyLogApp({super.key});

  @override
  State<TyLogApp> createState() => _TyLogAppState();
}

class _TyLogAppState extends State<TyLogApp> {
  // App-wide light/dark/system selection. Held in the tree (not a global) so it
  // is disposed with the app and cannot leak state between widget tests. The
  // persisted value in [VaultRegistry.themeMode] flows up from HomeScreen once
  // the registry has loaded, via [_setThemeMode].
  ThemeMode _themeMode = ThemeMode.system;

  void _setThemeMode(ThemeMode mode) {
    if (mode == _themeMode) return;
    setState(() => _themeMode = mode);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TyLog',
      theme: tyLogTheme(Brightness.light),
      darkTheme: tyLogTheme(Brightness.dark),
      themeMode: _themeMode,
      home: HomeScreen(
        themeMode: _themeMode,
        onThemeModeChanged: _setThemeMode,
      ),
    );
  }
}

/// Phones stop the foreground poll in the background (battery; the
/// background worker takes over); desktops keep it.
bool stopsPollingInBackground(TargetPlatform platform) =>
    platform == TargetPlatform.android || platform == TargetPlatform.iOS;

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.themeMode = ThemeMode.system,
    this.onThemeModeChanged,
    this.onCompilePdf,
    this.onSharePdf,
    this.databaseOpener,
    this.databaseCloser,
    this.startup,
  });

  /// Current app-wide appearance and the callback to change it, both owned by
  /// [TyLogApp]. Optional so tests can mount HomeScreen without wiring theming.
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final Future<Uint8List> Function({
    required String source,
    required Map<String, Uint8List> files,
    String paper,
  })?
  onCompilePdf;
  final Future<void> Function(String name, Uint8List pdf)? onSharePdf;
  final Future<TyLogDatabase> Function()? databaseOpener;
  final Future<void> Function(TyLogDatabase database)? databaseCloser;
  final Future<void> Function()? startup;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late final Future<TyLogDatabase?> database;
  final Map<String, Future<TyLogDatabase?>> _vaultDatabases = {};

  /// Recordings whose chip is already in the note but whose file/note are
  /// still being written (startup index and sync can delay SAF writes for
  /// minutes): playback and the waveform read from memory meanwhile.
  final Map<String, ({Uint8List bytes, List<int> peaks})> _pendingAudio = {};
  final Map<String, Future<void>> _audioNoteTasks = {};

  /// Attachments picked but still being copied into the vault: [_readAsset]
  /// serves them from the picked file, and opening waits on the copy.
  final Map<String, File> _pendingAttach = {};
  final Map<String, Future<void>> _attachTasks = {};
  final List<TyLogDatabase> _additionalDatabases = [];
  bool _exiting = false;
  Future<void>? _shutdownFuture;
  Future<void>? _databaseCloseFuture;
  final _mentionQueryCache = MentionQueryCache();
  final _actionableSidecars = ActionableSidecarSummary();
  final Set<String> _reservedTaskIds = {};
  final Set<String> _botDecidedItems = {};
  final sourceController = TextEditingController();
  final sourceEditorKey = GlobalKey<EditorState>();
  var _plainEditorKey = GlobalKey<VirtualPlainEditorState>();
  final _plainHistoryRevision = ValueNotifier<int>(0);
  late final TyLogEditingController richController;
  late final WorkspaceController workspace;
  // Launch lands in the journal editor with today's file open.
  String mode = 'normal';
  bool _editScreenshot = false;
  String? _searchRevealQuery;
  int? _searchRevealOffset;
  int _searchRevealGeneration = 0;

  /// Test seam for the asynchronous export path; the production entry point is
  /// the Share as PDF item in the More menu.
  @visibleForTesting
  Future<void> sharePdfForTesting() => _sharePdf();
  // Graph overview mode: 'local' (default), 'conceptMap', or 'allFiles'.
  String _graphMode = 'local';
  String? _graphSelectedPath;
  // Concept/note path the local graph is rooted at when expanded from the map.
  String? _graphFocusPath;

  final _graphCache =
      <
        ({
          int revision,
          int pendingRevision,
          String mode,
          String? focus,
          String? current,
        }),
        NoteGraph
      >{};
  int _graphCacheRevision = -1;

  /// The graph for the current pane, built at most once per set of inputs.
  ///
  /// Keyed on [WorkspaceController.indexRevision] rather than the index object:
  /// the controller retains the index in place, so its identity never changes
  /// and an `identical` check would cache the first graph forever.
  /// The cached review-status enrich decision behind a proposed graph edge.
  EnrichDecision? _pendingEnrichDecision(String from, String to) {
    final view = _enrichDecisions;
    if (view == null || view.$1 != from) return null;
    for (final decision in view.$2.decisions) {
      if (decision.status == EnrichStatus.review &&
          decision.target?.path == to) {
        return decision;
      }
    }
    return null;
  }

  NoteGraph _memoizedGraph(String? current) {
    final graphFocus = _graphFocusPath ?? current;
    final enrichView = _enrichDecisions;
    final pending = enrichView != null && enrichView.$1 == graphFocus
        ? [
            for (final decision in enrichView.$2.decisions)
              if (decision.status == EnrichStatus.review &&
                  decision.target != null)
                (enrichView.$1, decision.target!.path),
          ]
        : const <(String, String)>[];
    final key = (
      revision: workspace.indexRevision,
      pendingRevision: Object.hashAll(pending),
      mode: _graphMode,
      focus: _graphFocusPath,
      current: current,
    );
    if (_graphCacheRevision != workspace.indexRevision) {
      _graphCache.clear();
      _graphCacheRevision = workspace.indexRevision;
    }
    final cached = _graphCache[key];
    if (cached != null) return cached;
    // ponytail: wipe-when-full cap; local-graph keys grow per opened note.
    if (_graphCache.length >= 8) _graphCache.clear();
    final idx = index!;
    final built = switch (_graphMode) {
      // Overview = the 40 busiest topics; ~200 labelled hubs was unreadable.
      'conceptMap' => boundGraphForLayout(
        buildConceptMap(idx),
        maxNodes: 40,
        maxEdges: 120,
      ),
      // The treemap renders straight from the index; no note graph needed.
      'voronoi' => const NoteGraph(nodes: [], edges: []),
      'allFiles' => buildNoteGraph(idx),
      'timeline' => buildTimelineGraph(idx, {
        for (final r in _mergedRecent()) r.path: isoDay(r.openedAt),
      }),
      // No note open yet: focused view would be empty, show the overview.
      _ when (_graphFocusPath ?? current) == null => buildConceptMap(idx),
      _ => buildLocalNoteGraph(idx, graphFocus, pending: pending),
    };
    final bounded = boundGraphForLayout(built, currentPath: current);
    _graphCache[key] = bounded;
    return bounded;
  }

  int primaryDestination = 0;
  int _libraryTab = 0;
  final _backViews =
      <
        ({
          String mode,
          int destination,
          int libraryTab,
          KnowledgeView? knowledge,
          String? searchQuery,
        })
      >[];

  Future<void> _clockMutation = Future<void>.value();

  TaskRef? get _runningTask {
    final tasks =
        (index?.tasks ?? const <TaskRef>[])
            .where((task) => task.runningClock != null)
            .toList()
          ..sort(
            (a, b) => (DateTime.tryParse(a.runningClock!.start) ?? DateTime(0))
                .compareTo(
                  DateTime.tryParse(b.runningClock!.start) ?? DateTime(0),
                ),
          );
    return tasks.lastOrNull;
  }

  /// The day the arrows have stepped to but not opened yet. The header reads
  /// this first so a tap moves the date immediately.
  DateTime? _navDay;
  Timer? _navDebounce;
  int _openGeneration = 0;

  double _swipeDx = 0;

  @visibleForTesting
  Future<void> openReferenceForTesting(String source) =>
      _handleAtomSource(source, allowEdit: false);

  @visibleForTesting
  Future<NoteRef?> createEntityForTesting() => _createEntity();

  @visibleForTesting
  Future<void> saveLinksAsArticlesForTesting() => _saveLinksAsArticles();

  @visibleForTesting
  Future<int> relinkArticlesForTesting() => _relinkArticles(vault!);

  @visibleForTesting
  Future<void> refreshNoteAssetsForTesting(
    String source, {
    bool force = false,
  }) => _refreshNoteAssets(source, force: force);

  @visibleForTesting
  Future<void> refreshArticleJobsForTesting() => _refreshArticleJobs();

  void _rememberView({
    KnowledgeView? knowledge,
    String? searchQuery,
    bool today = false,
  }) {
    _backViews.add((
      mode: today ? 'today' : mode,
      destination: primaryDestination,
      libraryTab: _libraryTab,
      knowledge: knowledge,
      searchQuery: searchQuery,
    ));
  }

  void _enterView(String next) {
    if (mode == next) return;
    _rememberView();
    setState(() => mode = next);
  }

  void _back() {
    if (_backViews.isEmpty) {
      unawaited(_showToday());
      return;
    }
    ++_destinationGeneration;
    ++_openGeneration;
    if (mode == 'source' || mode == 'split') {
      richController.loadSource(sourceController.text);
    }
    final previous = _backViews.removeLast();
    if (previous.mode == 'today') {
      unawaited(_showToday());
      return;
    }
    setState(() {
      mode = previous.mode;
      primaryDestination = previous.destination;
      _libraryTab = previous.libraryTab;
    });
    if (previous.knowledge case final view?) {
      unawaited(
        _showKnowledge(initialView: view, initialQuery: previous.searchQuery),
      );
    }
  }

  String? selectedTag;
  VaultRegistry? vaultRegistry;
  final taskScheduler = TaskScheduler();
  Timer? _previewDebounceTimer;
  Timer? _semanticRefreshTimer;
  Timer? _screenshotsApplyTimer;
  SemanticSearchController? _semantic;
  String? _debouncedPreviewSource;
  String? _pendingPreviewSource;
  String? _debouncedPreviewWidth;
  String? _pendingPreviewWidth;
  static const _previewPixelsPerPt = 2.0;
  // Path/date of the daily note last opened via _openToday(), so a resume
  // after midnight can detect the Today screen is showing a stale day.
  String? _todayNotePath;
  DateTime? _todayOpenedAt;
  // Last syncError/conflict count a snackbar fired for, so background sync
  // polling (which calls notifyListeners repeatedly while unchanged) doesn't
  // spam a snackbar per tick — only a genuinely new failure/conflict does.
  String? _lastSnackedSyncError;
  int _lastSnackedConflictCount = 0;
  bool _newPageInFlight = false;
  final _oltClient = OltClient();
  Map<String, List> _oltCache = const {};
  Set<String> _oltDecided = <String>{};
  DateTime? _oltLastSync;
  bool _oltCacheLoading = false;
  OltCacheMeta _oltMeta = const OltCacheMeta();
  bool _oltSignedOut = false;

  void _loadOltForToday() {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    if (_oltCacheLoading) return;
    if (_oltLastSync != null &&
        DateTime.now().difference(_oltLastSync!) <
            const Duration(minutes: 15)) {
      return;
    }
    _oltLastSync = DateTime.now();
    _oltCacheLoading = true;
    unawaited(() async {
      try {
        final dir = await oltCacheDirectory();
        final cached = await loadOltCache(dir);
        final decided = await readDecidedOltIds(dir);
        final meta = await loadOltCacheMeta(dir);
        final signedOut = await _oltClient.session == null;
        if (mounted) {
          setState(() {
            _oltCache = cached;
            _oltDecided = decided;
            _oltMeta = meta;
            _oltSignedOut = signedOut;
            _setOltEntities(cached);
          });
        }
        final result = await refreshOltCache(_oltClient, dir);
        if (mounted) {
          setState(() {
            _oltCache = result.cache;
            _oltMeta = result.meta;
            _oltSignedOut = result.signedOut;
            _setOltEntities(result.cache);
          });
        }
      } catch (_) {
      } finally {
        _oltCacheLoading = false;
      }
    }());
  }

  void _setOltEntities(Map<String, List> cache) {
    final connector = OltConnector(() async => cache);
    unawaited(
      connector.refresh().then((_) {
        if (mounted) workspace.setExternalEntities(connector.entities());
      }),
    );
  }

  void _markOltDecided(String id) {
    setState(() => _oltDecided = {..._oltDecided, id});
  }

  Vault? get vault => workspace.vault;
  VaultIndex? get index => workspace.entityIndex;
  set index(VaultIndex? value) => workspace.index = value;

  List<NoteRef>? _pagedLibraryNotes;
  int _pagedLibraryRevision = -1;
  Vault? _pagedLibraryVault;
  bool _pagedLibraryLoading = false;
  String? get note => workspace.note;
  set note(String? value) => workspace.note = value;
  String get status => workspace.status;
  set status(String value) => workspace.status = value;
  bool get dirty =>
      workspace.dirty ||
      richController.isComposing ||
      (_plainEditorKey.currentState?.hasPendingChanges ?? false);
  String get helperSource => workspace.helperSource;
  Map<String, Uint8List> get typstPackageFiles => workspace.typstPackageFiles;
  String get bibliographySource => workspace.bibliographySource;
  set bibliographySource(String value) => workspace.bibliographySource = value;
  String get zoteroBibSource => workspace.zoteroBibSource;
  set zoteroBibSource(String value) => workspace.zoteroBibSource = value;
  NextcloudConfig? get cloud => workspace.cloud;
  set cloud(NextcloudConfig? value) => workspace.cloud = value;
  PkmsSearchIndex get searchIndex => workspace.searchIndex;
  PkmsValidationReport? get validation => workspace.validation;
  SyncResult? get lastSync => workspace.lastSync;
  List<SyncConflict> get syncConflicts => workspace.syncConflicts;
  DateTime? get lastSyncAt => workspace.lastSyncAt;
  String? get syncError => workspace.syncError;
  set syncError(String? value) => workspace.syncError = value;
  bool get syncing => workspace.syncing;
  String? get syncStage => workspace.syncStage;
  bool? get storageHealthy => workspace.storageHealthy;
  bool get rebuilding => workspace.rebuilding;
  double? get rebuildProgress => workspace.rebuildProgress;

  final _statusPillBounds = GlobalKey();
  final _taskClockBounds = GlobalKey();
  final _captureFocus = FocusNode();
  final _todayStorage = PageStorageBucket();
  bool _dailyMoreExpanded = false;
  String? _timestampCapturePath;
  (Vault?, String?)? _editorNote;
  bool _plainLongEditor = false;
  bool get _usePlainLongEditor =>
      note != _timestampCapturePath && _plainLongEditor;
  static const _shareChannel = MethodChannel('org.tylog.tylog/share');
  bool _handlingShare = false;
  List<ArticleJob> _articleJobs = const [];
  final _processingJobs = ProcessingJobs();
  int _articleJobsGeneration = 0;
  (Vault?, bool, int)? _jobsRevision;

  Future<void> _refreshArticleJobs() async {
    final generation = ++_articleJobsGeneration;
    final currentVault = vault;
    unawaited(_processingJobs.refresh(currentVault?.storage));
    if (currentVault == null) {
      _articleJobs = const [];
      return;
    }
    try {
      final jobs = await loadArticleJobs(currentVault.storage);
      if (mounted &&
          identical(vault, currentVault) &&
          generation == _articleJobsGeneration) {
        final previousJobs = _articleJobs;
        setState(() => _articleJobs = jobs);
        unawaited(_relinkFinishedArticles(currentVault, previousJobs, jobs));
      }
    } catch (error) {
      if (mounted) showSnack(context, 'Could not read article jobs: $error');
    }
  }

  void _processingJobWritten(Vault currentVault, String path) {
    if (!mounted || !identical(vault, currentVault)) return;
    currentVault.restoreWriteMarkers(path, stale: false, pendingSync: true);
    workspace.queueCloudSync();
    unawaited(_refreshArticleJobs());
  }

  Future<void> _showProcessing() async {
    if (vault == null) return;
    unawaited(_processingJobs.refresh(vault!.storage));
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ProcessingScreen(
          jobs: _processingJobs,
          titleForPath: (path) => index?.notesByPath[path]?.title,
          onQueued: (path) {
            if (vault case final currentVault?) {
              _processingJobWritten(currentVault, path);
            }
          },
        ),
      ),
    );
  }

  void _showProcessingQueued() =>
      showProcessingQueued(context, () => unawaited(_showProcessing()));

  Future<void> _handlePendingShares() async {
    if (_handlingShare || vault == null || !mounted) return;
    _handlingShare = true;
    try {
      while (mounted && vault != null) {
        final data = await _shareChannel.invokeMapMethod<String, String>(
          'getPendingShare',
        );
        if (data == null || !mounted || vault == null) break;
        if (data['action'] == 'record') {
          // The take lands in today's log as a player card.
          _navDebounce?.cancel();
          _navDay = null;
          final inToday = await _openToday();
          if (inToday && mounted) {
            _showEditor();
            setState(() => primaryDestination = 0);
          }
          await _recordAudioNote(inline: inToday);
          continue;
        }
        final path = data['path'];
        final mime = data['mime'] ?? '';
        final text = data['text'] ?? '';
        final article = SharedArticle.parse(text, title: data['title']);
        final targetVault = vault!;
        final audioNote = path != null && isAudioPath(path);
        final choice = await showModalBottomSheet<String>(
          context: context,
          showDragHandle: false,
          builder: (context) => AppSheet(
            title: 'Share',
            children: [
              ListTile(
                title: Text(
                  path != null
                      ? data['name'] ?? path.split('/').last
                      : article?.title ?? article?.url ?? text,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (audioNote)
                ListTile(
                  leading: const Icon(Icons.audiotrack),
                  title: const Text('Save as audio note'),
                  subtitle: const Text('Default'),
                  onTap: () => Navigator.pop(context, 'audio'),
                ),
              if (path != null)
                ListTile(
                  leading: Icon(
                    mime.startsWith('image/')
                        ? Icons.image_outlined
                        : mime.startsWith('audio/') && !audioNote
                        ? Icons.audiotrack
                        : Icons.attach_file,
                  ),
                  title: const Text('Attach to today'),
                  subtitle: audioNote ? null : const Text('Default'),
                  onTap: () => Navigator.pop(context, 'attach'),
                ),
              if (path == null && article != null)
                ListTile(
                  leading: const Icon(Icons.article_outlined),
                  title: const Text('Save as article'),
                  subtitle: const Text('Fetch and convert the page to text'),
                  trailing: const Text('Default'),
                  onTap: () => Navigator.pop(context, 'article'),
                ),
              if (path == null)
                ListTile(
                  leading: const Icon(AppIcons.today),
                  title: Text(
                    article == null ? 'Add to today' : 'Add link to today',
                  ),
                  subtitle: article == null ? const Text('Default') : null,
                  onTap: () => Navigator.pop(context, 'today'),
                ),
            ],
          ),
        );
        if (!mounted || !identical(vault, targetVault)) continue;
        if (choice == 'article' && article != null) {
          await article.enqueue(targetVault.storage);
          _processingJobWritten(targetVault, article.path);
          if (mounted) _showProcessingQueued();
        } else if (choice == 'audio' && path != null) {
          await _saveSharedAudio(File(path));
        } else if (choice == 'attach' && path != null) {
          if (!await _captureTimestamp()) continue;
          if (!mounted || !identical(vault, targetVault)) continue;
          final asset = await _attachFile(File(path));
          if (asset != null && isAudioPath(asset)) {
            await _openAudioAsset(asset, open: false, shared: true);
          }
        } else if (choice == 'today') {
          if (!await _captureTimestamp()) continue;
          if (!mounted || !identical(vault, targetVault)) continue;
          richController.value = TextEditingValue(
            text: '${richController.text}$text',
            selection: TextSelection.collapsed(
              offset: richController.text.length + text.length,
            ),
          );
        }
      }
    } catch (error) {
      if (mounted) showSnack(context, 'Could not save share: $error');
    } finally {
      _handlingShare = false;
    }
  }

  /// Last (vault, note, index revision) enrichment ran for, the vault whose
  /// recent days got their blocks, and the open day's decisions.
  Object? _enrichRevision;
  (Vault, int, DateTime, EnrichMemory)? _enrichMemoryCache;
  (Object, _EnrichView)? _enrichMemo;
  (String, _EnrichView)? _enrichDecisions;
  bool _enrichBusy = false;
  final _enrichShown = <(Vault, String, String, String)>{};
  Future<void> _enrichLedgerWrite = Future.value();
  final _enrichRetry = EnrichLedgerRetry();
  DateTime? _articleRelinkAt;

  // setState is @protected; this shim lets the flow extensions in
  // app_mobile/*.dart trigger rebuilds without tripping the analyzer.
  void _rebuild(VoidCallback fn) => setState(fn);

  @override
  void initState() {
    super.initState();
    database = widget.databaseOpener != null
        ? widget.databaseOpener!()
        : Platform.environment.containsKey('FLUTTER_TEST')
        ? Future.value(null)
        : openDatabase();
    TyLogEditingController.audioBuilder = _audioCard;
    if (Platform.isMacOS && !Platform.environment.containsKey('FLUTTER_TEST')) {
      // Another device may change the wanted screenshot mode (ai.json syncs);
      // this Mac applies it. One small file read a minute.
      _screenshotsApplyTimer = Timer.periodic(
        const Duration(seconds: 60),
        (_) => unawaited(_applyWantedScreenshots()),
      );
      Timer(
        const Duration(seconds: 10),
        () => unawaited(_applyWantedScreenshots()),
      );
    }
    richController = TyLogEditingController(
      source: '',
      onSourceChanged: _acceptRichSource,
      onError: _richEditorError,
      onProtectedTap: (id) => unawaited(_tapProtected(id)),
      onProtectedLongPress: (id) => unawaited(_longPressProtected(id)),
      imageResolver: _readAsset,
      imageWriter: (path, bytes) => saveImageCrop(vault!.storage, path, bytes),
      resolveKind: _resolveKind,
      nextTaskId: (text) async {
        final opened = vault;
        final file = note;
        if (opened == null) throw StateError('No vault is open');
        final reserved = {
          ..._reservedTaskIds,
          for (final call in locateTypstCalls(
            richController.document.toSource(),
            names: const {'tylog.task'},
          ))
            if (taskField(call.source, 'id') case final String id) id,
        };
        _reservedTaskIds.addAll(reserved);
        final id = await opened.nextTaskId(
          text,
          reserved: _reservedTaskIds,
          // The open note covers today's IDs even while the startup index is absent.
          knownIds: {for (final task in index?.tasks ?? <TaskRef>[]) task.id},
        );
        _reservedTaskIds.add(id);
        if (!identical(vault, opened) || note != file) {
          throw StateError('The vault changed');
        }
        return id;
      },
      beforeTaskDoing: (id) async {
        final opened = vault;
        final file = note!;
        await _queueClockMutation(() => _stopOtherDoingTasks(file));
        if (!identical(vault, opened) ||
            note != file ||
            (index?.tasks.any(
                  (t) => t.notePath != file && t.runningClock != null,
                ) ??
                false)) {
          throw StateError('Could not stop the previous task');
        }
      },
    );
    workspace = WorkspaceController(
      taskScheduler: taskScheduler,
      isComposing: () => richController.isComposing,
      databaseForVault: _databaseForVault,
    )..addListener(_workspaceChanged);
    kindRegistry.addListener(_kindRegistryChanged);
    WidgetsBinding.instance.addObserver(this);
    _shareChannel.setMethodCallHandler((call) async {
      if (call.method == 'shareAvailable') await _handlePendingShares();
    });
    unawaited(
      (widget.startup ?? _open)().then((_) async {
        await _refreshArticleJobs();
        if (Platform.isAndroid) await _handlePendingShares();
      }),
    );
    // One silent update check per launch on supported self-updating desktops.
    // Skipped under `flutter test`: it would hit GitHub and leave an unawaited
    // rootBundle/HTTP load pending past teardown, wedging the asset channel for
    // the next test (appVersion hangs).
    if ((Platform.isMacOS || updater.windowsSelfUpdatable()) &&
        !Platform.environment.containsKey('FLUTTER_TEST')) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(_checkForUpdates(silent: true)),
      );
    }
  }

  @override
  void dispose() {
    _screenshotsApplyTimer?.cancel();
    _openGeneration++;
    _captureFocus.dispose();
    _plainHistoryRevision.dispose();
    _shareChannel.setMethodCallHandler(null);
    _previewDebounceTimer?.cancel();
    _semanticRefreshTimer?.cancel();
    _semantic?.dispose();
    _processingJobs.dispose();
    WidgetsBinding.instance.removeObserver(this);
    kindRegistry.removeListener(_kindRegistryChanged);
    workspace
      ..removeListener(_workspaceChanged)
      ..dispose();
    richController.dispose();
    sourceController.dispose();
    unawaited(_closeDatabases());
    super.dispose();
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    try {
      await (_shutdownFuture ??= _shutdown()).timeout(
        const Duration(seconds: 3),
      );
    } catch (error, stack) {
      debugPrint('Desktop shutdown did not finish: $error\n$stack');
    }
    return AppExitResponse.exit;
  }

  Future<void> _shutdown() async {
    setState(() => _exiting = true);
    _openGeneration++;
    _previewDebounceTimer?.cancel();
    _semanticRefreshTimer?.cancel();
    _navDebounce?.cancel();
    workspace.removeListener(_workspaceChanged);
    final semantic = _semantic;
    _semantic = null;
    // Unmount preview widgets so their owned Typst engines/documents dispose.
    final frame = WidgetsBinding.instance.endOfFrame;
    try {
      await Future.wait([
        workspace.shutdown(),
        if (semantic != null) semantic.shutdown(),
      ]);
    } finally {
      semantic?.dispose();
      await _closeDatabases();
      await frame;
    }
  }

  Future<void> _closeDatabases() =>
      _databaseCloseFuture ??= _closeOwnedDatabases();

  Future<void> _closeOwnedDatabases() async {
    await Future.wait(
      _vaultDatabases.values.map((future) => future.catchError((_) => null)),
    );
    final primary = await database.catchError((_) => null);
    // Start every close even if another connection hangs or fails.
    await Future.wait([
      for (final db in {?primary, ..._additionalDatabases})
        Future<void>.sync(
          () => (widget.databaseCloser ?? (value) => value.close())(db),
        ),
    ]);
  }

  Future<TyLogDatabase?> _databaseForVault(VaultEntry entry) => _exiting
      ? (_vaultDatabases[entry.id] ?? Future.value(null))
      : _vaultDatabases.putIfAbsent(entry.id, () async {
          final primary = await database;
          if (primary == null || await primary.claimVault(entry.id)) {
            return primary;
          }
          if (widget.databaseOpener != null) {
            throw StateError(
              'The test database is already bound to another vault',
            );
          }
          final scoped = await openDatabaseForVault(entry.id);
          try {
            await scoped.claimVault(entry.id);
          } catch (_) {
            await scoped.close();
            rethrow;
          }
          _additionalDatabases.add(scoped);
          return scoped;
        });

  void _kindRegistryChanged() {
    if (mounted) setState(() {});
  }

  void _workspaceChanged() {
    if (!mounted || _exiting) return;
    if (workspace.entry == null) {
      _semantic?.dispose();
      _semantic = null;
    }
    if (sourceController.text != workspace.source) {
      // A save/sync round-trip can hand back a cosmetically different but
      // semantically identical source — e.g. trailing blank lines left by an
      // exited list. Reloading the rich editor then would clobber its live
      // state, wiping the empty line the user just opened to type on. Only
      // reload when content, inline formatting, atoms or the note header changes.
      final incoming = TyLogDocument.parse(workspace.source);
      final current = richController.document;
      final changed =
          incoming.prefix != current.prefix ||
          incoming.visibleText != current.visibleText ||
          !sameStyledText(incoming, current) ||
          !listEquals(
            locateTypstCalls(
              workspace.source,
              names: const {'tylog.task'},
            ).map((c) => c.source).toList(),
            locateTypstCalls(
              current.toSource(validate: false),
              names: const {'tylog.task'},
            ).map((c) => c.source).toList(),
          );
      sourceController.text = workspace.source;
      if (changed) {
        final oldText = richController.text;
        final oldSelection = richController.selection;
        richController.foldScope = note;
        richController.loadSource(workspace.source);
        if (oldSelection.isValid && richController.text == oldText) {
          richController.selection = oldSelection;
        }
      }
    }
    if (_editorNote != (vault, note)) {
      _editorNote = (vault, note);
      _plainEditorKey = GlobalKey<VirtualPlainEditorState>();
      _plainLongEditor = shouldUseVirtualPlainEditor(richController);
    }
    if (_jobsRevision?.$1 != vault ||
        _jobsRevision?.$3 != workspace.indexRevision) {
      _queueSemanticRefresh();
    }
    final jobsRevision = (vault, syncing, workspace.indexRevision);
    if (_jobsRevision != jobsRevision) {
      _jobsRevision = jobsRevision;
      unawaited(_refreshArticleJobs());
    }
    if (index != null) {
      _queueEnrichRefresh();
      _queueArticleRelink();
    }
    if (Platform.isAndroid) unawaited(_handlePendingShares());
    _maybeSnackNewSyncTrouble();
    _refreshPagedLibraryNotes();
    setState(() {});
  }

  void _queueSemanticRefresh() {
    _semanticRefreshTimer?.cancel();
    _semanticRefreshTimer = Timer(const Duration(milliseconds: 300), () {
      unawaited(_ensureSemanticController(refresh: true));
    });
  }

  Future<void> _ensureSemanticController({bool refresh = false}) async {
    final entry = workspace.entry;
    if (entry == null) return;
    final db = await _databaseForVault(entry);
    if (!mounted || _exiting || workspace.entry != entry || db == null) return;
    var controller = _semantic;
    if (controller == null || !identical(controller.db, db)) {
      controller?.dispose();
      final support = await getApplicationSupportDirectory();
      if (!mounted || _exiting || workspace.entry != entry) return;
      controller = SemanticSearchController(
        db: db,
        modelRoot: Directory(
          '${support.path}/models/multilingual-e5-small-ccc66d3',
        ),
      );
      _semantic = controller;
      await controller.init();
    }
    if (refresh && controller.searchable) {
      unawaited(controller.refreshNotes());
    }
  }

  void _refreshPagedLibraryNotes() {
    final opened = vault;
    if (!identical(opened, _pagedLibraryVault)) {
      _pagedLibraryVault = opened;
      _pagedLibraryNotes = null;
      _pagedLibraryRevision = -1;
    }
    final revision = workspace.indexRevision;
    if (_pagedLibraryLoading || revision == _pagedLibraryRevision) return;
    _pagedLibraryRevision = revision;
    _pagedLibraryLoading = true;
    unawaited(() async {
      final notes = await _pagedPickerNotes();
      if (mounted &&
          identical(opened, vault) &&
          revision == workspace.indexRevision &&
          notes != null) {
        setState(() => _pagedLibraryNotes = notes);
      }
      _pagedLibraryLoading = false;
      if (mounted &&
          (revision != workspace.indexRevision || !identical(opened, vault))) {
        _refreshPagedLibraryNotes();
      }
    }());
  }

  void _maybeSnackNewSyncTrouble() {
    final error = syncError;
    if (error != null && error != _lastSnackedSyncError) {
      showSnack(context, 'Sync failed: $error');
    }
    _lastSnackedSyncError = error;

    final conflictCount = syncConflicts.length;
    if (conflictCount > _lastSnackedConflictCount) {
      showSnack(
        context,
        conflictCount == 1
            ? 'Sync conflict needs attention'
            : '$conflictCount sync conflicts need attention',
      );
    }
    _lastSnackedConflictCount = conflictCount;
  }

  VaultEntry? get _activeRegistryEntry {
    final registry = vaultRegistry;
    if (registry == null) return null;
    return registry.entries
        .where((entry) => entry.id == registry.activeId)
        .firstOrNull;
  }

  Directory? get _localVaultDirectory {
    return workspace.localDirectory;
  }

  Future<bool> _save({bool syncAfter = true}) async {
    if (workspace.noteIsExtension) return true;
    if (richController.isComposing) {
      richController.value = richController.value.copyWith(
        composing: TextRange.empty,
      );
    }
    _plainEditorKey.currentState?.flush();
    if (_currentSource() != workspace.source) {
      workspace.source = _currentSource();
    }
    return workspace.save(syncAfter: syncAfter);
  }

  void _queueCloudSync() => workspace.queueCloudSync();

  void _startCloudPolling() => workspace.startCloudPolling();

  void _stopCloudPolling() => workspace.stopCloudPolling();

  bool get _editingRecently => workspace.editingRecently;

  void _queueAutosave() {
    if (workspace.noteIsExtension) return;
    _refreshNoteAssets(_currentSource());
    workspace.edit(_currentSource());
  }

  String _currentSource() => sourceController.text;

  /// Vault-relative asset bytes for the open note, loaded by [_loadNoteAssets]
  /// so the synchronous [_typstFiles] can hand them to the Typst compiler.
  final Map<String, Uint8List> _noteAssetFiles = {};
  int _assetRevision = 0;
  String? _loadedAssetKey;
  Object? _loadedAssetVault;
  Future<void>? _assetLoadFuture;

  /// The `kind` of the note a `#tylog.ref-note("target")` points at, or a
  /// resolution-status sentinel; null when the index or resolver is absent.
  String? _resolveKind(String target) {
    final ix = index;
    // The retained resolver, never a fresh one: this runs once per mention chip
    // per span rebuild, and constructing a LinkResolver is O(vault). It is built
    // wherever the index is published, so it is non-null whenever `ix` is.
    final resolved = workspace.linkResolver?.resolve(target);
    if (ix == null || resolved == null) return null;
    return switch (resolved.status) {
      LinkResolutionStatus.resolved => ix.notesByPath[resolved.path]?.kind,
      // A class picked from the calendar exists before the index catches up.
      LinkResolutionStatus.unresolved =>
        workspace.feedEvents.any((e) => e.id == target)
            ? 'event'
            : 'unresolved',
      LinkResolutionStatus.ambiguous => 'ambiguous',
    };
  }

  /// Opens a `mailto:`/`http(s)` URL (e.g. an entity's email) in the OS handler.
  void _openUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    unawaited(
      canLaunchUrl(uri).then((ok) {
        if (ok) launchUrl(uri);
      }),
    );
  }

  /// Reads a vault asset (e.g. an article image) for inline rendering; null on
  /// any failure so the editor falls back to the path chip.
  Future<Uint8List?> _readAsset(String path) async {
    final v = vault;
    if (v == null) return null;
    try {
      final clean = path.replaceFirst(RegExp(r'^/+'), '');
      final pending = _pendingAttach[clean];
      if (pending != null) return await pending.readAsBytes();
      return await v.storage.readBytesNow(clean);
    } catch (_) {
      return null;
    }
  }

  /// Loads every `assets/...` image referenced by [source] into
  /// [_noteAssetFiles] (keyed with and without a leading slash) so `#image(...)`
  /// resolves at compile time. Async; triggers a rebuild when it finishes.
  Future<void> _refreshNoteAssets(String source, {bool force = false}) {
    final key = referencedAssetKey(source);
    if (!force &&
        _assetLoadFuture != null &&
        key == _loadedAssetKey &&
        identical(vault, _loadedAssetVault) &&
        referencedAssetPaths(source).every(
          (p) =>
              _noteAssetFiles.containsKey(p.replaceFirst(RegExp(r'^/+'), '')),
        )) {
      return _assetLoadFuture!;
    }
    _loadedAssetKey = key;
    _loadedAssetVault = vault;
    final revision = ++_assetRevision;
    final future = _loadNoteAssets(source, revision: revision);
    _assetLoadFuture = future;
    unawaited(future);
    return future;
  }

  Future<void> _loadNoteAssets(String source, {required int revision}) async {
    final v = vault;
    final loaded = <String, Uint8List>{};
    if (v == null) {
      if (mounted && revision == _assetRevision) {
        _noteAssetFiles.clear();
        setState(() {});
      }
      return;
    }
    final paths = referencedAssetPaths(source);
    for (final path in paths) {
      final relative = path.replaceFirst(RegExp(r'^/+'), '');
      try {
        final bytes = await v.storage.readBytes(relative);
        loaded[relative] = bytes;
        loaded['/$relative'] = bytes;
      } catch (_) {
        // Missing asset: leave it out; the compiler reports file-not-found.
      }
    }
    if (!mounted || revision != _assetRevision || vault != v) return;
    _noteAssetFiles
      ..clear()
      ..addAll(loaded);
    setState(() {});
  }

  Map<String, Uint8List> _typstFiles() {
    final files = <String, Uint8List>{};
    // Typst resolves both root-relative and absolute forms; register each.
    void put(String path, String text) {
      final bytes = Uint8List.fromList(utf8.encode(text));
      files[path] = bytes;
      files['/$path'] = bytes;
    }

    put('_system/tylog.typ', helperSource);
    files.addAll(_noteAssetFiles);
    files.addAll(typstPackageFiles);
    if (bibliographySource.isNotEmpty) {
      put(Vault.bibliographyPath, bibliographySource);
    }
    if (zoteroBibSource.trim().isNotEmpty) {
      put(Vault.zoteroBibPath, zoteroBibSource);
    }
    return files;
  }

  /// Preview-only source: cited notes get a bibliography section appended so
  /// `@key` references resolve; the stored note is never modified.
  String _previewSource() {
    final source = sourceController.text;
    final bib = bibliographySource.trim();
    final hasYml = bib.isNotEmpty && bib != '{}';
    final hasZotero = zoteroBibSource.trim().isNotEmpty;
    if (!hasYml && !hasZotero) return source;
    if (!RegExp(r'(^|[\s\[(])@[A-Za-z0-9_.:-]+').hasMatch(source)) {
      return source;
    }
    final directive = hasYml && hasZotero
        ? '#bibliography(("/${Vault.bibliographyPath}", "/${Vault.zoteroBibPath}"))'
        : hasZotero
        ? '#bibliography("/${Vault.zoteroBibPath}")'
        : '#bibliography("/${Vault.bibliographyPath}")';
    return '$source\n$directive\n';
  }

  // Debounces the preview source by 400ms so a recompile isn't triggered on
  // every keystroke; the first render after entering preview/split is
  // immediate. Reset by `build()` whenever preview isn't visible.
  String _debouncedPreview(String width) {
    final live = _previewSource();
    if (_debouncedPreviewSource == null) {
      _debouncedPreviewSource = live;
      _pendingPreviewSource = live;
      _debouncedPreviewWidth = width;
      _pendingPreviewWidth = width;
      return _screenPage(live);
    }
    if (live != _pendingPreviewSource || width != _pendingPreviewWidth) {
      _pendingPreviewWidth = width;
      _pendingPreviewSource = live;
      _previewDebounceTimer?.cancel();
      _previewDebounceTimer = Timer(const Duration(milliseconds: 400), () {
        if (!mounted) return;
        setState(() {
          _debouncedPreviewSource = live;
          _debouncedPreviewWidth = width;
        });
      });
    }
    return _screenPage(_debouncedPreviewSource!);
  }

  // Notes without the TyLog template (plain Typst, e.g. phone dailies) never
  // reach the theme, so the screen-wide page is set here as well; templated
  // notes get the same page from the theme via `tylog-page-width`.
  // ponytail: shifts Typst error line numbers by one in Preview.
  String _screenPage(String source) =>
      '#set page(width: ${_debouncedPreviewWidth}pt, height: auto, '
      'margin: 12pt)\n$source';

  void _loadSource(String source) {
    sourceController.text = source;
    richController.foldScope = note;
    richController.loadSource(source);
    _refreshNoteAssets(source);
  }

  void _acceptRichSource(String source) {
    if (sourceController.text == source) return;
    sourceController.text = source;
    _queueAutosave();
  }

  void _richEditorError(Object error) {
    if (!mounted) return;
    if (error is RichEditorSyntaxError) return;
    showSnack(context, 'Edit kept safe: $error');
  }

  Future<void> _queueClockMutation(Future<void> Function() action) {
    final opened = vault;
    _clockMutation = _clockMutation.then((_) async {
      try {
        await workspace.waitForMutationRefresh();
        if (!mounted || opened == null || !identical(vault, opened)) return;
        await action();
        await workspace.waitForMutationRefresh();
      } catch (error) {
        if (mounted) showSnack(context, 'Could not update that timer: $error');
      }
    });
    return _clockMutation;
  }

  Future<void> _leaveRunningTask(TaskRef running, String nextStatus) async {
    var discard = false;
    final opened = vault;
    final start = DateTime.tryParse(running.runningClock!.start);
    final elapsed = start == null
        ? Duration.zero
        : DateTime.now().difference(start);
    if (elapsed >= ClockEntry.runawayThreshold) {
      final choice = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            'This timer has been running for ${trackedTime(elapsed)}.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Stop now'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard session'),
            ),
          ],
        ),
      );
      if (choice == null || !mounted || !identical(vault, opened)) {
        return;
      }
      discard = choice;
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final entry = running.runningClock!;
    final closed = ClockEntry(start: entry.start, end: now);
    final duration = closed.elapsed;
    final misfire = duration != null && duration < ClockEntry.minimumMeaningful;
    final updated = await workspace.mutateNote(running.notePath, (source) {
      final entries = taskClocked(source, running.id);
      if (ClockEntry.latestRunning(entries) != entry) {
        throw StateError('The running session changed');
      }
      final stopped = discard || misfire
          ? setTaskClocked(
              source,
              running.id,
              entries.where((e) => e != entry).toList(),
            )
          : source;
      return applyTaskStatus(
        stopped,
        running.id,
        nextStatus,
        DateTime.parse(now),
      );
    });
    if (!updated) throw StateError('The vault changed');
    await workspace.waitForMutationRefresh();
    if (misfire && !discard && mounted) {
      showSnack(
        context,
        'Short timer session removed',
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => unawaited(
            _queueClockMutation(() async {
              if (!identical(vault, opened)) return;
              final restored = await workspace.mutateNote(
                running.notePath,
                (source) => setTaskClocked(source, running.id, [
                  ...taskClocked(source, running.id),
                  closed,
                ]),
              );
              if (!restored) throw StateError('The vault changed');
            }),
          ),
        ),
      );
    }
  }

  Future<void> _stopOtherDoingTasks(String file) async {
    final now = DateTime.now().toUtc();
    for (final running
        in index?.tasks.where((t) => t.runningClock != null).toList() ??
            <TaskRef>[]) {
      // Same-note transitions are atomic inside applyTaskStatus.
      if (running.notePath == file) continue;
      final updated = await workspace.mutateNote(
        running.notePath,
        (source) => applyTaskStatus(source, running.id, 'todo', now),
      );
      if (!updated) throw StateError('The vault changed');
    }
  }

  Future<void> _setTaskStatus(
    TaskRef task,
    String nextStatus,
  ) => _queueClockMutation(() async {
    if (vault == null) return;
    final file = task.notePath;
    try {
      if (nextStatus == 'doing') await _stopOtherDoingTasks(file);
      final current = index?.tasks
          .where((t) => t.id == task.id && t.notePath == file)
          .firstOrNull;
      if (nextStatus == 'todo' && current?.runningClock != null) {
        await _leaveRunningTask(current!, nextStatus);
        return;
      }
      final updated = await workspace.mutateNote(
        file,
        (source) => applyTaskStatus(
          source,
          task.id,
          nextStatus,
          DateTime.now().toUtc(),
        ),
      );
      if (!updated && mounted) {
        showSnack(context, 'Could not update that task: the vault changed.');
      }
    } on StateError catch (error) {
      // The task writers throw when they cannot find the call — an id the
      // index still lists but the file no longer has, or two tasks sharing an
      // id. Callers discard this future (`unawaited(onSetStatus(...))`), so
      // without this the checkbox silently did nothing and the user was told
      // nothing at all.
      if (!mounted) return;
      showSnack(context, 'Could not update that task: ${error.message}');
      return;
    } catch (error) {
      if (!mounted) return;
      showSnack(context, 'Could not update that task: $error');
      return;
    }
  });

  Future<void> _setTaskField(TaskRef task, String field, String value) async {
    try {
      final updated = await workspace.mutateNote(
        task.notePath,
        (source) => setOneTaskField(source, task.id, field, value),
      );
      if (!updated) throw StateError('The vault changed');
    } catch (error) {
      if (mounted) showSnack(context, 'Could not update that task: $error');
    }
  }

  Future<void> _setNoteProperty(NoteRef note, String name, String value) async {
    if (vault == null) return;
    try {
      final updated = await workspace.mutateNote(
        note.path,
        (source) => replaceNoteProperty(source, name, value),
      );
      if (!updated && mounted) {
        showSnack(context, 'Could not update that note: the vault changed.');
      }
    } on StateError catch (error) {
      // `replaceNoteProperty` throws on a note with no managed header — four
      // in this vault. Both call sites are `unawaited(...)` dropdowns, so
      // without this the control moved, nothing was written, and the user was
      // told nothing. Same silent-failure shape as `_setTaskStatus` above.
      if (!mounted) return;
      showSnack(context, 'Could not update that note: ${error.message}');
      return;
    } catch (error) {
      if (!mounted) return;
      showSnack(context, 'Could not update that note: $error');
      return;
    }
  }

  Future<void> _setReadStatus(NoteRef note, String status) =>
      _setNoteProperty(note, 'status', status);

  Future<void> _setRelevance(NoteRef note, String relevance) =>
      _setNoteProperty(note, 'relevance', relevance);

  String? _pathForLink(String title) {
    final resolved = workspace.linkResolver?.resolve(title);
    return resolved?.status == LinkResolutionStatus.resolved
        ? resolved!.path
        : null;
  }

  LinkResolution _resolveLink(String title) {
    final ix = index;
    return ix == null
        ? LinkResolution(target: title, status: LinkResolutionStatus.unresolved)
        : resolveLink(ix, title);
  }

  Future<void> _rebuildIndex({bool force = false}) async {
    await workspace.rebuildIndex(force: force);
  }

  /// Rewrites every note the [transform] changes, but only after saying how
  /// many and taking a copy.
  ///
  /// These are one-tap tiles that write to every note in the vault, and there
  /// is no vault-level undo — the editor's history is a 100-entry in-memory
  /// stack cleared on every `setSource`. Before this, one mis-tap rewrote
  /// 3,351 files with no confirmation and nothing to recover from but the
  /// server's own versioning.
  ///
  /// The pass is computed first and applied second, so the count in the dialog
  /// is the real one rather than an estimate, and a note is only copied if it
  /// is actually about to change.
  Future<void> _runBulkRewrite({
    required String title,
    required String confirmLabel,
    required String pastTense,
    required String nothingToDo,
    required String Function(String source) transform,
  }) async {
    final v = vault;
    final ix = index;
    if (v == null || ix == null) return;

    final pending = <String>{};
    for (final note in ix.notes) {
      final source = note.path == workspace.note
          ? _currentSource()
          : await v.storage.readText(note.path);
      final updated = transform(source);
      if (updated != source) pending.add(note.path);
    }
    if (!mounted) return;
    if (pending.isEmpty) {
      showSnack(context, nothingToDo);
      return;
    }

    final count = '${pending.length} note${pending.length == 1 ? '' : 's'}';
    final confirmed = await showConfirmDialog(
      context,
      title: title,
      message:
          'This rewrites $count and cannot be undone from inside TyLog.\n\n'
          'A copy of each note as it is now will be written to '
          '.tylog/undo/ first.',
      confirmLabel: confirmLabel,
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    // The editor may have changed while the confirmation dialog was open.
    // Persist it before taking the undo snapshot, so the backup and the
    // subsequent mutateNote both start from the latest user-visible source.
    if (pending.contains(workspace.note) &&
        dirty &&
        !await _save(syncAfter: false)) {
      if (mounted) showSnack(context, 'Could not save the open note.');
      return;
    }

    final String undoDirectory;
    try {
      undoDirectory = await v.snapshotNotes(pending);
    } catch (error) {
      // No snapshot, no rewrite. The whole point of the copy is that it exists
      // before anything is overwritten.
      if (!mounted) return;
      showSnack(
        context,
        'Could not save a backup, so nothing was changed: $error',
      );
      return;
    }

    for (final path in pending) {
      if (!await workspace.mutateNote(path, transform)) {
        if (mounted) {
          showSnack(context, 'Rewrite stopped because the vault changed.');
        }
        return;
      }
    }
    await workspace.waitForMutationRefresh();
    if (!mounted) return;
    showSnack(context, '$pastTense $count — previous copies in $undoDirectory');
  }

  /// One-off maintenance action: folds the legacy `properties["type"]`
  /// entity classifier into `kind` across every note in the vault (see
  /// [migrateEntityTypeToKind]). Safe to run multiple times.
  Future<void> _migrateEntityTypes() => _runBulkRewrite(
    title: 'Migrate entity types',
    confirmLabel: 'Migrate',
    pastTense: 'Migrated',
    nothingToDo: 'No notes needed entity-type migration',
    transform: migrateEntityTypeToKind,
  );

  Future<void> _migrateNamespaces({String? noteId}) async {
    final v = vault;
    final ix = index;
    if (v == null || ix == null) return;
    final notes = ix.notes.toList();
    if (dirty && !await _save(syncAfter: false)) return;
    if (!mounted) return;
    if (noteId == null) {
      unawaited(
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => const AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 20),
                Expanded(child: Text('Building namespace preview…')),
              ],
            ),
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
    }
    final plan = noteId == null
        ? await Isolate.run(() => namespacePlan(notes))
        : namespacePlan(notes, noteId: noteId);
    if (noteId == null && mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    if (noteId != null && plan.changes.isEmpty) {
      if (mounted) showSnack(context, 'This title cannot be migrated');
      return;
    }
    final lines = [
      for (final c in plan.changes)
        '${c.existingId == null ? "Create" : "Update"}: ${c.fullPath} → ${c.newTitle}${c.parentPath == null ? "" : " (parent: ${c.parentPath})"}',
      for (final title in plan.skipped) 'Skipped: $title',
    ];
    if (!mounted) return;
    final confirmed =
        noteId != null ||
        (await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Migrate namespace titles'),
                content: SizedBox(
                  width: 500,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${plan.changes.where((c) => c.existingId != null).length} updates · '
                        '${plan.changes.where((c) => c.existingId == null).length} pages to create · '
                        '${plan.skipped.length} skipped',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: kSpace12),
                      SizedBox(
                        height: 320,
                        child: SingleChildScrollView(
                          child: Text(
                            lines.isEmpty
                                ? 'No changes needed.'
                                : lines.join('\n'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  if (plan.changes.isNotEmpty)
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Apply'),
                    ),
                ],
              ),
            )) ==
            true;
    if (!confirmed || !mounted || vault != v) return;
    try {
      final affected = plan.changes
          .map((c) => c.existingId)
          .whereType<String>()
          .toSet();
      await v.snapshotNotes(
        notes.where((n) => affected.contains(n.id)).map((n) => n.path).toSet(),
      );
      await applyNamespacePlan(v, notes, plan, mutate: workspace.mutateNote);
      await workspace.waitForMutationRefresh();
      await workspace.refreshIndex(updateStatus: false, always: true);
      if (mounted) showSnack(context, 'Namespace migration complete');
    } catch (error) {
      if (mounted) showSnack(context, 'Namespace migration stopped: $error');
    }
  }

  /// One-off maintenance: drops the *empty* org-mode drawers and trailing
  /// empty blocks that Logseq exports carry into a note (see
  /// [stripLogseqNoise]). A drawer holding CLOCK: records is left alone — those
  /// are the user's time tracking, and this rewrites in bulk. The converter
  /// strips these now, but a re-import cannot repair the notes already on disk
  /// — the wizard skips a source whose SHA is unchanged. Safe to run more than
  /// once.
  Future<void> _stripImportNoise() => _runBulkRewrite(
    title: 'Clean up imported notes',
    confirmLabel: 'Clean up',
    pastTense: 'Cleaned',
    nothingToDo: 'No imported notes needed cleaning',
    transform: stripLogseqNoise,
  );

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_exiting) return;
    if (state == AppLifecycleState.inactive) {
      if (dirty) unawaited(_save(syncAfter: false));
      return;
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _semantic?.pause();
      unawaited(workspace.flushSearch());
      // Android may kill the app inside the 400 ms autosave debounce; flush
      // pending edits now so backgrounding never loses keystrokes.
      unawaited(
        (dirty ? _save(syncAfter: false) : Future.value(true))
            .then((_) async {
              if (cloud?.isReady ?? false) {
                await _syncNow(trigger: 'background');
              }
            })
            .whenComplete(workspace.flushSearch),
      );
      // Desktops keep polling with the window closed (hide-on-close): the
      // Mac publishes revisions for the phones even when nobody looks at it.
      if (stopsPollingInBackground(defaultTargetPlatform)) _stopCloudPolling();
      // Hand off to the background worker: one catch-up run in ~1 min, then
      // the 15-min periodic keeps the vault fresh while the app is closed.
      if (Platform.isAndroid && (cloud?.isReady ?? false)) {
        unawaited(
          AndroidTreeVaultStorage.scheduleBackgroundSoon().catchError((_) {}),
        );
      }
      return;
    }
    if (state == AppLifecycleState.resumed) {
      workspace.pushPendingInBackground();
      if (_semantic != null) unawaited(_semantic!.refreshNotes());
      // The UI owns the vault again; a still-pending catch-up run would only
      // contend for the lock.
      if (Platform.isAndroid) {
        unawaited(
          AndroidTreeVaultStorage.cancelBackgroundSoon().catchError((_) {}),
        );
      }
      _startCloudPolling();
      _rolloverTodayIfStale();
      if (cloud?.isReady ?? false) {
        if (_editingRecently) {
          _queueCloudSync();
        } else {
          unawaited(workspace.pollOnResume());
        }
      }
    }
  }

  /// If the Today note was opened before the calendar day changed (app left
  /// open or backgrounded across midnight), re-open today's note so the
  /// Today screen and header reflect the actual current day.
  void _rolloverTodayIfStale() {
    final openedAt = _todayOpenedAt;
    if (openedAt == null || note != _todayNotePath) return;
    if (!shouldRolloverToday(openedAt: openedAt, now: DateTime.now())) return;
    if (dirty) {
      // ponytail: rollover skipped while dirty; edits win
      return;
    }
    unawaited(_openToday());
  }

  void _showVaults() {
    final registry = vaultRegistry;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: false,
      builder: (context) => VaultsSheet(
        vaults: registry?.entries ?? const [],
        activeVaultId: registry?.activeId,
        onAddVault: () {
          if (vaultRegistry != null) unawaited(_pickVault());
        },
        onSwitchVault: (entry) => unawaited(_switchVault(entry)),
        onForgetVault: (entry) => unawaited(_forgetVault(entry)),
        onDeleteVault: (entry) => unawaited(_deleteVault(entry)),
        onMoveToAppStorage: Platform.isAndroid
            ? (entry) => unawaited(_moveVaultToAppStorage(entry))
            : null,
      ),
    );
  }

  Future<void> _applyWantedScreenshots() async {
    final opened = vault;
    final registry = vaultRegistry;
    final path = _localVaultDirectory?.path;
    if (opened == null || registry == null || path == null) return;
    try {
      final ai = await readAiSettings(opened.storage);
      final task = ai.screenshots;
      final publish = screenshotsToPublish(
        task.mode,
        await installedScreenshotMode(),
        registry.screenshotsTime,
      );
      if (publish != null) {
        await writeAiSettings(
          opened.storage,
          ai.copyWith(
            screenshots: task.copyWith(mode: publish.$1, time: publish.$2),
          ),
        );
        return;
      }
      if (!screenshotsNeedApply(
        task.mode,
        task.time,
        registry.screenshotsMode,
        registry.screenshotsTime,
      )) {
        return;
      }
      final time = task.time ?? registry.screenshotsTime;
      await configureScreenshotsOcr(
        path,
        task.mode!,
        time,
        scriptsDir: registry.screenshotsFolder,
      );
      await registry.setScreenshotsOcr(task.mode!, time);
    } catch (_) {
      // Retried next minute; the Settings status shows agent problems.
    }
  }

  void _insertTypstSnippet(String snippet) {
    final source = _currentSource();
    _loadSource('${source.trimRight()}\n\n$snippet\n');
    _enterView('source');
    _queueAutosave();
  }

  Future<void> _openPath(String path) async {
    final v = vault;
    if (v == null) return;
    await workspace.materializeEvent(path);
    await _openNote(path);
  }

  void _showEditor() {
    if (mode == 'source' || mode == 'split') {
      richController.loadSource(sourceController.text);
    }
    while (_backViews.isNotEmpty &&
        _backViews.last.knowledge == null &&
        const {
          'normal',
          'read',
          'preview',
          'source',
          'split',
        }.contains(_backViews.last.mode)) {
      _backViews.removeLast();
    }
    setState(() => mode = 'normal');
  }

  int _destinationGeneration = 0;

  Future<void> _showToday() async {
    if (!mounted) return;
    ++_destinationGeneration;
    _backViews.clear();
    setState(() {
      primaryDestination = 0;
      mode = 'normal';
    });
    await _openToday();
  }

  void _setEditorMode(String next) {
    if (next == 'normal') {
      _showEditor();
    } else {
      if (mode == 'normal') sourceController.text = _currentSource();
      _enterView(next);
    }
  }

  Future<void> _selectDestination(int destination, {int libraryTab = 0}) async {
    if (destination == 3) {
      await _showKnowledge();
      return;
    }
    if (destination == 4 || !mounted) return;
    if (destination == 0) {
      await _showToday();
      return;
    }
    final generation = ++_destinationGeneration;
    ++_openGeneration;
    _backViews.clear();
    switch (destination) {
      case 1:
        setState(() {
          primaryDestination = 1;
          mode = 'journal';
        });
        break;
      case 2:
        setState(() {
          primaryDestination = 2;
          _libraryTab = libraryTab;
          mode = 'library';
        });
        break;
      default:
        return;
    }
    if (dirty && !await _save()) return;
    if (!mounted || generation != _destinationGeneration) return;
  }

  Future<void> _showMoreMenu(Widget linksPanel) async {
    final action = await showModalBottomSheet<_ShellAction>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (context) {
        Widget tile(_ShellAction action, IconData icon, String title) =>
            AppTile(
              icon: icon,
              title: title,
              onTap: () => Navigator.pop(context, action),
            );
        return AppSheet(
          title: 'More',
          children: [
            AppSection(
              title: 'Switch',
              divider: false,
              children: [
                tile(_ShellAction.vaults, AppIcons.folder, 'Vaults'),
                tile(_ShellAction.settings, AppIcons.settings, 'Settings'),
              ],
            ),
            AppSection(
              title: 'Create',
              children: [
                tile(_ShellAction.newPage, Icons.note_add_outlined, 'New page'),
                tile(
                  _ShellAction.newEntity,
                  Icons.person_add_alt,
                  'New entity',
                ),
              ],
            ),
            if (vault != null && note != null)
              AppSection(
                title: 'This note',
                children: [
                  tile(_ShellAction.backlinks, AppIcons.link, 'Context'),
                  if (_currentNoteRef()?.title.contains('/') == true)
                    tile(
                      _ShellAction.namespace,
                      Icons.account_tree_outlined,
                      'Convert namespace',
                    ),
                  tile(_ShellAction.sharePdf, Icons.ios_share, 'Share as PDF'),
                ],
              ),
            AppSection(
              title: 'Views',
              children: [
                tile(_ShellAction.graph, AppIcons.graph, 'Graph'),
                if (vault != null)
                  tile(
                    _ShellAction.processing,
                    Icons.hourglass_top,
                    'Processing',
                  ),
              ],
            ),
          ],
        );
      },
    );
    if (action == null) return;
    await _runShellAction(action, linksPanel);
  }

  Future<void> _showSemanticSearch() async {
    await _ensureSemanticController();
    final controller = _semantic;
    if (!mounted || controller == null) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: false,
      builder: (context) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final state = controller.state;
          final installed = state is SemanticReady || state is SemanticIndexing;
          return AppSheet(
            title: 'Semantic search',
            children: [
              Text(switch (state) {
                SemanticNotInstalled() => 'Not installed',
                SemanticDownloading(:final progress) =>
                  'Downloading ${(progress * 100).round()}%',
                SemanticIndexing(:final done, :final pending) =>
                  'Indexing: $done done, $pending pending',
                SemanticReady() => 'Ready',
                SemanticError(:final message) => 'Error: $message',
              }),
              const SizedBox(height: kSpace12),
              if (state case SemanticDownloading(:final progress)) ...[
                LinearProgressIndicator(value: progress),
                TextButton(
                  onPressed: controller.cancel,
                  child: const Text('Cancel'),
                ),
              ] else if (!installed)
                FilledButton(
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Download semantic model?'),
                        content: const Text(
                          'It downloads once from Hugging Face and works offline afterwards.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Download'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) unawaited(controller.download());
                  },
                  child: const Text('Download model (252 MB)'),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _runShellAction(_ShellAction action, Widget linksPanel) async {
    switch (action) {
      case _ShellAction.vaults:
        _showVaults();
      case _ShellAction.newPage:
        await _newPage();
      case _ShellAction.newEntity:
        await _createEntity();
      case _ShellAction.graph:
        _enterView('graph');
      case _ShellAction.split:
        sourceController.text = _currentSource();
        _enterView('split');
      case _ShellAction.backlinks:
        await showDialog<void>(
          context: context,
          builder: (_) => Dialog.fullscreen(
            child: Scaffold(
              appBar: AppBar(title: const Text('Context')),
              body: SafeArea(child: linksPanel),
            ),
          ),
        );
      case _ShellAction.namespace:
        final current = _currentNoteRef();
        if (current != null) await _migrateNamespaces(noteId: current.id);
      case _ShellAction.sharePdf:
        await _sharePdf();
      case _ShellAction.settings:
        _showSettings();
      case _ShellAction.processing:
        await _showProcessing();
    }
  }

  Widget _screenshotView(NoteRef screenshot, {VoidCallback? onBack}) {
    final currentVault = vault!;
    return ScreenshotView(
      note: screenshot,
      source: _currentSource(),
      imageResolver: _readAsset,
      onEdit: () => setState(() => _editScreenshot = true),
      onBack: onBack,
      readSource: () => currentVault.storage.readText(screenshot.path),
      translationJob: (target) =>
          readTranslationJob(currentVault.storage, screenshot.path, target),
      requestTranslation: (target, language) async {
        if (!mounted || vault != currentVault) return;
        await enqueueScreenshotTranslation(
          currentVault.storage,
          notePath: screenshot.path,
          target: target,
          sourceLang: language,
        );
        _processingJobWritten(
          currentVault,
          translationJobPath(screenshot.path, target),
        );
      },
      onOpenAsPage: (language, lines) async {
        if (!mounted || vault != currentVault) return;
        final path = await createAudioTextPage(
          workspace,
          screenshot,
          language,
          lines,
        );
        if (!mounted || vault != currentVault) return;
        if (!await _openNote(path)) {
          throw StateError('Could not open text page');
        }
        unawaited(workspace.refreshIndex(always: true));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_exiting) return const SizedBox.shrink();
    if (mode != 'preview' && mode != 'split') {
      _previewDebounceTimer?.cancel();
      _previewDebounceTimer = null;
      _debouncedPreviewSource = null;
      _pendingPreviewSource = null;
      _debouncedPreviewWidth = null;
      _pendingPreviewWidth = null;
    }
    final compactHeight = MediaQuery.sizeOf(context).height < 480;
    final v = vault;
    final current = v == null || note == null ? null : note;
    final currentTitle = _currentTitle(current);
    final currentNote = current == null ? null : index?.notesByPath[current];
    if (mode == 'read') {
      if (currentNote?.kind == 'screenshot' && !_editScreenshot) {
        return _screenshotView(
          currentNote!,
          onBack: _backViews.isEmpty ? _showEditor : _back,
        );
      }
      var savedProgress = 0.0;
      for (final r in _mergedRecent()) {
        if (r.path == current) {
          savedProgress = r.progress;
          break;
        }
      }
      return ReadingMode(
        source: _currentSource(),
        path: current,
        imageResolver: _readAsset,
        resolveKind: _resolveKind,
        fontScale: vaultRegistry?.readingFontScale ?? 1,
        nightMode: vaultRegistry?.readingNightMode ?? false,
        onExit: _backViews.isEmpty ? _showEditor : _back,
        onPreferencesChanged: _updateReadingPreferences,
        onProgress: _recordReadingProgress,
        onAtomTap: (source) =>
            unawaited(_handleAtomSource(source, allowEdit: false)),
        revealQuery: _searchRevealQuery,
        revealOffset: _searchRevealOffset,
        // A finished article reopens at the top, not the last line.
        initialProgress: savedProgress >= 0.98 ? 0 : savedProgress,
        canRate:
            currentNote?.kind == 'article' &&
            currentNote?.properties['rating'] == null,
        onRate: current == null
            ? null
            : (value) => _rateArticle(current, value),
      );
    }
    final backlinks = current == null
        ? const <String>[]
        : index?.backlinksByTarget[current] ?? const <String>[];
    final outgoing = current == null
        ? const <String>[]
        : index?.notesByPath[current]?.outgoingLinks ?? const <String>[];
    // Both derived once per index by the controller, not per build. The shell
    // rebuilds on every notifyListeners() — 20 swipes used to cost ~4s of CPU
    // because each rebuild re-derived the whole vault. Null until the first
    // derivation lands; every consumer below already handles that.
    final resolver = workspace.linkResolver;
    if (mode == 'graph' || mode == 'library') {
      unawaited(workspace.refreshDerived());
    }
    final communities = workspace.communities;
    // Only the graph pane consumes this, and `mode` defaults to 'normal', so
    // building it unconditionally was pure waste on every other screen.
    final graph = mode == 'graph' && index != null
        ? _memoizedGraph(current)
        : null;
    final desktopManaged =
        _localVaultDirectory != null &&
        isNextcloudManagedVault(_localVaultDirectory!);
    // The pending step wins so the arrows feel instant; it clears when the
    // open lands (see [_stepDay]).
    final currentDaily = _navDay ?? _dailyDateOf(current);
    if (currentDaily != null) _loadOltForToday();
    final dayItems = currentDaily == null
        ? const <CalendarItem>[]
        : workspace.calendar
              .where(
                (item) =>
                    item.date == isoDay(currentDaily) &&
                    item.notePath != current,
              )
              .toList();
    final linksPanel = LinksPanel(
      current: current,
      outgoing: outgoing,
      backlinks: backlinks,
      dayItems: dayItems,
      fileRefs: current == null
          ? const <String>[]
          : index?.notesByPath[current]?.fileRefs ?? const <String>[],
      index: index,
      resolveLink: resolver?.resolve ?? _resolveLink,
      onOpenLink: _openLink,
      onOpenPath: _openPath,
      onOpenFile: _openAttachment,
      onEditMetadata: _editCurrentMetadata,
    );
    final documentModes = const {
      'normal',
      'read',
      'preview',
      'source',
      'split',
    };
    final content = switch (mode) {
      _ when v == null && documentModes.contains(mode) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Choose a vault folder to continue'),
            const SizedBox(height: kSpace12),
            FilledButton(
              onPressed: () => unawaited(_open()),
              child: const Text('Choose vault'),
            ),
          ],
        ),
      ),
      'journal' => JournalFeed(
        onSetStatus: _setTaskStatus,
        onSetField: _setTaskField,
        events: workspace.calendar
            .where((e) => e.kind != CalendarItemKind.daily)
            .toList(),
        vault: v,
        index: index,
        resolveKind: _resolveKind,
        onAtomTap: (source) =>
            unawaited(_handleAtomSource(source, allowEdit: false)),
        onOpenPath: (path) {
          primaryDestination = 1;
          unawaited(_openPath(path));
        },
      ),
      'library' => LibraryView(
        boardStorage: v?.storage,
        githubClient: workspace.githubClient,
        boardDeviceId: vaultRegistry?.deviceId ?? 'unknown',
        onOpenColumns: (context, board) {
          if (v == null) return;
          if (board.scopeExtra['github_project'] is Map) {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => GitHubProjectBoard(
                  board: board,
                  storage: v.storage,
                  client: workspace.githubClient,
                  deviceId: vaultRegistry?.deviceId ?? 'unknown',
                ),
              ),
            );
            return;
          }
          final boardIndex =
              index ?? const VaultIndex(notesByPath: {}, backlinksByTarget: {});
          final entityId = board.scopeEntity ?? board.id;
          final entity =
              boardIndex.notes
                  .where((note) => note.id == entityId)
                  .firstOrNull ??
              NoteRef(
                id: entityId,
                path: '',
                title: board.title,
                outgoingLinks: const [],
              );
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => UnifiedBoard(
                entity: entity,
                sourceBoardId: board.id,
                deviceId: vaultRegistry?.deviceId ?? 'unknown',
                imageResolver: _readAsset,
                onOpenPath: _openPath,
                vault: v,
                index: boardIndex,
                setStatus: _setTaskStatus,
                mutateNote: workspace.mutateNote,
                githubClient: workspace.githubClient,
                onOpenUrl: _openUrl,
                refreshIndex: () async {
                  await workspace.waitForMutationRefresh();
                  return index;
                },
              ),
            ),
          );
        },
        initialTab: _libraryTab,
        onTabChanged: (tab) => _libraryTab = tab,
        articleJobs: _articleJobs,
        index: index,
        pagedNotes: _pagedLibraryNotes,
        calendar: workspace.calendar,
        dayMarks: workspace.calendarDayMarks,
        indexing: workspace.awaitingIndex,
        // Insertion order stays newest-opened-first — the shelf's
        // continue-reading card takes the first in-progress entry.
        progressByPath: {for (final r in _mergedRecent()) r.path: r.progress},
        onOpenPath: (path) {
          primaryDestination = 2;
          unawaited(_openPath(path));
        },
        onOpenDay: (day) {
          primaryDestination = 2;
          unawaited(_openDay(day));
        },
        onSetTaskStatus: _setTaskStatus,
        onSetTaskField: _setTaskField,
        imageResolver: _readAsset,
        onSetReadStatus: _setReadStatus,
        onSetRelevance: _setRelevance,
        noteToCluster: communities?.noteToCluster ?? const {},
        shelfPrefs: vaultRegistry?.shelfPrefs ?? const {},
        onShelfPrefsChanged: (prefs) {
          final registry = vaultRegistry;
          if (registry == null) return;
          // Merge against the live map: a shelf sends only its own keys.
          unawaited(
            registry.updateShelfPrefs({...registry.shelfPrefs, ...prefs}),
          );
        },
        audioShelf: _audioShelf,
        onCreateNote: (kind) => unawaited(_newPage(kind: kind)),
        onCreateEntity: () => unawaited(_createEntity()),
        onImportMarkdownArticles: _importMarkdownArticles,
        onReadPath: _readPath,
        onDeleteArticle: _deleteArticle,
      ),
      'graph' when _graphMode == 'voronoi' && index != null => VoronoiView(
        index: index!,
        communities: communities,
        indexRevision: workspace.indexRevision,
        clusterNames: workspace.clusterNames,
        onRenameCluster: workspace.renameCluster,
        initialSelectedPath: _graphSelectedPath,
        onSelectionChanged: (path) => setState(() => _graphSelectedPath = path),
        onOpenPath: (path) => unawaited(_openPath(path)),
        onOpenNotes: (paths) {
          final ids = paths.toSet();
          final filtered = VaultIndex(
            notesByPath: {
              for (final entry in index!.notesByPath.entries)
                if (ids.contains(entry.key)) entry.key: entry.value,
            },
            backlinksByTarget: const {},
          );
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) => Scaffold(
                appBar: AppBar(title: Text('${ids.length} notes')),
                body: LibraryView(
                  index: filtered,
                  calendar: const [],
                  dayMarks: (daily: <String>{}, refs: <String>{}),
                  progressByPath: const {},
                  onOpenPath: (path) {
                    Navigator.of(context).pop();
                    unawaited(_openPath(path));
                  },
                  onOpenDay: (day) => unawaited(_openDay(day)),
                  onSetTaskStatus: _setTaskStatus,
                  onSetTaskField: _setTaskField,
                  onSetReadStatus: _setReadStatus,
                  onSetRelevance: _setRelevance,
                  onCreateNote: (kind) => unawaited(_newPage(kind: kind)),
                  onCreateEntity: () => unawaited(_createEntity()),
                  onImportMarkdownArticles: _importMarkdownArticles,
                  onReadPath: _readPath,
                  onDeleteArticle: _deleteArticle,
                ),
              ),
            ),
          );
        },
      ),
      'graph' => GraphView(
        graph: graph ?? const NoteGraph(nodes: [], edges: []),
        onExportSvg: _shareGraphSvg,
        currentPath: _graphFocusPath ?? current,
        initialSelectedPath: _graphSelectedPath,
        onSelectionChanged: (path) => setState(() => _graphSelectedPath = path),
        onAcceptSuggestion: (from, to) async {
          if (_pendingEnrichDecision(from, to) case final decision?) {
            await _enrichOnce(
              () => _acceptEnrich(from, decision.mention, decision.target!),
            );
          }
        },
        onRejectSuggestion: (from, to) async {
          if (_pendingEnrichDecision(from, to) case final decision?) {
            await _enrichOnce(
              () => _rejectEnrich(from, decision.mention, decision.target!),
            );
          }
        },
        // Opening a concept/work hub expands it into a rooted local view rather
        // than opening a file; opening a note opens the file as usual.
        onOpenPath: (path) {
          if (path.startsWith('concept:') || path.startsWith('cite:')) {
            setState(() {
              _graphMode = 'local';
              _graphFocusPath = path;
            });
          } else {
            unawaited(_openPath(path));
          }
        },
        isWholeVault: _graphMode == 'allFiles',
        onSwitchToFocused: () => setState(() {
          _graphMode = 'local';
          _graphFocusPath = null;
        }),
        // Zoom-out zones only for the whole-vault hairball; elsewhere the
        // nodes-to-zones flip on pinch read as "strange zooming" in tests.
        communities: _graphMode == 'allFiles' ? communities : null,
      ),
      'preview' when !workspace.typstPackagesReady => const Center(
        child: LoadingIndicator(),
      ),
      'preview' => LayoutBuilder(
        builder: (context, constraints) => TypstDocumentViewer(
          source: _debouncedPreview(
            (constraints.maxWidth / _previewPixelsPerPt).toStringAsFixed(1),
          ),
          inputs: {'tylog-page-width': _debouncedPreviewWidth!},
          pixelsPerPt: _previewPixelsPerPt,
          pageSpacing: 0,
          pageElevation: 0,
          files: _typstFiles(),
          loadingBuilder: (_) => const Center(child: LoadingIndicator()),
          errorBuilder: (_, error) => Padding(
            padding: const EdgeInsets.all(kSpace16),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SelectableText('Typst error:\n$error'),
                  FilledButton.tonalIcon(
                    onPressed: () =>
                        unawaited(_showTypstHelp(error: error.toString())),
                    icon: const Icon(Icons.help_outline),
                    label: const Text('Explain error'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      'source' => Editor(
        key: sourceEditorKey,
        controller: sourceController,
        onChanged: _queueAutosave,
        monospace: true,
        readOnly: workspace.noteIsExtension,
      ),
      'split' => () {
        final stacked = MediaQuery.sizeOf(context).width < 600;
        return Flex(
          direction: stacked ? Axis.vertical : Axis.horizontal,
          children: [
            Expanded(
              child: Editor(
                key: sourceEditorKey,
                controller: sourceController,
                onChanged: _queueAutosave,
                monospace: true,
                readOnly: workspace.noteIsExtension,
              ),
            ),
            if (stacked)
              const Divider(height: 1)
            else
              const VerticalDivider(width: 1),
            Expanded(
              child: !workspace.typstPackagesReady
                  ? const Center(child: LoadingIndicator())
                  : LayoutBuilder(
                      builder: (context, constraints) => TypstDocumentViewer(
                        source: _debouncedPreview(
                          (constraints.maxWidth / _previewPixelsPerPt)
                              .toStringAsFixed(1),
                        ),
                        inputs: {'tylog-page-width': _debouncedPreviewWidth!},
                        pixelsPerPt: _previewPixelsPerPt,
                        pageSpacing: 0,
                        pageElevation: 0,
                        files: _typstFiles(),
                      ),
                    ),
            ),
          ],
        );
      }(),
      'normal' when currentNote?.kind == 'screenshot' && !_editScreenshot =>
        _screenshotView(currentNote!),
      'normal' when _usePlainLongEditor => VirtualPlainEditor(
        readOnly: workspace.noteIsExtension,
        key: _plainEditorKey,
        onHistoryChanged: () => _plainHistoryRevision.value++,
        source: richController.text,
        onChanged: (visibleText) {
          if (!identical(vault, v) || note != current) return;
          richController.value = TextEditingValue(
            text: visibleText,
            selection: TextSelection.collapsed(offset: visibleText.length),
          );
        },
      ),
      'normal' => TyLogRichEditor(
        issueAction:
            primaryDestination == 0 &&
                currentDaily != null &&
                v != null &&
                index != null &&
                !workspace.noteIsExtension
            ? (line) {
                final issue = index!.issues
                    .where(
                      (i) =>
                          i.notePath == current &&
                          i.line == line &&
                          i.githubNumber == null,
                    )
                    .firstOrNull;
                if (issue == null) return null;
                final repo = issueGithubRepo(issue, index!);
                if (repo == null) return null;
                return () async {
                  try {
                    await sendIssueToGithub(
                      issue: issue,
                      repo: repo,
                      vault: v,
                      githubClient: workspace.githubClient,
                      mutateNote: workspace.mutateNote,
                    );
                    await workspace.waitForMutationRefresh();
                  } catch (e) {
                    if (context.mounted) {
                      showSnack(context, 'Could not send issue: $e');
                    }
                  }
                };
              }
            : null,
        readOnly: workspace.noteIsExtension,
        popupBottomY: () {
          // Only pills docked at the bottom limit the popup. While the
          // keyboard is up the pills sit at the top (see `typing`), and
          // counting them squeezed the suggestions into a strip there.
          final bounds = [_statusPillBounds, _taskClockBounds]
              .where((key) => key.currentContext != null)
              .where(
                (key) =>
                    (key.currentContext!.findRenderObject()! as RenderBox)
                        .localToGlobal(Offset.zero)
                        .dy >
                    MediaQuery.sizeOf(key.currentContext!).height / 2,
              )
              .map(
                (key) => (key.currentContext!.findRenderObject()! as RenderBox)
                    .localToGlobal(Offset.zero)
                    .dy,
              );
          if (bounds.isEmpty) return null;
          return bounds.reduce((a, b) => a < b ? a : b);
        },
        focusNode: _captureFocus,
        controller: richController,
        revealQuery: _searchRevealQuery,
        revealOffset: _searchRevealOffset,
        revealGeneration: _searchRevealGeneration,
        onInsert: _showMagicMenu,
        onSelectMention: (item) async {
          final event = workspace.feedEvents
              .where((e) => e.id == item.id)
              .firstOrNull;
          if (event != null) {
            await workspace.materializeEvent(event.path);
            unawaited(workspace.refreshIndex(always: true));
          }
        },
        onMentionQuery: (query, kind) async {
          // Query the note index (populated the moment the vault opens), not
          // the full-text search index — the latter can take a while to finish
          // building on large SAF vaults, and mentions must resolve instantly.
          final q = foldAccents(query.trim());
          final eventSuggestions = [
            for (final e in searchFeedEvents(
              workspace.feedEvents,
              query,
              today: DateTime.now(),
              editedDay:
                  index?.notesByPath[current]?.date ??
                  (_dailyDateOf(current) == null
                      ? null
                      : isoDay(_dailyDateOf(current)!)),
            ))
              MentionSuggestion(
                id: e.id,
                title: e.title,
                noteKind: 'event',
                subtitle: '${e.date} · ${e.label}',
              ),
          ];
          final eventIds = eventSuggestions.map((e) => e.id).toSet();
          // Built once per query, not per candidate: _mergedRecent() allocates
          // and sorts, and it is capped at 30 entries.
          final recency = <String, int>{
            for (final (position, recent) in _mergedRecent().indexed)
              recent.path: position,
          };
          // Bare `[[` / `@` shows recently-opened notes instead of "No
          // matches" — the recency list was already computed and only ever
          // used as a tiebreaker.
          if (q.isEmpty) {
            final byPath = index?.notesByPath ?? const <String, NoteRef>{};
            return [
              ...eventSuggestions,
              for (final recent in _mergedRecent().take(8))
                if (byPath[recent.path] case final NoteRef n)
                  MentionSuggestion(
                    id: n.id,
                    title: n.title,
                    noteKind: n.kind,
                    subtitle: mentionSubtitle(n),
                  ),
            ];
          }
          bool matches(String s) => foldAccents(s).contains(q);
          final mentionText = richController.text;
          final mentionSelection = richController.selection;
          bool cancelled() =>
              !mounted ||
              vault != v ||
              richController.text != mentionText ||
              richController.selection != mentionSelection;
          final matchedNotes = await _mentionQueryCache.queryAsync(
            index,
            q,
            recency,
            excludedIds: eventIds,
            revision: workspace.indexRevision,
            isCancelled: cancelled,
          );
          if (cancelled()) return <MentionSuggestion>[];
          final suggestions = [
            ...eventSuggestions,
            ...matchedNotes
                .take(8)
                .map(
                  (n) => MentionSuggestion(
                    id: n.id,
                    title: n.title,
                    noteKind: n.kind,
                    subtitle: mentionSubtitle(n),
                  ),
                ),
          ];
          // `[[` also completes existing tags into concepts; `@` stays notes.
          if (kind == AutocompleteTriggerKind.wikiLink) {
            final tags = <String>{
              for (final n in index?.notes ?? const <NoteRef>[])
                if (!eventIds.contains(n.id)) ...n.tags,
            }.where(matches).toList()..sort();
            suggestions.addAll(
              tags
                  .take(8)
                  .map(
                    (t) => MentionSuggestion(
                      id: t,
                      title: t,
                      kind: MentionKind.concept,
                    ),
                  ),
            );
          }
          // Let either trigger create a person or an ordinary note without
          // forcing a near match to an existing page.
          final typed = query.trim();
          if (typed.isNotEmpty &&
              !suggestions.any(
                (s) => s.title.toLowerCase() == typed.toLowerCase(),
              )) {
            for (final kind in ['person', 'note']) {
              suggestions.add(
                MentionSuggestion(
                  id: typed,
                  title: typed,
                  noteKind: kind,
                  subtitle: 'Create $kind',
                  create: true,
                ),
              );
            }
          }
          return suggestions;
        },
        onCommandSelected: _runMagic,
        onCreateNote: (title, kind) {
          final v = vault;
          if (v == null) return null;
          final direct =
              'notes/${title.trim().replaceAll(RegExp(r'[\\/]'), '-')}.typ';
          final existing = index?.notesByPath[direct];
          final id =
              existing?.id ??
              v.allocateNoteId(
                title,
                knownIds:
                    index?.notes.map((note) => note.id).toSet() ?? <String>{},
              );
          return (
            id: id,
            create: () async {
              if (existing != null) return;
              if (!identical(vault, v)) throw StateError('Vault changed');
              final file = await workspace.createPage(
                title,
                kind: kind,
                id: id,
              );
              if (context.mounted) showSnack(context, 'Created $file');
              unawaited(workspace.refreshIndex(always: true));
            },
          );
        },
      ),
      _ => const SizedBox.shrink(),
    };
    final isTodayDocument =
        primaryDestination == 0 &&
        documentModes.contains(mode) &&
        currentDaily != null;
    // A person/place/… note gets a Logseq-style page: an info header above the
    // body and a linked-references (backlinks) block below it. Any note that is
    // mentioned elsewhere gets the references block too.
    final isEntity =
        currentNote != null && !structuralNoteKinds.contains(currentNote.kind);
    // While typing the editor gets the screen: the screenshot strip, linked
    // references and mentions step aside. Placeholders keep every child's slot,
    // so the editor is not rebuilt (and the keyboard not dropped) on the switch.
    final keyboardUp = MediaQuery.viewInsetsOf(context).bottom > 0;
    final dailyMore = <Widget>[];
    Widget documentContent = content;
    if (mode == 'normal' &&
        currentNote != null &&
        (isEntity || backlinks.isNotEmpty)) {
      final v = vault;
      final references = backlinks.isEmpty || v == null
          ? null
          : LinkedReferences(
              imageResolver: _readAsset,
              backlinks: backlinks,
              index: index,
              targets: {
                currentNote.id,
                currentNote.title,
                ...currentNote.aliases,
              }.map((t) => t.toLowerCase()).toSet(),
              readSource: (path) async {
                try {
                  return await v.storage.readText(path);
                } catch (_) {
                  return '';
                }
              },
              onOpenPath: _openPath,
            );
      if (currentDaily != null && references != null) {
        dailyMore.add(references);
      }
      documentContent = Column(
        children: [
          if (isEntity)
            EntityHeader(
              note: currentNote,
              onOpenTimeline: index == null
                  ? null
                  : () => showModalBottomSheet<void>(
                      context: context,
                      builder: (context) => EntityTimeline(
                        entity: currentNote,
                        index: index!,
                        resolver: workspace.linkResolver,
                        onOpenPath: (path) {
                          Navigator.pop(context);
                          _openPath(path);
                        },
                      ),
                    ),
              onGithubChanged: (value) =>
                  _setNoteProperty(currentNote, 'github', value.trim()),
              onEditDetails: _editCurrentMetadata,
              onFillInfo: () async {
                try {
                  await workspace.requestFill(currentNote);
                  if (mounted) {
                    showSnack(
                      this.context,
                      'Fill info requested. The draft appears in Incoming '
                      'when the worker has run.',
                    );
                  }
                } catch (error) {
                  if (mounted) {
                    showSnack(this.context, 'Could not request: $error');
                  }
                }
              },
              relationships: EntityRelationships(
                note: scanNote(currentNote.path, _currentSource()),
                index: index,
                onAdd: _addParent,
                onRemove: (id) => _updatePartOf(id, remove: true),
                onOpen: _openPath,
              ),
              onOpenBoard: v != null && index != null
                  ? () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => UnifiedBoard(
                          entity: currentNote,
                          onOpenPath: _openPath,
                          imageResolver: _readAsset,
                          deviceId: vaultRegistry?.deviceId ?? 'unknown',
                          githubClient: workspace.githubClient,
                          onOpenUrl: _openUrl,
                          vault: v,
                          index: index!,
                          setStatus: _setTaskStatus,
                          mutateNote: workspace.mutateNote,
                          refreshIndex: () async {
                            await workspace.waitForMutationRefresh();
                            return index;
                          },
                        ),
                      ),
                    )
                  : null,
              imageResolver: _readAsset,
              onOpenUrl: _openUrl,
              onChangeKindIcon: () async {
                final entry = kindRegistry.value[currentNote.kind];
                final icon = await showKindIconPicker(
                  context,
                  entry is Map && entry['icon'] is String
                      ? entry['icon'] as String
                      : null,
                );
                if (icon == null || !mounted || !identical(vault, v)) return;
                try {
                  await workspace.configureKind(
                    currentNote.kind,
                    icon: icon,
                    label: labelForKind(currentNote.kind) == 'Entity'
                        ? currentNote.kind
                        : labelForKind(currentNote.kind),
                  );
                } catch (error) {
                  if (context.mounted) {
                    showSnack(context, 'Could not save kind: $error');
                  }
                }
              },
            ),
          Expanded(
            child: references == null || keyboardUp || currentDaily != null
                ? content
                // The references panel may take at most 40% of what is left
                // under the header, so the page text always stays visible
                // (on the P30 it used to squeeze the editor to nothing).
                : LayoutBuilder(
                    builder: (context, constraints) => Column(
                      children: [
                        Expanded(child: content),
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: constraints.maxHeight * 0.4,
                          ),
                          child: references,
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      );
    }
    if (workspace.extensionName case final name?) {
      documentContent = Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: kSpace16,
                vertical: kSpace4,
              ),
              child: Text(
                'extension · $name',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ),
          Expanded(child: documentContent),
        ],
      );
    }
    final enrichDay = _enrichDecisions;
    final enrichView = mode == 'normal' && enrichDay?.$1 == current
        ? enrichDay?.$2
        : null;
    final suggestionCount = enrichView == null
        ? 0
        : enrichView.decisions.length +
              enrichView.tags.length +
              enrichView.markers.length;
    if (documentModes.contains(mode) &&
        currentNote != null &&
        currentNote.kind == 'idea' &&
        currentDaily == null) {
      documentContent = Column(
        children: [
          IdeaProperties(
            note: currentNote,
            onToggle: (enabled) async {
              try {
                final updated = await workspace.mutateNote(
                  currentNote.path,
                  (source) => setIdeaKind(currentNote.path, source, enabled),
                );
                if (!updated && context.mounted) {
                  showSnack(
                    context,
                    'Could not update that note: the vault changed.',
                  );
                }
              } catch (error) {
                if (context.mounted) {
                  showSnack(context, 'Could not update that note: $error');
                }
              }
            },
            onStatus: (value) => _setNoteProperty(currentNote, 'status', value),
          ),
          Expanded(child: documentContent),
        ],
      );
    }
    if (documentModes.contains(mode) &&
        currentDaily != null &&
        !(isTodayDocument && compactHeight)) {
      documentContent = Column(
        children: [
          if (keyboardUp)
            const SizedBox.shrink()
          else
            IdeaHubStrip(
              key: ValueKey((
                vault,
                workspace.indexRevision,
                isoDay(currentDaily),
              )),
              index: index,
              day: isoDay(currentDaily),
              readSource: (path) => vault!.storage.readText(path),
              onOpenPath: _openPath,
            ),
          Expanded(child: documentContent),
        ],
      );
    }
    if (documentModes.contains(mode) && currentDaily != null) {
      final day = isoDay(currentDaily);
      final external = oltIncomingOnDay(
        _oltCache,
        _oltDecided,
        day,
        pending: day == isoDay(DateTime.now()),
      );
      if (day == isoDay(DateTime.now())) {
        external.addAll(githubConflictNotes(workspace.githubConflicts));
      }
      final botMountIds = workspace.mounts
          .where((mount) => mount.source.extra['botVault'] == true)
          .map((mount) => mount.id)
          .toSet();
      external.addAll(
        botIncomingOnDay(
          index,
          botMountIds,
        ).where((note) => !_botDecidedItems.contains(note.id)),
      );
      final incomingCount = incomingOnDay(index, day).length + external.length;
      final referenceCount = dailyMore.isEmpty ? 0 : backlinks.length;
      dailyMore.insert(
        0,
        ListTile(
          key: const ValueKey('incoming-open'),
          title: const Text('Incoming suggestions'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showEnrichIncoming(),
        ),
      );
      dailyMore.insert(
        0,
        ScreenshotStrip(
          index: index,
          day: day,
          onOpenPath: _openPath,
          imageResolver: _readAsset,
          incoming: true,
          external: external,
          onDecide: (note, action) => unawaited(_decideIncoming(note, action)),
        ),
      );
      final dailyEditor = documentContent;
      documentContent = LayoutBuilder(
        builder: (context, constraints) => Column(
          children: [
            Expanded(child: dailyEditor),
            if (keyboardUp)
              const SizedBox.shrink()
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: constraints.maxHeight * 0.5,
                ),
                child: SingleChildScrollView(
                  child: ExpansionTile(
                    key: const ValueKey('daily-more'),
                    initiallyExpanded: _dailyMoreExpanded,
                    onExpansionChanged: (value) => _dailyMoreExpanded = value,
                    title: Text(
                      [
                        'More',
                        if (incomingCount > 0) '$incomingCount incoming',
                        if (suggestionCount > 0)
                          '$suggestionCount suggestion${suggestionCount == 1 ? '' : 's'}',
                        if (referenceCount > 0)
                          '$referenceCount reference${referenceCount == 1 ? '' : 's'}',
                      ].join(' · '),
                      style: Theme.of(context).textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    children: dailyMore,
                  ),
                ),
              ),
          ],
        ),
      );
    }
    final bodyContent = isTodayDocument
        ? PageStorage(
            bucket: _todayStorage,
            child: TodayPage(
              typing: keyboardUp,
              indexing: workspace.awaitingIndex,
              shownDay: currentDaily,
              onOpenDay: (day) => _stepDay(0, target: day),
              events: [
                for (final event in workspace.feedEvents)
                  CalendarItem(
                    date: event.date,
                    start: event.properties['start']?.toString(),
                    end: event.properties['end']?.toString(),
                    detail: event.properties['rooms']?.toString(),
                    source: 'ics',
                    kind: CalendarItemKind.dateRef,
                    title: event.title,
                    notePath: event.path,
                  ),
                ...oltCalendarOnDay(_oltCache, isoDay(currentDaily)),
              ],
              tasks: index?.tasks ?? const [],
              notes: index?.notesByPath ?? const {},
              onAllTasks: () => unawaited(_selectDestination(2, libraryTab: 3)),
              recent: _recentNotes(),
              editor: documentContent,
              onOpenPath: (path) {
                if (path.startsWith('olt:')) {
                  final item = oltCalendarOnDay(
                    _oltCache,
                    isoDay(currentDaily),
                  ).where((event) => event.notePath == path).firstOrNull;
                  showSnack(
                    context,
                    item == null
                        ? path
                        : '${item.title} · ${item.start ?? ''} · ${item.detail ?? ''}',
                  );
                  return;
                }
                unawaited(_openPath(path));
              },
              onSetStatus: _setTaskStatus,
              onSetField: _setTaskField,
              onReadPath: _readPath,
            ),
          )
        : documentContent;
    // Floats over the body (see workArea's Stack): transient status must
    // never take part in content layout, or every screen jumps when a sync
    // starts, changes stage, and ends.
    // Bottom-anchored: the top of the body is where the Library's tab bar
    // (Notes/Projects/Articles/…) lives, and a pill parked there hides the
    // tabs for the whole of an index run.
    final runningTask = _runningTask;
    Widget statusPill({
      required Widget child,
      Key? key,
      bool interactive = false,
    }) => IgnorePointer(
      ignoring: !interactive,
      key: key,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.only(bottom: kSpace4),
          child: Material(
            key: interactive ? _taskClockBounds : null,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            elevation: 2,
            borderRadius: BorderRadius.circular(kRadiusLarge),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 360),
              padding: const EdgeInsets.fromLTRB(
                kSpace16,
                kSpace8,
                kSpace16,
                kSpace8,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
    // Two slots: the error banner is interactive (Retry) and stays pinned at
    // the top; the transient pills float at the bottom, clear of the tab bar.
    Widget statusBanner({required bool error}) => ListenableBuilder(
      listenable: Listenable.merge([workspace, workspace.syncProgressTick]),
      builder: (context, _) {
        final openFailed = status.startsWith('Open failed:');
        final saveFailed = status.startsWith('Save failed');
        final markupLine = mode == 'normal'
            ? richController.syntaxErrorLine
            : null;
        final failed = openFailed || saveFailed || markupLine != null;
        final banner = failed
            ? appBanner(
                key: ValueKey(
                  markupLine == null ? 'status-error' : 'markup-error',
                ),
                backgroundColor: Theme.of(context).colorScheme.errorContainer,
                content: Text(
                  markupLine != null && !openFailed && !saveFailed
                      ? 'This note has broken markup on line $markupLine.'
                      : saveFailed
                      ? 'Could not save your note. Your edits are still here.'
                      : status,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () =>
                        markupLine != null && !openFailed && !saveFailed
                        ? _setEditorMode('source')
                        : saveFailed
                        ? unawaited(_save())
                        : unawaited(_open()),
                    child: Text(
                      markupLine != null && !openFailed && !saveFailed
                          ? 'Open Source'
                          : saveFailed
                          ? 'Retry Save'
                          : 'Retry',
                    ),
                  ),
                ],
              )
            : (v != null && (index == null || rebuildProgress != null))
            ? statusPill(
                key: const ValueKey('status-progress'),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      syncing && syncStage != null
                          ? syncStageLabel(syncStage!)
                          : status,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: kSpace4),
                    LinearProgressIndicator(value: rebuildProgress),
                  ],
                ),
              )
            : const SizedBox.shrink(key: ValueKey('status-none'));
        return AnimatedSwitcher(
          key: error ? null : _statusPillBounds,
          duration: kMotionStatus,
          child: failed == error
              ? banner
              : const SizedBox.shrink(key: ValueKey('status-none')),
        );
      },
    );
    final typing = keyboardUp;
    final workArea = WorkSurface(
      child: Stack(
        children: [
          Positioned.fill(child: bodyContent),
          // left/right pinned on both so the MaterialBanner keeps a tight
          // width; only one vertical edge, so each shrink-wraps its height.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: statusBanner(error: true),
          ),
          // While the keyboard is up the editor's tool row sits at the bottom
          // of this area; the transient pills move to the top then so they
          // never cover the editing tools.
          Positioned(
            top: typing ? 0 : null,
            bottom: typing ? null : (runningTask == null ? 0 : 60),
            left: 0,
            right: 0,
            child: statusBanner(error: false),
          ),
          if (runningTask != null)
            Positioned(
              top: typing ? 56 : null,
              bottom: typing ? null : 0,
              left: 0,
              right: 0,
              child: statusPill(
                key: const ValueKey('task-clock-pill'),
                interactive: true,
                child: TaskClock(
                  task: runningTask,
                  onStop: (task) => _setTaskStatus(task, 'todo'),
                  onOpen: () => unawaited(_openPath(runningTask.notePath)),
                ),
              ),
            ),
        ],
      ),
    );

    final wideNavigation =
        MediaQuery.sizeOf(context).width >= 900 || compactHeight;
    final canGoBack =
        _backViews.isNotEmpty || primaryDestination != 0 || mode != 'normal';
    final desktop =
        Theme.of(context).platform == TargetPlatform.macOS ||
        Theme.of(context).platform == TargetPlatform.windows ||
        Theme.of(context).platform == TargetPlatform.linux;
    return PopScope<void>(
      canPop: !canGoBack,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: compactHeight ? 48 : 56,
          automaticallyImplyLeading: false,
          // The slot is always there, so the title never jumps when the
          // back button appears (e.g. stepping from Today to another day).
          leading:
              canGoBack &&
                  (!desktop || _backViews.isNotEmpty || mode == 'graph')
              ? BackButton(onPressed: _back)
              : const SizedBox.shrink(),
          centerTitle: false,
          title: mode == 'journal'
              ? _swipeDay(
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: EdgeInsets.only(left: wideNavigation ? 25 : 0),
                        child: CompactDateTitle(
                          day: currentDaily ?? DateTime.now(),
                        ),
                      ),
                    ),
                  ),
                )
              : mode == 'library'
              ? const Text('Library')
              : mode == 'graph'
              ? const Text('Graph')
              : documentModes.contains(mode) && currentDaily != null
              // The date alone (no day arrows): it opens the calendar.
              ? _swipeDay(
                  Tooltip(
                    message: 'Calendar',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(kRadiusSmall),
                      onTap: () => unawaited(_showCalendarPicker()),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: ValueListenableBuilder<bool>(
                            valueListenable: workspace.dirtyNotifier,
                            builder: (context, dirty, _) => Padding(
                              padding: EdgeInsets.only(
                                left: wideNavigation ? 25 : 0,
                              ),
                              child: CompactDateTitle(
                                day: currentDaily,
                                dirty: dirty,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              : ValueListenableBuilder<bool>(
                  valueListenable: workspace.dirtyNotifier,
                  builder: (context, dirty, _) => Text(
                    dirty ? '$currentTitle •' : currentTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
          actions: [
            ProcessingBadge(
              jobs: _processingJobs,
              onOpen: () => unawaited(_showProcessing()),
            ),
            IconButton(
              tooltip: 'Timestamped capture',
              icon: const Icon(Icons.more_time),
              onPressed: () => unawaited(_captureTimestamp()),
            ),
            if (mode == 'journal')
              IconButton(
                tooltip: 'Choose journal date',
                onPressed: () => unawaited(_showCalendarPicker()),
                icon: const Icon(AppIcons.calendarDate),
              ),
            if (mode == 'graph')
              PopupMenuButton<String>(
                tooltip: 'Graph view',
                icon: Icon(switch (_graphMode) {
                  'conceptMap' => Icons.bubble_chart,
                  'allFiles' => AppIcons.graph,
                  'timeline' => Icons.timeline,
                  'voronoi' => Icons.hive,
                  _ => Icons.center_focus_strong,
                }),
                onSelected: (value) => setState(() {
                  _graphMode = value;
                  _graphFocusPath = null;
                }),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'local', child: Text('Focused')),
                  PopupMenuItem(value: 'conceptMap', child: Text('Overview')),
                  PopupMenuDivider(),
                  PopupMenuItem(value: 'allFiles', child: Text('All files')),
                  PopupMenuItem(value: 'timeline', child: Text('Timeline')),
                  PopupMenuItem(value: 'voronoi', child: Text('Voronoi')),
                ],
              ),
            if (mode == 'normal' && _usePlainLongEditor && v != null)
              ListenableBuilder(
                listenable: _plainHistoryRevision,
                builder: (context, _) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Undo',
                      icon: const Icon(Icons.undo),
                      onPressed: _plainEditorKey.currentState?.canUndo == true
                          ? () => _plainEditorKey.currentState?.undo()
                          : null,
                    ),
                    IconButton(
                      tooltip: 'Redo',
                      icon: const Icon(Icons.redo),
                      onPressed: _plainEditorKey.currentState?.canRedo == true
                          ? () => _plainEditorKey.currentState?.redo()
                          : null,
                    ),
                  ],
                ),
              ),
            if (documentModes.contains(mode))
              PopupMenuButton<String>(
                tooltip: 'View mode',
                icon: Icon(switch (mode) {
                  'read' => Icons.chrome_reader_mode_outlined,
                  'preview' => Icons.preview_outlined,
                  'source' => Icons.code,
                  'split' => Icons.vertical_split,
                  _ => AppIcons.edit,
                }),
                onSelected: (value) {
                  if (value == 'split') {
                    unawaited(_runShellAction(_ShellAction.split, linksPanel));
                  } else {
                    _setEditorMode(value);
                  }
                },
                itemBuilder: (_) => [
                  for (final (value, label, icon) in const [
                    ('normal', 'Edit', AppIcons.edit),
                    ('read', 'Read', Icons.chrome_reader_mode_outlined),
                    ('preview', 'Preview', Icons.preview_outlined),
                    ('source', 'Source', Icons.code),
                    ('split', 'Split', Icons.vertical_split),
                  ])
                    PopupMenuItem(
                      value: value,
                      height: 48,
                      child: Row(
                        children: [
                          Icon(icon),
                          const SizedBox(width: kSpace12),
                          Expanded(child: Text(label)),
                          if (mode == value) const Icon(Icons.check),
                        ],
                      ),
                    ),
                ],
              ),
            ListenableBuilder(
              listenable: Listenable.merge([
                workspace,
                workspace.syncProgressTick,
              ]),
              builder: (context, _) => SyncIconButton(
                syncing: syncing,
                vaultOpen: v != null,
                storageHealthy: storageHealthy ?? true,
                configured: cloud?.isReady ?? false,
                desktopManaged: desktopManaged,
                error: syncError,
                conflicts: syncConflicts.length,
                result: lastSync,
                onPressed: _showSyncDashboard,
              ),
            ),
          ],
        ),
        floatingActionButton:
            documentModes.contains(mode) &&
                (mode == 'source' || mode == 'split')
            ? Padding(
                padding: const EdgeInsets.only(bottom: 52),
                child: FloatingActionButton.extended(
                  onPressed: _showMagicMenu,
                  icon: const Icon(Icons.auto_fix_high),
                  label: const Text('Add to note'),
                ),
              )
            : null,
        bottomNavigationBar: wideNavigation
            ? null
            : NavigationBar(
                selectedIndex: primaryDestination,
                onDestinationSelected: (destination) {
                  if (destination == 4) {
                    unawaited(_showMoreMenu(linksPanel));
                  } else {
                    unawaited(_selectDestination(destination));
                  }
                },
                destinations: const [
                  NavigationDestination(
                    icon: Icon(AppIcons.today),
                    label: 'Today',
                  ),
                  NavigationDestination(
                    icon: Icon(AppIcons.daily),
                    label: 'Journal',
                  ),
                  NavigationDestination(
                    icon: Icon(AppIcons.library),
                    label: 'Library',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.search),
                    label: 'Search',
                  ),
                  NavigationDestination(
                    icon: Icon(AppIcons.overflow),
                    label: 'More',
                  ),
                ],
              ),
        body: wideNavigation
            ? Row(
                children: [
                  NavigationRail(
                    selectedIndex: primaryDestination,
                    onDestinationSelected: (destination) {
                      if (destination == 4) {
                        unawaited(_showMoreMenu(linksPanel));
                      } else {
                        unawaited(_selectDestination(destination));
                      }
                    },
                    scrollable: compactHeight,
                    labelType: compactHeight
                        ? NavigationRailLabelType.none
                        : NavigationRailLabelType.all,
                    destinations: const [
                      NavigationRailDestination(
                        icon: Icon(AppIcons.today),
                        label: Text('Today'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(AppIcons.daily),
                        label: Text('Journal'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(AppIcons.library),
                        label: Text('Library'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.search),
                        label: Text('Search'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(AppIcons.overflow),
                        label: Text('More'),
                      ),
                    ],
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: workArea),
                ],
              )
            : workArea,
      ),
    );
  }

  String _currentTitle(String? current) => current == null
      ? 'Today'
      : index?.notesByPath[current]?.title ??
            current.split('/').last.replaceFirst('.typ', '');

  /// A dialog text field. The app-wide theme sets `InputBorder.none` for the
  /// editor surfaces, which leaves dialog fields with no visible affordance —
  /// every dialog field goes through here so they cannot drift apart again.
  Widget _dialogField(
    TextEditingController controller, {
    required String label,
    String? hint,
    String? helper,
    bool autofocus = false,
    bool obscureText = false,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    List<String>? autofillHints,
    ValueChanged<String>? onChanged,
    ValueChanged<String>? onSubmitted,
    // URLs, logins and paths: Gboard's autocorrect otherwise splits
    // "soundingdoubts" and adds spaces after dots, even with a URL keyboard.
    bool plain = false,
  }) => TextField(
    controller: controller,
    autofocus: autofocus,
    obscureText: obscureText,
    autocorrect: !plain,
    enableSuggestions: !plain,
    keyboardType: keyboardType,
    textInputAction: textInputAction,
    autofillHints: autofillHints,
    onChanged: onChanged,
    onSubmitted: onSubmitted,
    decoration: InputDecoration(
      border: const OutlineInputBorder(),
      labelText: label,
      hintText: hint,
      helperText: helper,
    ),
  );
}

enum _ShellAction {
  namespace,
  processing,
  vaults,
  newPage,
  newEntity,
  sharePdf,
  graph,
  split,
  backlinks,
  settings,
}

List<String> _csvValues(String value) =>
    value
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
