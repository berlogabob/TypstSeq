import 'reading_log.dart';
import 'dart:async';
import 'widgets/app_icons.dart';
import 'calendar_feeds.dart';
import 'dart:ui' show AppExitResponse;
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, listEquals;
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:typst_flutter/typst_flutter.dart';
import 'package:tylog_audio/tylog_audio.dart'
    show audioDurationMs, peaksFromWav;
import 'package:tylog_core/enrich.dart';
import 'package:tylog_core/values.dart';
import 'package:url_launcher/url_launcher.dart';

import 'ai/ai_settings.dart';
import 'article_jobs.dart';
import 'bibliography.dart';
import 'controlled_editor.dart';
import 'editor_autocomplete.dart' show MentionQueryCache;
import 'entity_kinds.dart';
import 'graph.dart';
import 'knowledge_screen.dart';
import 'saved_searches.dart';
import 'markdown_article_import.dart';
import 'screenshots_ocr.dart';
import 'widgets/screenshot_strip.dart';
import 'models.dart';
import 'month_calendar.dart';
import 'nextcloud_sync.dart';
import 'nextcloud_sync/conflict_choice.dart';
import 'package:tylog_core/validation.dart';
import 'platform_file_actions.dart';
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
import 'widgets/entity_header.dart';
import 'widgets/enrich_review.dart';
import 'widgets/linked_references.dart';
import 'widgets/dialogs.dart';
import 'widgets/editor_panel.dart';
import 'widgets/journal_feed.dart';
import 'widgets/links_panel.dart';
import 'widgets/loading.dart';
import 'widgets/reading_mode.dart';
import 'widgets/screenshot_view.dart';
import 'audio/audio_note_doc.dart';
import 'audio/processing_policy.dart';
import 'audio/transcript_jobs.dart';
import 'module_pack_io.dart';
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
part 'app_mobile/article_links_flow.dart';
part 'app_mobile/audio_flow.dart';
part 'app_mobile/markdown_import_flow.dart';
part 'app_mobile/module_flow.dart';
part 'app_mobile/vault_import_flow.dart';
part 'app_mobile/vault_lifecycle.dart';

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
  final Set<String> _reservedTaskIds = {};
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
  // Graph overview mode: 'conceptMap' (default), 'local', or 'allFiles'.
  String _graphMode = 'conceptMap';
  // Concept/note path the local graph is rooted at when expanded from the map.
  String? _graphFocusPath;

  final _graphCache =
      <
        ({int revision, String mode, String? focus, String? current}),
        NoteGraph
      >{};
  int _graphCacheRevision = -1;

  /// The graph for the current pane, built at most once per set of inputs.
  ///
  /// Keyed on [WorkspaceController.indexRevision] rather than the index object:
  /// the controller retains the index in place, so its identity never changes
  /// and an `identical` check would cache the first graph forever.
  NoteGraph _memoizedGraph(String? current) {
    final key = (
      revision: workspace.indexRevision,
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
      'conceptMap' => buildConceptMap(idx),
      // The treemap renders straight from the index; no note graph needed.
      'voronoi' => const NoteGraph(nodes: [], edges: []),
      'allFiles' => buildNoteGraph(idx),
      'timeline' => buildTimelineGraph(idx, {
        for (final r in _mergedRecent()) r.path: isoDay(r.openedAt),
      }),
      _ => buildLocalNoteGraph(idx, _graphFocusPath ?? current),
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

  Vault? get vault => workspace.vault;
  VaultIndex? get index => workspace.index;
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
  String? _timestampCapturePath;
  (Vault?, String?)? _editorNote;
  bool _plainLongEditor = false;
  bool get _usePlainLongEditor =>
      note != _timestampCapturePath && _plainLongEditor;
  static const _shareChannel = MethodChannel('org.tylog.tylog/share');
  bool _handlingShare = false;
  List<ArticleJob> _articleJobs = const [];
  int _articleJobsGeneration = 0;
  (Vault?, bool, int)? _jobsRevision;

  Future<void> _refreshArticleJobs() async {
    final generation = ++_articleJobsGeneration;
    final currentVault = vault;
    if (currentVault == null) {
      _articleJobs = const [];
      return;
    }
    try {
      final jobs = await loadArticleJobs(currentVault.storage);
      if (mounted &&
          identical(vault, currentVault) &&
          generation == _articleJobsGeneration) {
        setState(() => _articleJobs = jobs);
      }
    } catch (error) {
      if (mounted) showSnack(context, 'Could not read article jobs: $error');
    }
  }

  Future<void> _handlePendingShares() async {
    if (_handlingShare || vault == null || !mounted) return;
    _handlingShare = true;
    try {
      while (mounted && vault != null) {
        final data = await _shareChannel.invokeMapMethod<String, String>(
          'getPendingShare',
        );
        if (data == null || !mounted || vault == null) break;
        final path = data['path'];
        final mime = data['mime'] ?? '';
        final text = data['text'] ?? '';
        final article = SharedArticle.parse(text, title: data['title']);
        final targetVault = vault!;
        final audioNote =
            path != null && mime.startsWith('audio/') && isAudioPath(path);
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
          targetVault.restoreWriteMarkers(
            article.path,
            stale: false,
            pendingSync: true,
          );
          workspace.queueCloudSync();
          await _refreshArticleJobs();
          if (mounted) showSnack(context, 'Article queued');
        } else if (choice == 'audio' && path != null) {
          await _saveSharedAudio(File(path));
        } else if (choice == 'attach' && path != null) {
          if (!await _captureTimestamp()) continue;
          if (!mounted || !identical(vault, targetVault)) continue;
          await _attachFile(File(path));
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
  Vault? _enrichPassVault;
  (Vault, DateTime, EnrichMemory)? _enrichMemoryCache;
  (Object, _EnrichView)? _enrichMemo;
  (String, _EnrichView)? _enrichDecisions;
  bool _enrichBusy = false;
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
    WidgetsBinding.instance.removeObserver(this);
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
          !listEquals(
            incoming.blocks
                .expand((b) => b.parts)
                .expand(
                  (p) => p.text
                      .split('')
                      .where((c) => c != '\n')
                      .map((c) => (c, p.style, p.source)),
                )
                .toList(),
            current.blocks
                .expand((b) => b.parts)
                .expand(
                  (p) => p.text
                      .split('')
                      .where((c) => c != '\n')
                      .map((c) => (c, p.style, p.source)),
                )
                .toList(),
          ) ||
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
        richController.foldScope = note;
        richController.loadSource(workspace.source);
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
    _refreshNoteAssets(_currentSource());
    workspace.edit(_currentSource());
  }

  String _currentSource() => sourceController.text;

  /// Vault-relative asset bytes for the open note, loaded by [_loadNoteAssets]
  /// so the synchronous [_typstFiles] can hand them to the Typst compiler.
  final Map<String, Uint8List> _noteAssetFiles = {};
  int _assetRevision = 0;
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
  Future<void> _refreshNoteAssets(String source) {
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
    final paths = RegExp(
      r'"(/?assets/[^"]+\.(?:png|jpe?g|gif|svg|webp|bmp))"',
      caseSensitive: false,
    ).allMatches(source).map((m) => m.group(1)!).toSet();
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
    showSnack(context, 'Edit kept safe: $error');
  }

  Future<void> _tapProtected(String id) => _handleAtomSource(
    richController.protectedSource(id),
    allowEdit: true,
    protectedId: id,
  );

  Future<void> _longPressProtected(String id) async {
    final source = richController.protectedSource(id);
    final match = RegExp(
      r'^#tylog\.ref-note\s*\(\s*"((?:\\.|[^"\\])*)"',
    ).firstMatch(source.trim());
    if (match == null) return;
    final target = match[1]!.replaceAllMapped(RegExp(r'\\(.)'), (m) => m[1]!);
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: false,
      builder: (context) => AppSheet(
        title: 'Reference actions',
        children: [
          for (final action in ['Rename', 'Edit Typst', 'Remove'])
            ListTile(
              minTileHeight: 48,
              title: Text(action),
              onTap: () => Navigator.pop(context, action),
            ),
        ],
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'Edit Typst') {
      await _editProtectedBlock(id);
      return;
    }
    if (action == 'Remove') {
      richController.replaceProtected(id, '');
      return;
    }
    final resolution =
        workspace.linkResolver?.resolve(target) ?? _resolveLink(target);
    final path = resolution.path;
    if (path == null) {
      showSnack(context, 'Resolve this reference before renaming.');
      return;
    }
    final currentTitle =
        index?.notes.where((n) => n.path == path).firstOrNull?.title ?? target;
    var draftTitle = currentTitle;
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename note'),
        content: TextFormField(
          initialValue: currentTitle,
          onChanged: (value) => draftTitle = value,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Title'),
          onFieldSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, draftTitle),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    if (!mounted || title == null) return;
    if (_currentSource() != workspace.source) workspace.edit(_currentSource());
    final result = await workspace.renameNote(path, title);
    if (mounted) showSnack(context, result.message);
  }

  Future<void> _handleAtomSource(
    String source, {
    required bool allowEdit,
    String? protectedId,
  }) async {
    source = source.trim();
    final audio = RegExp(
      r'^#tylog\.attachment\("((?:\\.|[^"])*)",\s*kind:\s*"audio"',
    ).firstMatch(source);
    if (audio != null) {
      await _openAttachment(
        unescapeTypstString(audio[1]!).replaceFirst(RegExp(r'^/+'), ''),
      );
      return;
    }
    final match = RegExp(
      r'^#tylog\.date-ref\("(\d{4})-(\d{2})-(\d{2})"',
    ).firstMatch(source);
    if (match != null) {
      await _openDay(
        DateTime(
          int.parse(match.group(1)!),
          int.parse(match.group(2)!),
          int.parse(match.group(3)!),
        ),
      );
      return;
    }
    final link = RegExp(
      r'^#link\("(mailto:[^"]+|https?://[^"]+)"\)',
    ).firstMatch(source);
    if (link != null) {
      final uri = Uri.tryParse(link.group(1)!);
      if (uri != null && await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        if (!mounted) return;
        showSnack(context, "Couldn't open ${link.group(1)}");
      }
      return;
    }
    // Tapping a note reference (`@mention` / `[[link]]`) navigates to the
    // note; a dangling reference offers to create it (Logseq muscle memory),
    // an ambiguous one lets the user pick which owner to open.
    final ref = RegExp(
      r'^#tylog\.ref-note\("((?:\\.|[^"])*)"',
    ).firstMatch(source);
    if (ref != null) {
      final target = ref
          .group(1)!
          .replaceAll(r'\"', '"')
          .replaceAll(r'\\', r'\');
      final heading = refNoteHeading(source);
      final resolution =
          workspace.linkResolver?.resolve(target) ?? _resolveLink(target);
      switch (resolution.status) {
        case LinkResolutionStatus.resolved:
          await _openNote(resolution.path!, heading: heading);
        case LinkResolutionStatus.ambiguous:
          await _chooseLinkOwner(
            target,
            resolution.candidates,
            heading: heading,
          );
        case LinkResolutionStatus.unresolved:
          final recent = workspace.recentNotePaths[target];
          if (recent != null) {
            await _openNote(recent, heading: heading);
          } else {
            await _createFromLink(target, heading: heading);
          }
      }
      return;
    }
    if (allowEdit && protectedId != null) {
      await _editProtectedBlock(protectedId);
    }
  }

  Future<void> _createFromLink(String target, {String? heading}) async {
    final generation = ++_openGeneration;
    final v = vault;
    if (v == null) return;
    // The resolver lags behind a just-created note until the background
    // rescan lands (minutes on a big vault), so check the direct
    // title->file mapping before claiming the note doesn't exist. Same
    // sanitization as Vault.page.
    final direct =
        'notes/${target.trim().replaceAll(RegExp(r'[\\/]'), '-')}.typ';
    if (await v.storage.exists(direct)) {
      await _openNote(direct, heading: heading, generation: generation);
      return;
    }
    if (!mounted) return;
    final create = await showConfirmDialog(
      context,
      title: 'Create note?',
      message: 'No note called “$target”. Create it?',
      confirmLabel: 'Create',
    );
    if (!create || !mounted) return;
    final file = await workspace.createPage(target);
    // Open first — the refresh only serves future link resolution and can
    // block for minutes behind an in-flight full rebuild.
    await _openNote(file, heading: heading, generation: generation);
    if (heading == null && mounted) showSnack(context, 'Created $file');
    unawaited(workspace.refreshIndex(always: true));
  }

  Future<void> _chooseLinkOwner(
    String target,
    List<String> candidates, {
    String? heading,
  }) async {
    final generation = ++_openGeneration;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: false,
      builder: (context) => AppSheet(
        title: '“$target” matches ${candidates.length} notes',
        children: [
          for (final path in candidates)
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(path),
              onTap: () => Navigator.pop(context, path),
            ),
        ],
      ),
    );
    if (choice != null) {
      await _openNote(choice, heading: heading, generation: generation);
    }
  }

  Future<void> _editProtectedBlock(String id) async {
    final input = TextEditingController(
      text: richController.protectedSource(id),
    );
    final updated = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Typst block'),
        content: SizedBox(
          width: 640,
          child: TextField(
            controller: input,
            autofocus: true,
            minLines: 5,
            maxLines: 16,
            style: const TextStyle(fontFamily: 'monospace'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, input.text),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    if (updated != null) richController.replaceProtected(id, updated);
  }

  Future<bool> _openNote(
    String path, {
    String? heading,
    int? generation,
    bool rememberView = true,
    String? searchQuery,
    int? searchOffset,
  }) async {
    final request = generation ??= ++_openGeneration;
    final v = vault;
    if (v == null) return false;
    if (dirty && !await _save()) return false;
    if (!mounted || request != _openGeneration || vault != v) return false;
    late final ({String source, int mutationVersion, int editRevision})
    snapshot;
    try {
      snapshot = await workspace.readNoteSnapshot(path);
    } on StateError {
      return false;
    } on FileSystemException {
      return false;
    }
    if (!mounted || request != _openGeneration || vault != v) return false;
    final noteChanged = path != note;
    final fromToday =
        mode == 'normal' &&
        primaryDestination == 0 &&
        _backViews.isEmpty &&
        path != note;
    if (!workspace.adoptNoteRead(path, snapshot)) return false;
    if (rememberView &&
        (mode == 'library' || mode == 'journal' || mode == 'graph')) {
      _rememberView();
    } else if (rememberView && fromToday) {
      _rememberView(today: true);
    }
    _loadSource(snapshot.source);
    _searchRevealQuery = searchQuery;
    _searchRevealOffset = searchOffset;
    if (searchQuery != null) _searchRevealGeneration++;
    setState(() {
      mode = 'normal';
      if (noteChanged) _editScreenshot = false;
    });
    if (heading != null) {
      final text = richController.text;
      final exact = RegExp(
        '^${RegExp.escape(heading)}\$',
        multiLine: true,
      ).firstMatch(text);
      final offset = exact?.start ?? text.indexOf(heading);
      if (offset >= 0) {
        richController.selection = TextSelection.collapsed(offset: offset);
      } else {
        if (mounted) showSnack(context, 'Heading "$heading" not found');
      }
    }
    final entry = _activeRegistryEntry;
    if (entry != null) {
      // Adopt another device's position on the first local open of a note
      // this device has never read (recordOpen keeps a local record if any).
      var synced = 0.0;
      for (final r in workspace.mergedReading) {
        if (r.path == path) {
          synced = r.progress;
          break;
        }
      }
      unawaited(
        vaultRegistry!
            .recordOpen(entry, path, fallbackProgress: synced)
            .then((_) => _writeReadingFile()),
      );
    }
    return true;
  }

  Future<bool> _openToday() async {
    final generation = ++_openGeneration;
    final v = vault;
    if (v == null) return false;
    if (dirty && !await _save()) return false;
    if (!mounted || generation != _openGeneration || vault != v) return false;
    final path = await workspace.ensureTodayNote();
    if (!mounted || generation != _openGeneration || vault != v) return false;
    if (!await _openNote(path, generation: generation, rememberView: false)) {
      return false;
    }
    _todayNotePath = path;
    _todayOpenedAt = DateTime.now();
    return true;
  }

  Future<bool> _captureTimestamp() async {
    if (vault == null) return false;
    _navDebounce?.cancel();
    _navDay = null;
    try {
      final path = await workspace.ensureTodayNote();
      if (!mounted) return false;
      if (note != path && !await _openToday()) return false;
      if (!mounted || note != path) return false;
      _timestampCapturePath = path;
      _backViews.clear();
      _showEditor();
      richController.appendTimestamp(DateTime.now());
      setState(() => primaryDestination = 0);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _captureFocus.requestFocus();
      });
      return true;
    } catch (error) {
      if (mounted) showSnack(context, 'Could not capture: $error');
      return false;
    }
  }

  Future<bool> _openDay(DateTime day) async {
    final generation = ++_openGeneration;
    final v = vault;
    if (v == null) return false;
    if (dirty && !await _save()) return false;
    return _openNote(
      await workspace.ensureTodayNote(day),
      generation: generation,
    );
  }

  /// The day the arrows have stepped to but not opened yet. The header reads
  /// this first so a tap moves the date immediately.
  DateTime? _navDay;
  Timer? _navDebounce;
  int _openGeneration = 0;

  /// Steps the journal by [delta] days.
  ///
  /// Coalesced, because one step is not cheap: opening a day saves the dirty
  /// buffer, creates the month directory, checks for the file, writes it when
  /// missing and reads it back — five SAF round-trips that queue behind any
  /// running sync. Uncoalesced, a user who taps `>` four times waited for four
  /// of those sequences *and* left an empty daily note behind for every day
  /// merely passed through. Now the label moves on the tap, the taps collapse,
  /// and only the day actually landed on is created.
  void _stepDay(int delta, {DateTime? target}) {
    final from = _navDay ?? _dailyDateOf(note);
    if (from == null) return;
    final next = target ?? DateTime(from.year, from.month, from.day + delta);
    setState(() => _navDay = next);
    _navDebounce?.cancel();
    _navDebounce = Timer(const Duration(milliseconds: 180), () {
      final target = _navDay;
      if (target == null || !mounted) return;
      unawaited(
        _openDay(target).whenComplete(() {
          if (!mounted) return;
          // Only clear when nothing has stepped past this open in the meantime.
          if (_navDay == target) setState(() => _navDay = null);
        }),
      );
    });
  }

  /// Date of the currently open note when it is a daily journal file.
  DateTime? _dailyDateOf(String? path) {
    if (path == null) return null;
    final match = RegExp(
      r'^daily/\d{4}/\d{2}/(\d{4})-(\d{2})-(\d{2})\.typ$',
    ).firstMatch(path);
    if (match == null) return null;
    return DateTime(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  Future<void> _showCalendarPicker() async {
    final day = await showDialog<DateTime>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.all(kSpace12),
            child: MonthCalendar(
              screenshotDays: {
                for (final n in index?.notes ?? const <NoteRef>[])
                  if (n.kind == 'screenshot' && n.date != null) n.date!,
              },
              dayMarks: workspace.calendarDayMarks,
              initialMonth: _dailyDateOf(
                vault == null || note == null ? null : note!,
              ),
              onOpenDay: (day) => Navigator.pop(context, day),
            ),
          ),
        ),
      ),
    );
    if (day != null) await _openDay(day);
  }

  Future<void> _openLink(String title) async {
    final generation = ++_openGeneration;
    final v = vault;
    if (v == null) return;
    final event = workspace.feedEvents
        .where((e) => e.id == title || e.title == title)
        .firstOrNull;
    if (event != null) {
      await workspace.materializeEvent(event.path);
      await _openNote(event.path, generation: generation);
      return;
    }
    final existing = _pathForLink(title);
    if (existing != null) {
      await _openNote(existing, generation: generation);
      return;
    }
    final file = await workspace.createPage(title);
    await _openNote(file, generation: generation);
    if (mounted) showSnack(context, 'Created $file');
    // Without the refresh the new note stays unresolvable to every chip
    // until the next unrelated scan; run it behind the navigation.
    unawaited(workspace.refreshIndex(always: true));
  }

  Future<void> _newPage({String kind = 'note'}) async {
    if (_newPageInFlight) return;
    _newPageInFlight = true;
    final generation = ++_openGeneration;
    try {
      final v = vault;
      if (v == null) return;
      final title = await _askPageTitle();
      if (!mounted || generation != _openGeneration || vault != v) return;
      if (title == null || title.trim().isEmpty) return;
      final template = await _chooseTemplate(v);
      if (!mounted || generation != _openGeneration || vault != v) return;
      if (dirty && !await _save()) return;
      if (!mounted || generation != _openGeneration || vault != v) return;
      final file = await workspace.createPage(
        title,
        kind: kind,
        template: template,
      );
      if (!await _openNote(file, generation: generation)) return;
      unawaited(workspace.refreshIndex(always: true));
      if (mounted) showSnack(context, 'Created $file');
    } catch (error) {
      if (mounted) showSnack(context, 'Could not create page: $error');
    } finally {
      _newPageInFlight = false;
    }
  }

  Future<String?> _chooseTemplate(Vault v) async {
    final templates =
        (await v.storage.list(path: '_system/templates'))
            .where(
              (entity) => !entity.isDirectory && entity.path.endsWith('.typ'),
            )
            .map((entity) => entity.path)
            .toList()
          ..sort();
    if (templates.isEmpty) return null;
    if (!mounted) return null;
    return showDialog<String?>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Choose template'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context),
            child: const Text('Blank note'),
          ),
          for (final file in templates)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, file),
              child: Text(file.split('/').last),
            ),
        ],
      ),
    );
  }

  Future<String?> _askPageTitle() {
    final title = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New page'),
        content: _dialogField(
          title,
          label: 'Title',
          autofocus: true,
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, title.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _editCurrentMetadata() async {
    final v = vault;
    final ix = index;
    final n = note;
    if (v == null || ix == null || n == null) return;
    final path = n;
    final current = ix.notesByPath[path];
    if (current == null) return;
    if (current.metadataSource != 'typst-query') {
      final convert = await showConfirmDialog(
        context,
        title: 'Convert metadata header?',
        message:
            'This legacy or dynamic header could not be verified by Typst. Saving will replace only the metadata call with a canonical literal header; the note body is preserved.',
        confirmLabel: 'Convert',
      );
      if (!convert) return;
      if (!mounted) return;
    }
    final title = TextEditingController(text: current.title);
    final tagsText = TextEditingController(text: current.tags.join(', '));
    final aliases = TextEditingController(text: current.aliases.join(', '));
    final kindField = TextEditingController(text: current.kind);
    final email = TextEditingController(
      text: '${current.properties['email'] ?? ''}',
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit note metadata'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SelectableText('ID: ${current.id}'),
              _dialogField(title, label: 'Title'),
              _dialogField(tagsText, label: 'Tags, comma-separated'),
              _dialogField(aliases, label: 'Aliases, comma-separated'),
              _dialogField(
                kindField,
                label: 'Kind',
                hint: 'note, project, person, place…',
              ),
              _dialogField(
                email,
                label: 'Email',
                keyboardType: TextInputType.emailAddress,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved == true) {
      final kind = kindField.text.trim();
      final properties = Map<String, Object?>.from(current.properties);
      final emailText = email.text.trim();
      if (emailText.isEmpty) {
        properties.remove('email');
      } else {
        properties['email'] = emailText;
      }
      final updated = replaceNoteHeader(
        _currentSource(),
        NoteMetadataDraft(
          id: current.id,
          title: title.text.trim(),
          kind: kind.isEmpty ? current.kind : kind,
          project: current.project,
          date: current.date,
          tags: _csvValues(tagsText.text),
          aliases: _csvValues(aliases.text),
          properties: properties,
        ),
      );
      _loadSource(updated);
      _queueAutosave();
      await _save();
    }
  }

  Future<void> _showKnowledge({
    KnowledgeView initialView = KnowledgeView.search,
    String? initialQuery,
  }) async {
    if (!mounted) return;
    final v = vault;
    if (v == null) return;
    final generation = ++_destinationGeneration;
    ++_openGeneration;
    final previousDestination = primaryDestination;
    setState(() => primaryDestination = 3);
    final searchStore = SavedSearchStore(v.storage);
    var savedSearches = <SavedSearch>[];
    final ready = ValueNotifier<bool>(false);
    final navigator = Navigator.of(context);
    final route = MaterialPageRoute<void>(
      builder: (_) => ValueListenableBuilder<bool>(
        valueListenable: ready,
        builder: (_, loaded, _) => loaded
            ? ListenableBuilder(
                listenable: workspace,
                builder: (_, _) {
                  final ix =
                      index ??
                      VaultIndex(notesByPath: {}, backlinksByTarget: {});
                  Future<void> openFromSearch(
                    String path,
                    String? query,
                  ) async {
                    final selection = ++_destinationGeneration;
                    navigator.pop();
                    setState(() => primaryDestination = previousDestination);
                    await workspace.materializeEvent(path);
                    if (!mounted || selection != _destinationGeneration) {
                      return;
                    }
                    if (await _openNote(
                          path,
                          rememberView: false,
                          searchQuery: query,
                        ) &&
                        mounted) {
                      // Search is a route; recreate it when leaving its editor.
                      _rememberView(knowledge: initialView, searchQuery: query);
                      setState(() {});
                    }
                  }

                  return KnowledgeScreen(
                    onSetTaskStatus: _setTaskStatus,
                    onSetTaskField: _setTaskField,
                    initialView: initialView,
                    initialQuery: initialQuery ?? '',
                    index: ix,
                    search: (query, tag, status) =>
                        _searchNotes(ix, query, tag: tag, status: status),
                    searchState: workspace,
                    // The worker loads its search index on the first query,
                    // so the screen only waits for the note index itself.
                    searchReady: () =>
                        workspace.searchReady || workspace.index != null,
                    searchRevision: () => workspace.searchRevision,
                    // Checked per query: the controller may finish installing or
                    // indexing while the search screen is open.
                    vectorSearch: (query) async =>
                        await _semantic?.searchNotes(query) ?? const [],
                    citedSearch: (query) async =>
                        await _semantic?.citations(query) ?? const [],
                    resolveMissing: (id) {
                      final note = ix.notesByPath[id];
                      if (note == null) return null;
                      return PkmsSearchResult(
                        id: note.path,
                        path: note.path,
                        title: note.title,
                        kind: note.kind,
                        tags: note.tags,
                        score: 0,
                      );
                    },
                    savedSearches: savedSearches,
                    onSaveSearch: (search) async {
                      final next = [
                        ...savedSearches.where((s) => s.name != search.name),
                        search,
                      ];
                      await searchStore.save(next);
                      savedSearches = next;
                      _queueCloudSync();
                    },
                    onDeleteSearch: (search) async {
                      final next = savedSearches
                          .where((s) => s.name != search.name)
                          .toList();
                      await searchStore.save(next);
                      savedSearches = next;
                      _queueCloudSync();
                    },
                    problems: _knowledgeProblems(),
                    // Same close-and-open as a search hit, minus the reveal.
                    onOpenNote: (path) => unawaited(openFromSearch(path, null)),
                    onCaptureTimestamp: () {
                      Navigator.of(context).pop();
                      unawaited(_captureTimestamp());
                    },
                    onOpenSearchNote: (path, query) =>
                        openFromSearch(path, query),
                    onOpenSearchCitation: (citation, query) async {
                      if (citation.sourceKind == 'note') {
                        final path = await _resolveCitationPath(citation, ix);
                        if (path == null) {
                          if (mounted) {
                            showSnack(
                              context,
                              'Could not open ${citation.sourceTitle ?? citation.sourceLocator}',
                            );
                          }
                          return;
                        }
                        await _openSearchNote(
                          path,
                          previousDestination,
                          query: query,
                          offset: citation.startOffset,
                        );
                        return;
                      }
                      await _openCitation(citation);
                    },
                    onFixProblems: _fixProblems,
                  );
                },
              )
            : Scaffold(
                appBar: AppBar(title: const Text('Search')),
                body: const Center(child: CircularProgressIndicator()),
              ),
      ),
    );
    final closed = navigator.push<void>(route);
    bool current() =>
        mounted && generation == _destinationGeneration && vault == v;
    Future<void> prepare() async {
      if (dirty && !await _save()) {
        if (current() && route.isActive) navigator.removeRoute(route);
        return;
      }
      if (!current()) return;
      unawaited(_ensureSemanticController());
      final loaded = await searchStore.load();
      if (!current()) return;
      savedSearches = loaded;
      ready.value = true;
      unawaited(workspace.refreshIndex());
    }

    unawaited(prepare());
    await closed;
    // Ignore late storage completions once this route has closed.
    if (current()) {
      ++_destinationGeneration;
      if (initialView == KnowledgeView.search) {
        await _showToday();
      } else {
        setState(() => primaryDestination = previousDestination);
      }
    }
    // The outgoing route still listens during its reverse transition.
    route.completed.then((_) => ready.dispose());
  }

  /// The Problems-screen view: everything except sync conflicts (which route to
  /// their own resolver).
  List<PkmsProblem> _knowledgeProblems() =>
      (validation?.problems ?? index?.problems ?? const <PkmsProblem>[])
          .where((problem) => !problem.code.startsWith('sync-'))
          .toList();

  /// Resolves a tile's (or a whole group's) problems from the Problems screen.
  /// Returns the refreshed problem list when the vault changed, or null when
  /// the fix only navigates (opening duplicate owners to merge by hand).
  Future<List<PkmsProblem>?> _fixProblems(List<PkmsProblem> toFix) async {
    if (toFix.isEmpty) return null;
    switch (toFix.first.code) {
      case 'metadata-fallback':
        return _convertToManagedHeader(toFix);
      case 'metadata-query-failed':
        return _repairArticles(toFix);
      case 'duplicate-note-id':
      case 'duplicate-alias':
        await _openDuplicateOwners(toFix);
        return null;
      case 'broken-link':
        return _triageMissingPages(toFix);
      default:
        return null;
    }
  }

  /// Materialises the pages behind Logseq wikilinks that never had a file.
  /// Logseq treats `[[Tutorial]]` as a page regardless; the importer only
  /// reported them, so a migrated vault is left with thousands of broken links
  /// — and the persons and places the user expected are among them.
  Future<List<PkmsProblem>?> _triageMissingPages(
    List<PkmsProblem> problems,
  ) async {
    final v = vault;
    final ix = index;
    if (v == null || ix == null) return null;
    final targets = unresolvedLinkTargets(problems, {
      for (final note in ix.notes) ...note.tags,
    });
    if (targets.isEmpty) {
      showSnack(context, 'Every unresolved link is already a tag');
      return null;
    }
    final picked = await Navigator.of(context).push<Map<String, String>>(
      MaterialPageRoute(
        builder: (_) => TriageMissingPagesScreen(targets: targets),
      ),
    );
    if (picked == null || picked.isEmpty || !mounted) return null;
    if (picked.length > 100) {
      final go = await showConfirmDialog(
        context,
        title: 'Create ${picked.length} pages?',
        message: 'This writes ${picked.length} new notes, then reindexes once.',
        confirmLabel: 'Create',
      );
      if (!go || !mounted) return null;
    }
    // One id namespace for the whole batch: nextNoteId otherwise dedups against
    // the last written index, which cannot know about the note created a
    // millisecond ago — and a Cyrillic title slugs to nothing, so a run of them
    // would all collapse onto the same timestamp id.
    final ids = {for (final note in ix.notes) note.id};
    for (final entry in picked.entries) {
      await workspace.createPage(entry.key, kind: entry.value, knownIds: ids);
    }
    await workspace.refreshIndex(always: true);
    if (!mounted) return null;
    showSnack(context, 'Created ${picked.length} pages');
    return _knowledgeProblems();
  }

  /// Counts how many of [attempted] still carry [code] after a rescan — the
  /// fix snackbars report resolved-vs-still-failing, not bytes written.
  int _stillFlagged(Iterable<PkmsProblem> attempted, String code) {
    final subjects = attempted.map((p) => p.subject).toSet();
    return _knowledgeProblems()
        .where((p) => p.code == code && subjects.contains(p.subject))
        .length;
  }

  /// Repairs markdown-import artifacts that break a note's Typst metadata query
  /// ("formatting couldn't be read") so it re-parses as verified metadata.
  Future<List<PkmsProblem>?> _repairArticles(List<PkmsProblem> problems) async {
    final v = vault;
    if (v == null) return null;
    for (final problem in problems) {
      if (!await workspace.mutateNote(problem.subject, repairArticleTypst)) {
        if (mounted) {
          showSnack(context, 'Repair stopped because the vault changed.');
        }
        return null;
      }
    }
    await workspace.waitForMutationRefresh();
    if (!mounted) return null;
    final remaining = _stillFlagged(problems, 'metadata-query-failed');
    final resolved = problems.length - remaining;
    showSnack(
      context,
      remaining == 0
          ? 'Repaired ${problems.length} note${problems.length == 1 ? '' : 's'}'
          : resolved == 0
          ? "Couldn't repair $remaining note${remaining == 1 ? '' : 's'} — "
                'see Technical details for each error'
          : 'Repaired $resolved, $remaining still failing — '
                'see Technical details',
    );
    return _knowledgeProblems();
  }

  /// Upgrades legacy/fallback-parsed notes to a managed `tylog.note.with(...)`
  /// header, rebuilt from the already-parsed metadata (body untouched).
  Future<List<PkmsProblem>?> _convertToManagedHeader(
    List<PkmsProblem> problems,
  ) async {
    final v = vault;
    final ix = index;
    if (v == null || ix == null) return null;
    var converted = 0;
    var alreadyManaged = 0;
    for (final problem in problems) {
      final note = ix.notesByPath[problem.subject];
      if (note == null) continue;
      var changed = false;
      if (!await workspace.mutateNote(problem.subject, (source) {
        if (source.contains('tylog.note.with(')) {
          // The header is fine — the note is flagged because Typst couldn't
          // verify it (engine timeout/death). Rewriting the header from
          // fallback-parsed metadata fixes nothing and risks baking
          // body-recovered tags into it.
          return source;
        }
        final updated = replaceNoteHeader(
          source,
          NoteMetadataDraft.fromNote(note),
        );
        changed = updated != source;
        return updated;
      })) {
        if (mounted) {
          showSnack(context, 'Conversion stopped because the vault changed.');
        }
        return null;
      }
      if (changed) converted++;
      if (!changed) alreadyManaged++;
    }
    await workspace.waitForMutationRefresh();
    if (!mounted) return null;
    final remaining = _stillFlagged(problems, 'metadata-fallback');
    final parts = [
      if (converted > 0)
        'Converted $converted note${converted == 1 ? '' : 's'}',
      if (alreadyManaged > 0)
        '$alreadyManaged already managed — Typst couldn\'t verify '
            'th${alreadyManaged == 1 ? 'at note' : 'ose notes'}',
    ];
    showSnack(
      context,
      parts.isEmpty
          ? 'Nothing to convert'
          : '${parts.join('; ')}'
                '${remaining > 0 ? ' ($remaining still unverified)' : ''}',
    );
    return _knowledgeProblems();
  }

  /// A duplicated id/date can only be resolved by a human merge, so list every
  /// file that claims it and open the tapped one. Accepts a whole group so the
  /// list's "Open files" action shows all duplicates, not just the first.
  Future<void> _openDuplicateOwners(List<PkmsProblem> problems) async {
    List<String> owners(PkmsProblem problem) =>
        problem.targets.isNotEmpty ? problem.targets : [problem.subject];
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: false,
      builder: (context) => AppSheet(
        title: 'Duplicate owners',
        children: [
          const ListTile(
            subtitle: Text('Open each to compare, then merge or delete one.'),
          ),
          for (final problem in problems) ...[
            ListTile(
              title: Text(
                '“${problem.subject}” is claimed by ${owners(problem).length} files',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            for (final path in owners(problem))
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(path),
                onTap: () => Navigator.pop(context, path),
              ),
          ],
        ],
      ),
    );
    if (choice == null || !mounted) return;
    Navigator.pop(context); // leave the Problems screen
    await _openPath(choice);
  }

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

  Future<void> _syncNow({String trigger = 'manual'}) async {
    try {
      await workspace.syncNow(trigger: trigger);
    } on WorkspaceSyncNotConfigured {
      await _showSyncSettings();
    }
  }

  Future<bool> _showSyncSettings() async {
    if (workspace.syncing) {
      showSnack(context, 'Sync already in progress');
      return false;
    }
    final vaultId = vaultRegistry?.activeId;
    var cfg =
        await NextcloudConfig.load(vaultId: vaultId) ??
        cloud ??
        await NextcloudConfig.load();
    if (!mounted) return false;
    while (true) {
      if (!mounted) return false;
      if (workspace.syncing) {
        showSnack(context, 'Sync already in progress');
        return false;
      }
      final saved = await showDialog<NextcloudConfig>(
        context: context,
        builder: (context) => NextcloudConnectDialog(config: cfg),
      );
      if (saved == null || !mounted) return false;
      cfg = saved;
      final opened = vault;
      final registry = vaultRegistry;
      if (opened == null || registry == null) return false;
      try {
        final local = await inspectLocalSync(opened);
        final remote = await NextcloudSync(saved).inspectRemoteVault();
        if (!mounted) return false;
        if (remote.kind == RemoteVaultKind.nonVault) {
          await _showNextcloudSetupError(
            'This cloud folder contains files but is not a TyLog vault. Choose another folder.',
          );
          continue;
        }
        final mode = await _confirmInitialSync(local, remote);
        if (mode == null || !mounted) return false;
        await registry.setCloud(registry.active, saved);
        if (!mounted) return false;
        setState(() {
          cloud = saved;
          status = 'Nextcloud connected · starting initial sync';
        });
        final connected = await workspace.syncNow(
          trigger: 'setup',
          configOverride: saved,
          initialMode: mode,
        );
        if (!connected) return false;
        setState(() {
          status = 'Nextcloud connected';
        });
        _startCloudPolling();
        return true;
      } catch (error) {
        if (!mounted) return false;
        await _showNextcloudSetupError(friendlySyncError(error));
      }
    }
  }

  Future<InitialSyncMode?> _confirmInitialSync(
    LocalSyncInspection local,
    RemoteVaultInspection remote,
  ) async {
    final localHasData = local.hasUserContent;
    final remoteHasData =
        remote.kind == RemoteVaultKind.validVault && remote.userFileCount > 0;
    final mode = initialSyncModeFor(
      localHasData: localHasData,
      remoteHasData: remoteHasData,
    );
    final (title, message, action) = switch ((localHasData, remoteHasData)) {
      (false, false) => (
        'Start new cloud sync?',
        'Both vaults are empty. TyLog will create the cloud folder and upload the starter vault.',
        'Start sync',
      ),
      (true, false) => (
        'Upload local vault?',
        'The local vault has ${local.userFileCount} user files and the cloud folder is empty.',
        'Upload local vault',
      ),
      (false, true) => (
        'Use cloud vault?',
        'The cloud vault has ${remote.userFileCount} user files. TyLog will download them and replace only untouched starter notes.',
        'Use cloud vault',
      ),
      (true, true) => (
        'Merge both vaults?',
        'Unique files will copy both ways. Different files at the same path become conflicts; nothing is deleted.',
        'Safe merge',
      ),
    };
    final confirmed = await showConfirmDialog(
      context,
      title: title,
      message: message,
      confirmLabel: action,
      barrierDismissible: false,
    );
    return confirmed ? mode : null;
  }

  Future<void> _showNextcloudSetupError(String message) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Nextcloud not connected'),
      content: Text(message),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Back to setup'),
        ),
      ],
    ),
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
      _stopCloudPolling();
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

  /// Leaves Settings entirely (home and any group page) before an action
  /// that opens something else; one pop only closed the top page.
  void _closeSettings(BuildContext context) => Navigator.of(context).popUntil(
    (route) => !(route.settings.name?.startsWith(kSettingsRoute) ?? false),
  );

  Future<List<PkmsSearchResult>> _searchNotes(
    VaultIndex fallbackIndex,
    String query, {
    String? tag,
    String? status,
  }) async {
    final activeEntry = workspace.entry;
    if (activeEntry != null) {
      try {
        final db = await _databaseForVault(activeEntry);
        if (db != null && await db.nodeProjectionComplete()) {
          final ids = await db.searchNodeIds(query);
          final byId = {for (final note in fallbackIndex.notes) note.id: note};
          final pathsById = await db.nodePathsForIds(ids);
          return mergeKeywordResults([
            for (var i = 0; i < ids.length; i++)
              if ((byId[ids[i]] ?? fallbackIndex.notesByPath[pathsById[ids[i]]])
                  case final NoteRef note)
                if ((tag == null || note.tags.contains(tag)) &&
                    (status == null || note.properties['status'] == status))
                  PkmsSearchResult(
                    id: note.id,
                    path: note.path,
                    title: note.title,
                    kind: note.kind,
                    tags: note.tags,
                    score: ids.length - i,
                  ),
          ], await workspace.searchNotes(query, tag: tag, status: status));
        }
      } catch (_) {
        // The derived index is optional; preserve the existing search path.
      }
    }
    return workspace.searchNotes(query, tag: tag, status: status);
  }

  void _showSettings() {
    final initialStorageHealth = vault == null ? false : storageHealthy;
    final storageHealth = initialStorageHealth == null
        ? workspace.probeStorage()
        : Future.value(initialStorageHealth);
    final registry = vaultRegistry;
    final activeLocation = vaultEntryLocation(_activeRegistryEntry);
    final openError = status.startsWith('Open failed:');
    final vaultPath = openError
        ? [activeLocation, status].whereType<String>().join('\n')
        : activeLocation ?? status;

    Navigator.of(context)
        .push<void>(
          MaterialPageRoute(
            settings: const RouteSettings(name: kSettingsRoute),
            builder: (context) => FutureBuilder<bool>(
              future: storageHealth,
              initialData: initialStorageHealth,
              builder: (context, snapshot) {
                final healthy = snapshot.data;
                final syncStatusSubtitle = healthy == null
                    ? 'Checking folder access…'
                    : syncStatusTitle(
                        syncStatusKind(
                          vaultOpen: vault != null,
                          storageHealthy: healthy,
                          cloudConfigured: cloud?.isReady ?? false,
                          desktopManaged:
                              _localVaultDirectory != null &&
                              isNextcloudManagedVault(_localVaultDirectory!),
                          syncing: syncing,
                          error: syncError,
                          conflicts: syncConflicts.length,
                          result: lastSync,
                        ),
                        conflicts: syncConflicts.length,
                      );
                return SettingsSheet(
                  calendarSettings: workspace.calendarSettings,
                  onConfigureCalendars: workspace.configureCalendars,
                  vaultPath: vaultPath,
                  cloud: cloud,
                  syncing: syncing,
                  syncStatusSubtitle: syncStatusSubtitle,
                  vaultCount: registry?.entries.length ?? 0,
                  readAi: vault == null
                      ? null
                      : () => readAiSettings(vault!.storage),
                  writeAi: vault == null
                      ? null
                      : (settings) async {
                          await writeAiSettings(vault!.storage, settings);
                          unawaited(_syncNow());
                        },
                  readWorkers: vault == null
                      ? null
                      : () => readWorkers(vault!.storage),
                  audioPolicyRead: vault == null
                      ? null
                      : () => readAudioPolicy(vault!.storage),
                  audioPolicyWrite: vault == null
                      ? null
                      : (policy) async {
                          await writeAudioPolicy(vault!.storage, policy);
                          unawaited(_syncNow());
                        },
                  onProcessAudio: vault == null
                      ? null
                      : () async {
                          await requestProcessNow(vault!.storage);
                          unawaited(_syncNow());
                        },
                  screenshotsMode: registry?.screenshotsMode ?? 'off',
                  screenshotsTime: registry?.screenshotsTime ?? '03:00',
                  readScreenshotsStatus: () async => vault!.storage.readText(
                    '_system/screenshots/status.json',
                  ),
                  onConfigureScreenshots: (mode, time) async {
                    // The wanted mode syncs in ai.json, so any device can set it;
                    // the Mac applies it to its LaunchAgents.
                    final storage = vault!.storage;
                    final ai = await readAiSettings(storage);
                    await writeAiSettings(
                      storage,
                      ai.copyWith(
                        screenshots: ai.screenshots.copyWith(
                          mode: mode,
                          time: time,
                        ),
                      ),
                    );
                    if (Platform.isMacOS) {
                      await configureScreenshotsOcr(
                        vaultPath,
                        mode,
                        time,
                        scriptsDir: registry?.screenshotsFolder,
                      );
                      await registry?.setScreenshotsOcr(mode, time);
                    } else {
                      unawaited(_syncNow());
                    }
                  },
                  readScreenshotsWanted: () async {
                    final task = (await readAiSettings(
                      vault!.storage,
                    )).screenshots;
                    final mode = task.mode;
                    return mode == null ? null : (mode, task.time ?? '03:00');
                  },
                  screenshotsFolder: Platform.isMacOS
                      ? registry?.screenshotsFolder
                      : null,
                  onScreenshotsFolderChanged: !Platform.isMacOS
                      ? null
                      : (folder) async {
                          await registry?.setScreenshotsFolder(folder);
                          // Reinstall the agents so they run from the new folder.
                          await configureScreenshotsOcr(
                            vaultPath,
                            registry?.screenshotsMode ?? 'off',
                            registry?.screenshotsTime ?? '03:00',
                            scriptsDir: folder,
                          );
                          if (mounted) setState(() {});
                        },
                  onProcessScreenshots: () async {
                    if (Platform.isMacOS) {
                      await runScreenshotsBackfill(
                        vaultPath,
                        scriptsDir: registry?.screenshotsFolder,
                      );
                    } else {
                      await requestScreenshotsRun(vault!.storage);
                      unawaited(_syncNow());
                    }
                  },
                  pdfPaper: registry?.pdfPaper ?? 'a4',
                  onPdfPaperChanged: (paper) {
                    unawaited(registry?.setPdfPaper(paper) ?? Future.value());
                  },
                  themeMode: widget.themeMode,
                  onThemeModeChanged: (mode) {
                    widget.onThemeModeChanged?.call(mode);
                    unawaited(
                      registry?.setThemeMode(themeModeName(mode)) ??
                          Future.value(),
                    );
                  },
                  onManageVaults: () => Navigator.pop(context, true),
                  onNextcloud: () {
                    _closeSettings(context);
                    unawaited(_showSyncDashboard());
                  },
                  onEnableReminders: () async {
                    await taskScheduler.requestPermission();
                    await taskScheduler.reconcile(index?.tasks ?? const []);
                    if (context.mounted) {
                      showSnack(context, 'Task reminders enabled');
                    }
                  },
                  onMigrateEntityTypes: () async {
                    _closeSettings(context);
                    await _migrateEntityTypes();
                  },
                  onStripImportNoise: () async {
                    _closeSettings(context);
                    await _stripImportNoise();
                  },
                  onImportVault: () async {
                    _closeSettings(context);
                    await _importVault();
                  },
                  onInstallModule: () async {
                    _closeSettings(context);
                    await _showModules();
                  },
                  onProblems: () {
                    _closeSettings(context);
                    unawaited(
                      _showKnowledge(initialView: KnowledgeView.problems),
                    );
                  },
                  onRebuildIndex: () {
                    _closeSettings(context);
                    unawaited(_rebuildIndex(force: true));
                  },
                  onRelinkVault: () {
                    _closeSettings(context);
                    unawaited(_relinkVault());
                  },
                  onSemanticSearch: () {
                    _closeSettings(context);
                    unawaited(_showSemanticSearch());
                  },
                  onTypstHelp: () {
                    _closeSettings(context);
                    unawaited(_showTypstHelp());
                  },
                  onCheckForUpdates:
                      Platform.isMacOS || updater.windowsSelfUpdatable()
                      ? () {
                          _closeSettings(context);
                          unawaited(_checkForUpdates(silent: false));
                        }
                      : null,
                );
              },
            ),
          ),
        )
        .then((_) {
          if (mounted) setState(() {});
        });
  }

  Future<void> _showTypstHelp({String? error}) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(error == null ? 'Typst help' : 'Explain Typst error'),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (error != null) ...[
                  SelectableText(error),
                  if (deterministicTypstFix(error, _currentSource())
                      case final fix?)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: kSpace8),
                      child: Text(fix),
                    ),
                ],
                Wrap(
                  spacing: kSpace8,
                  children: [
                    for (final entry in const {
                      'Heading': '= Heading',
                      'Note link': '#tylog.ref-note("note-id")[Title]',
                      'Tag': '#tylog.tag("topic")',
                      'Date': '#tylog.date-ref("2026-07-05")[5 July]',
                      'Task': 'Task',
                    }.entries)
                      ActionChip(
                        label: Text(entry.key),
                        onPressed: () async {
                          final opened = vault;
                          if (opened == null) return;
                          final snippet = entry.key == 'Task'
                              ? taskSnippet(
                                  id: await opened.nextTaskId(
                                    'Task',
                                    reserved: _reservedTaskIds,
                                  ),
                                  text: 'Task',
                                )
                              : entry.value;
                          if (!context.mounted || !identical(vault, opened)) {
                            return;
                          }
                          if (entry.key == 'Task') {
                            _reservedTaskIds.add(taskField(snippet, 'id')!);
                          }
                          Navigator.pop(context);
                          _insertTypstSnippet(snippet);
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _openAttachment(String path) async {
    final v = vault;
    if (v == null || !isSafeVaultPath(path)) return;
    try {
      await _attachTasks[path];
      if (path.toLowerCase().endsWith('.pdf')) {
        final entry = workspace.entry;
        final bytes = await v.storage.readBytes(path);
        final db = entry == null ? null : await _databaseForVault(entry);
        if (!mounted || vault != v) return;
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) =>
                PdfReaderScreen(bytes: bytes, path: path, database: db),
          ),
        );
      } else if (isAudioPath(path)) {
        await _openAudioAsset(path);
      } else {
        await openPlatformFile(
          v.storage,
          path,
          localRoot: _localVaultDirectory,
        );
      }
    } catch (error) {
      if (mounted) showSnack(context, 'Could not open file: $error');
    }
  }

  Future<void> _openCitation(ChunkCitation citation) async {
    final v = vault;
    if (citation.sourceKind == 'note') {
      return;
    }
    if (v == null ||
        citation.sourceKind != 'pdf' ||
        !isSafeVaultPath(citation.sourceLocator) ||
        !citation.sourceLocator.toLowerCase().endsWith('.pdf')) {
      return;
    }
    try {
      final bytes = await v.storage.readBytes(citation.sourceLocator);
      final entry = workspace.entry;
      final db = entry == null ? null : await _databaseForVault(entry);
      if (!mounted || vault != v || db == null) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => PdfReaderScreen(
            bytes: bytes,
            path: citation.sourceLocator,
            database: db,
            initialSourceVersionId: citation.sourceVersionId,
            initialStartOffset: citation.startOffset,
            initialEndOffset: citation.endOffset,
          ),
        ),
      );
    } catch (error) {
      if (mounted) showSnack(context, 'Could not open citation: $error');
    }
  }

  Future<String?> _resolveCitationPath(
    ChunkCitation citation,
    VaultIndex ix,
  ) async {
    final entry = workspace.entry;
    final db = entry == null ? null : await _databaseForVault(entry);
    final pathsById = db == null
        ? const <String, String>{}
        : await db.nodePathsForIds([citation.sourceId]);
    final locatorsById = db == null
        ? const <String, String>{}
        : await db.sourceLocatorsForIds([citation.sourceId]);
    return resolveCitationPath(
      sourceId: citation.sourceId,
      sourceLocator: citation.sourceLocator,
      sourceTitle: citation.sourceTitle,
      pathsById: pathsById,
      locatorsById: locatorsById,
      titlesByPath: {for (final note in ix.notes) note.path: note.title},
    );
  }

  Future<void> _openSearchNote(
    String path,
    int previousDestination, {
    required String query,
    required int offset,
  }) async {
    final selection = ++_destinationGeneration;
    Navigator.of(context).pop();
    setState(() => primaryDestination = previousDestination);
    await workspace.materializeEvent(path);
    if (!mounted || selection != _destinationGeneration) return;
    if (await _openNote(
          path,
          rememberView: false,
          searchQuery: query,
          searchOffset: offset,
        ) &&
        mounted) {
      _rememberView(knowledge: KnowledgeView.search);
      setState(() {});
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

  Future<void> _updateReadingPreferences(
    double fontScale,
    bool nightMode,
  ) async {
    final registry = vaultRegistry;
    if (registry == null) return;
    await registry.updateReadingPreferences(
      fontScale: fontScale,
      nightMode: nightMode,
    );
  }

  /// Mirrors this device's recents/progress into the vault at
  /// `_system/reading/<deviceId>.json` so it syncs across devices. Best
  /// effort — vaults.json stays the offline source of truth for this device.
  Future<void> _writeReadingFile() async {
    final v = vault;
    final entry = _activeRegistryEntry;
    final id = vaultRegistry?.deviceId;
    if (v == null || entry == null || id == null || id.isEmpty) return;
    try {
      await v.storage.writeText(
        '_system/reading/$id.json',
        jsonEncode({
          'schema': 1,
          'recent': [for (final r in entry.recent) r.toJson()],
        }),
      );
    } catch (_) {}
  }

  /// Cross-device recents: the synced merged view overlaid by this device's
  /// in-memory registry (registry wins ties, so the local session stays
  /// authoritative). Degrades to exactly the registry list when no reading
  /// files exist in the vault.
  List<RecentNote> _mergedRecent() {
    final byPath = {for (final r in workspace.mergedReading) r.path: r};
    for (final r in _activeRegistryEntry?.recent ?? const <RecentNote>[]) {
      final existing = byPath[r.path];
      if (existing == null || !r.openedAt.isBefore(existing.openedAt)) {
        byPath[r.path] = r;
      }
    }
    return byPath.values.toList()
      ..sort((a, b) => b.openedAt.compareTo(a.openedAt));
  }

  Future<void> _recordReadingProgress(String path, double progress) async {
    final entry = _activeRegistryEntry;
    if (entry == null) return;
    await vaultRegistry!.recordProgress(entry, path, progress);
    unawaited(_writeReadingFile());
    if (progress < 0.98) return;
    // Finishing an article marks it read; richer custom statuses
    // (e.g. "summarized") are left alone.
    final finished = index?.notesByPath[path];
    final status = finished?.properties['status'] as String?;
    if (finished != null &&
        finished.kind == 'article' &&
        (status == null || status == 'unread' || status == 'reading')) {
      await _logReading(finished.title);
      await _setReadStatus(finished, 'read');
      await _setNoteProperty(finished, 'finished', isoDay(DateTime.now()));
    }
  }

  /// Appends a reading-log line to today's daily note so "what I read"
  /// survives even after the article file itself is deleted. Plain text on
  /// purpose — a link would dangle once the article is gone.
  Future<void> _logReading(String title, {String? rating, String? url}) async {
    final v = vault;
    if (v == null || title.trim().isEmpty) return;
    try {
      final dayPath = await workspace.ensureTodayNote();
      final safeTitle = escapeMarkup(title.trim());
      final line = readingLogLine(safeTitle, rating: rating, url: url);
      // The daily note may be the currently-open (possibly dirty) document;
      // writing to disk behind the editor's back would be clobbered by the
      // next autosave, so route through the editor buffer in that case.
      final isOpen = note == dayPath;
      final source = isOpen
          ? _currentSource()
          : await v.storage.readText(dayPath);
      final String updated;
      if (rating != null && source.contains('- Read: $safeTitle\n')) {
        // Finish-then-rate upgrades the existing line instead of duplicating.
        updated = source.replaceFirst('- Read: $safeTitle\n', '$line\n');
      } else if (source.contains(': $safeTitle')) {
        return; // already logged today
      } else {
        final header = source.contains('== Reading') ? '' : '\n\n== Reading';
        updated = '${source.trimRight()}$header\n$line\n';
      }
      if (isOpen) {
        _loadSource(updated);
        _queueAutosave();
      } else {
        await workspace.mutateNote(dayPath, (_) => updated);
      }
    } catch (_) {
      // Logging must never break the reading/rating flow.
    }
  }

  List<(NoteRef note, double progress)> _recentNotes() {
    final notesByPath = index?.notesByPath;
    if (notesByPath == null) return const [];
    final result = <(NoteRef, double)>[];
    for (final recent in _mergedRecent()) {
      if (recent.progress >= 0.98) continue; // finished — nothing to continue
      final note = notesByPath[recent.path];
      if (note == null) continue;
      if (!continueReadingEligible(note)) continue;
      result.add((note, recent.progress));
      if (result.length == 8) break;
    }
    return result;
  }

  /// Opens [path] straight into reading mode (the shelf/rail "resume" tap).
  void _readPath(String path) {
    final fromList = mode == 'library' || mode == 'journal' || mode == 'graph';
    unawaited(
      _openNote(path).then((opened) {
        if (!mounted || !opened) return;
        if (fromList ||
            (_backViews.isNotEmpty && _backViews.last.mode == 'today')) {
          setState(() => mode = 'read');
        } else {
          _enterView('read');
        }
      }),
    );
  }

  Future<void> _deleteArticle(NoteRef ref) async {
    final v = vault;
    if (v == null) return;
    final confirmed = await showConfirmDialog(
      context,
      title: ref.kind == 'screenshot' ? 'Delete screenshot?' : 'Delete article',
      message:
          '"${ref.title}" will be removed from the vault. '
          'There is no recovery.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    if (note == ref.path) {
      // Move the editor off the doomed file first, so a dirty autosave
      // can't resurrect it; then return to the library shelf.
      if (!await _openToday()) {
        if (mounted) showSnack(context, 'Could not save the open article.');
        return;
      }
      if (mounted) {
        _backViews.clear();
        setState(() {
          primaryDestination = 2;
          mode = 'library';
        });
      }
    }
    try {
      if (!await workspace.deleteNote(ref.path)) {
        throw StateError('The article changed while it was being deleted');
      }
    } catch (error) {
      if (mounted) showSnack(context, 'Could not delete ${ref.title}: $error');
      return;
    }
    await workspace.refreshIndex(always: true);
    if (mounted) showSnack(context, 'Deleted ${ref.title}');
  }

  Future<void> _rateArticle(String path, String value) async {
    if (vault == null) return;
    try {
      final updated = await workspace.mutateNote(
        path,
        (source) => replaceNoteProperty(source, 'rating', value),
      );
      if (!updated) {
        if (mounted) {
          showSnack(context, 'Could not rate that article: the vault changed.');
        }
        return;
      }
    } on StateError catch (error) {
      if (mounted) {
        showSnack(context, 'Could not rate that article: ${error.message}');
      }
      return;
    } catch (error) {
      if (mounted) showSnack(context, 'Could not rate that article: $error');
      return;
    }
    final rated = index?.notesByPath[path];
    if (rated != null) {
      await _logReading(
        rated.title,
        rating: value,
        url: rated.properties['url'] as String?,
      );
    }
    if (value != 'shit' || !mounted) return;
    if (rated != null) await _deleteArticle(rated);
  }

  Future<void> _showSyncDashboard() async {
    // A conflict may have self-healed on disk since the last sync without
    // this screen's data being refreshed; catch it up before showing.
    await workspace.refreshSyncConflicts();
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => SyncDashboardScreen(
          load: _loadSyncDashboard,
          onSync: () => _syncNow(),
          onConfigure: _showSyncSettings,
          onResolve: _resolveSyncConflict,
          onResolveAll: _resolveAllSyncConflicts,
          onCopyDiagnostics: _copySyncDiagnostics,
        ),
      ),
    );
  }

  Future<SyncDashboardData> _loadSyncDashboard() async {
    final v = vault;
    if (v == null) {
      final active = _activeRegistryEntry;
      final error = syncError ?? (status == 'Opening vault...' ? null : status);
      return SyncDashboardData(
        storageName: active?.name ?? 'Vault not open',
        storageLocation: vaultEntryLocation(active) ?? '',
        cloud: active?.cloud ?? cloud,
        syncing: syncing,
        stage: syncStage == null ? null : syncStageLabel(syncStage!),
        error: error,
        result: lastSync,
        lastSyncAt: lastSyncAt,
        vaultOpen: false,
        desktopManaged: false,
        storageHealthy: false,
        conflicts: const [],
        events: const [],
      );
    }
    const tracePath = '.tylog/sync_trace.jsonl';
    final events = <Map<String, Object?>>[];
    final local = await deviceLocalStorage(v.storage);
    if (await local.exists(tracePath)) {
      for (final line in (await local.readText(tracePath)).split('\n')) {
        if (line.trim().isEmpty) continue;
        try {
          events.add((jsonDecode(line) as Map).cast<String, Object?>());
        } catch (_) {}
      }
    }
    final entry = vaultRegistry!.active;
    final healthy = storageHealthy ?? await workspace.probeStorage();
    return SyncDashboardData(
      storageName: entry.name,
      storageLocation: switch (entry.storageKind) {
        'android-tree' => entry.treeUri ?? entry.name,
        'app-local' => 'App storage',
        _ => entry.path,
      },
      backupPath: await _existingBackup(entry.backupPath),
      cloud: cloud,
      syncing: syncing,
      stage: syncStage == null ? null : syncStageLabel(syncStage!),
      error: syncError,
      result: lastSync,
      lastSyncAt: lastSyncAt,
      vaultOpen: true,
      desktopManaged:
          _localVaultDirectory != null &&
          isNextcloudManagedVault(_localVaultDirectory!),
      storageHealthy: healthy,
      conflicts: syncConflicts,
      events: events.reversed.toList(),
    );
  }

  Future<void> _resolveAllSyncConflicts(
    SyncConflictResolution resolution,
  ) async {
    final pending = workspace.syncConflicts.length;
    if (pending == 0) return;
    final keepingLocal = resolution == SyncConflictResolution.keepLocal;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Resolve $pending conflicts?',
      message: keepingLocal
          ? "This uploads this device's copy of $pending files, replacing what "
                'is on Nextcloud. Anything the other side added to them is lost.'
          : 'This overwrites this device\'s copy of $pending files with what '
                'is on Nextcloud. Anything you changed here is lost.',
      confirmLabel: 'Resolve $pending',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final resolved = await workspace.resolveAllConflicts(resolution);
    if (!mounted) return;
    final left = workspace.syncConflicts.length;
    showSnack(
      context,
      left == 0
          ? 'Resolved $resolved conflicts'
          : 'Resolved $resolved; $left still need review',
    );
  }

  Future<void> _resolveSyncConflict(SyncConflict conflict) async {
    final v = vault;
    final cfg = cloud;
    if (v == null || cfg == null || !cfg.isReady) return;
    if (note == conflict.path && dirty && !await _save(syncAfter: false)) {
      if (mounted) showSnack(context, 'Could not save the open note.');
      return;
    }
    final localBytes = await v.storage.exists(conflict.path)
        ? await v.storage.readBytes(conflict.path)
        : null;
    // The record decides whether a remote side exists at all; the snapshot of a
    // deleted remote must never be presented as "the Nextcloud version".
    final remoteBytes = conflictRemoteBytesToShow(
      conflict,
      conflict.remoteSnapshot == null
          ? null
          : await v.storage.readBytes(conflict.remoteSnapshot!),
    );
    final localText = conflict.isText && localBytes != null
        ? utf8.decode(localBytes, allowMalformed: true)
        : null;
    final remoteText = conflict.isText && remoteBytes != null
        ? utf8.decode(remoteBytes, allowMalformed: true)
        : null;
    if (!mounted) return;
    final shape = conflictShape(local: localText, remote: remoteText);
    // Null preselects nothing, forcing an explicit choice wherever a default
    // could discard the other side. See defaultResolution.
    final selected = ValueNotifier<SyncConflictResolution?>(
      defaultResolution(shape),
    );
    final merged = TextEditingController(text: localText ?? '');
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Resolve sync conflict'),
            leading: IconButton(
              tooltip: 'Cancel',
              onPressed: () => Navigator.pop(context, false),
              icon: const Icon(AppIcons.close),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.all(kSpace16),
            children: [
              Text(
                conflict.path,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: kSpace8),
              if (conflictShapeHint(shape) case final hint?) ...[
                Text(hint, style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: kSpace8),
              ],
              ValueListenableBuilder<SyncConflictResolution?>(
                valueListenable: selected,
                builder: (context, value, _) =>
                    RadioGroup<SyncConflictResolution>(
                      groupValue: value,
                      onChanged: (next) {
                        if (next == null) return;
                        selected.value = next;
                        if (next == SyncConflictResolution.keepLocal &&
                            localText != null) {
                          merged.text = localText;
                        } else if (next == SyncConflictResolution.keepRemote &&
                            remoteText != null) {
                          merged.text = remoteText;
                        }
                      },
                      child: Column(
                        children: [
                          RadioListTile<SyncConflictResolution>(
                            value: SyncConflictResolution.keepLocal,
                            title: Text(
                              localBytes != null
                                  ? 'Keep this device version'
                                  : 'Keep deletion from this device',
                            ),
                            subtitle: Text(
                              conflictSideLabel(
                                shape,
                                isLocal: true,
                                text: localText,
                                byteLength: localBytes?.length,
                              ),
                            ),
                          ),
                          RadioListTile<SyncConflictResolution>(
                            value: SyncConflictResolution.keepRemote,
                            title: Text(
                              conflict.remoteExists
                                  ? 'Keep Nextcloud version'
                                  : 'Keep deletion from Nextcloud',
                            ),
                            subtitle: Text(
                              conflictSideLabel(
                                shape,
                                isLocal: false,
                                text: remoteText,
                                byteLength: remoteBytes?.length,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
              ),
              if (localText != null && remoteText != null) ...[
                const SizedBox(height: kSpace16),
                Text(
                  'Final version',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: kSpace8),
                TextField(
                  controller: merged,
                  minLines: 12,
                  maxLines: null,
                  style: const TextStyle(fontFamily: 'monospace'),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) =>
                      selected.value = SyncConflictResolution.merge,
                ),
              ],
            ],
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(kSpace12),
              child: ValueListenableBuilder<SyncConflictResolution?>(
                valueListenable: selected,
                builder: (context, value, _) => FilledButton.icon(
                  // Disabled until a side is chosen: with nothing preselected
                  // there is no safe action to take on the user's behalf.
                  onPressed: value == null
                      ? null
                      : () => Navigator.pop(context, true),
                  icon: const Icon(Icons.check),
                  label: Text(
                    value == null
                        ? 'Choose a version to keep'
                        : 'Save resolution',
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final resolution = selected.value;
    if (save == true && resolution != null) {
      try {
        await workspace.resolveConflict(
          conflict,
          resolution,
          mergedText: resolution == SyncConflictResolution.merge
              ? merged.text
              : null,
        );
      } catch (error) {
        if (mounted) setState(() => syncError = friendlySyncError(error));
      }
    }
  }

  Future<void> _copySyncDiagnostics() async {
    final v = vault;
    if (v == null) return;
    const path = '.tylog/sync_trace.jsonl';
    final local = await deviceLocalStorage(v.storage);
    final trace = await local.exists(path)
        ? await local.readText(path)
        : 'No sync trace is available.\n';
    // A hung run never finishes, so the trace file is never written for it;
    // surface the live state up front so a stuck sync is still diagnosable.
    final state =
        'state: syncing=$syncing stage=${syncStage ?? '-'} '
        'lastSyncAt=${lastSyncAt ?? '-'}\n\n';
    await Clipboard.setData(
      ClipboardData(
        text:
            'TyLog ${await appVersion()}\n'
            'Platform: ${Platform.operatingSystem}\n'
            '$state$trace',
      ),
    );
    if (!mounted) return;
    showSnack(context, 'Sync diagnostics copied');
  }

  Future<String?> _askText(String title, {String? initialValue}) async {
    final input = TextEditingController(text: initialValue);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: _dialogField(
          input,
          label: title,
          autofocus: true,
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, input.text),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    return value?.trim();
  }

  String _selectedText() {
    if (mode == 'normal') return richController.selectedPlainText;
    final editor = sourceController;
    final selection = editor.selection;
    if (!selection.isValid || selection.isCollapsed) return '';
    return editor.text.substring(selection.start, selection.end);
  }

  void _applyMagic(MagicRequest request) {
    if (mode == 'normal') {
      richController.applyMagic(request);
      return;
    }
    final editor = sourceController;
    final edit = applyMagicEdit(editor.text, editor.selection, request);
    editor.value = TextEditingValue(text: edit.text, selection: edit.selection);
    _queueAutosave();
  }

  Future<NoteRef?> _chooseNote({
    String? kind,
    bool create = false,
    String? heading,
  }) async {
    final notes =
        await _pagedPickerNotes(kind: kind) ??
        (index?.notes ?? const <NoteRef>[])
            .where((note) => kind == null || note.kind == kind)
            .toList();
    if (!mounted) return null;
    final chosen = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: false,
      builder: (context) => NotePickerSheet(
        notes: notes,
        heading: heading,
        createLabel: create ? 'Create ${kind ?? 'note'}' : null,
      ),
    );
    if (chosen is NoteRef) return chosen;
    if (chosen != NotePickerSheet.createSentinel) return null;
    final title = await _askText(
      'New ${kind ?? 'note'}',
      initialValue: _selectedText(),
    );
    if (title == null || title.isEmpty || vault == null) return null;
    final file = await workspace.createPage(title, kind: kind ?? 'note');
    unawaited(workspace.refreshIndex(always: true));
    return scanNote(file, await workspace.readNote(file));
  }

  List<NoteRef> get _entities =>
      (index?.notes ?? const <NoteRef>[])
          .where((item) => !structuralNoteKinds.contains(item.kind))
          .toList()
        ..sort((a, b) => a.title.compareTo(b.title));

  Future<NoteRef?> _chooseEntity() async {
    final paged = await _pagedPickerNotes();
    if (!mounted) return null;
    final chosen = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: false,
      builder: (context) => NotePickerSheet(
        notes: paged ?? _entities,
        createLabel: 'New entity',
        subtitleFor: (note) => note.kind,
      ),
    );
    if (chosen is NoteRef) return chosen;
    return chosen == NotePickerSheet.createSentinel ? _createEntity() : null;
  }

  /// Reads picker candidates in bounded pages when the SQLite projection is
  /// complete. An incomplete projection falls back to the live index so a
  /// background scan never makes a picker appear empty.
  /// The move-to-app-storage backup, or null once the user deleted it (the
  /// sync screen kept showing a folder that no longer existed).
  Future<String?> _existingBackup(String? location) async {
    if (location == null) return null;
    try {
      final exists = location.startsWith('content://')
          ? (await AndroidTreeVaultStorage(
              uri: location,
              name: '',
            ).list()).isNotEmpty
          : await Directory(location).exists();
      return exists ? friendlyVaultPath(location) : null;
    } catch (_) {
      return null;
    }
  }

  Future<List<NoteRef>?> _pagedPickerNotes({String? kind}) async {
    final activeEntry = workspace.entry;
    if (activeEntry == null) return null;
    try {
      final db = await _databaseForVault(activeEntry);
      if (db == null || !await db.nodeProjectionComplete()) return null;
      final notes = <NoteRef>[];
      String? cursor;
      do {
        final page = await db.pageNodeSummaries(afterId: cursor, type: kind);
        for (final summary in page.nodes) {
          final attributes = jsonDecode(summary.attributesJson);
          if (attributes is! Map) continue;
          final json = attributes.cast<String, Object?>()
            ..['id'] = summary.id
            ..['title'] = summary.title
            ..['kind'] = summary.type;
          if (json['deletedAtMs'] != null || json['path'] is! String) {
            continue;
          }
          notes.add(NoteRef.fromJson(json));
        }
        cursor = page.nextCursor;
      } while (cursor != null);
      return notes;
    } catch (_) {
      return null;
    }
  }

  @visibleForTesting
  Future<NoteRef?> createEntityForTesting() => _createEntity();

  @visibleForTesting
  Future<void> saveLinksAsArticlesForTesting() => _saveLinksAsArticles();

  @visibleForTesting
  Future<int> relinkArticlesForTesting() => _relinkArticles(vault!);

  Future<NoteRef?> _createEntity({
    String? initialName,
    String? initialKind,
  }) async {
    final title = TextEditingController(text: initialName);
    final kindField = TextEditingController(text: initialKind);
    final aliases = TextEditingController();
    final fieldControllers = <String, TextEditingController>{
      'email': TextEditingController(),
      'address': TextEditingController(),
      'link': TextEditingController(),
    };
    var kindListenerAttached = false;
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          if (!kindListenerAttached) {
            kindListenerAttached = true;
            kindField.addListener(() => setDialogState(() {}));
          }
          final fields = entityFieldsForKind(kindField.text);
          return AlertDialog(
            title: const Text('New entity'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _dialogField(title, label: 'Name', autofocus: true),
                const SizedBox(height: kSpace12),
                DropdownMenu<String>(
                  key: const ValueKey('entity-kind'),
                  expandedInsets: EdgeInsets.zero,
                  controller: kindField,
                  label: const Text('Kind'),
                  requestFocusOnTap: true,
                  enableFilter: true,
                  dropdownMenuEntries:
                      entityKindChoices(
                            index?.notes.map((n) => n.kind) ?? const <String>[],
                          )
                          .map(
                            (value) =>
                                DropdownMenuEntry(value: value, label: value),
                          )
                          .toList(),
                ),
                const SizedBox(height: kSpace12),
                _dialogField(aliases, label: 'Aliases, comma-separated'),
                const SizedBox(height: kSpace12),
                for (final field in fields)
                  KeyedSubtree(
                    key: ValueKey('entity-field-$field'),
                    child: Padding(
                      padding: EdgeInsets.only(
                        bottom: field == fields.last ? 0 : kSpace12,
                      ),
                      child: _dialogField(
                        fieldControllers[field]!,
                        label: switch (field) {
                          'email' => 'Email (optional)',
                          'address' => 'Address (optional)',
                          _ => 'Link or map URL (optional)',
                        },
                        keyboardType: field == 'email'
                            ? TextInputType.emailAddress
                            : field == 'link'
                            ? TextInputType.url
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Create'),
              ),
            ],
          );
        },
      ),
    );
    final name = title.text.trim();
    final entityKind = kindField.text.trim();
    final v = vault;
    if (save != true || name.isEmpty || entityKind.isEmpty || v == null) {
      return null;
    }
    final file = await workspace.createPage(name);
    final source = await workspace.readNote(file);
    final created = scanNote(file, source);
    final updated = replaceNoteHeader(
      source,
      NoteMetadataDraft(
        id: created.id,
        title: created.title,
        kind: entityKind,
        tags: created.tags,
        aliases: _csvValues(aliases.text),
        properties: {
          ...created.properties,
          for (final field in entityFieldsForKind(entityKind))
            if (fieldControllers[field]!.text.trim().isNotEmpty)
              field: fieldControllers[field]!.text.trim(),
        },
      ),
    );
    if (!await workspace.mutateNote(file, (_) => updated)) {
      return null;
    }
    unawaited(workspace.refreshIndex(always: true));
    return scanNote(file, updated);
  }

  Future<void> _runMagic(MagicAction action) async {
    switch (action) {
      case MagicAction.bold:
      case MagicAction.italic:
      case MagicAction.heading:
      case MagicAction.strike:
      case MagicAction.underline:
      case MagicAction.mono:
        _applyMagic(MagicRequest(action: action));
        return;
      case MagicAction.highlight:
        // The four highlight colours used to be reachable only by long-
        // pressing the toolbar button, which tooltips advertise but Android
        // has no way to discover. Surface them explicitly here instead.
        final chosen = await showModalBottomSheet<String>(
          context: context,
          showDragHandle: false,
          builder: (context) => AppSheet(
            title: 'Highlight',
            children: [
              for (final (fill, label) in kHighlightChoices)
                ListTile(
                  leading: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: highlightSwatchColor(fill),
                      borderRadius: BorderRadius.circular(kRadiusSmall),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                  title: Text(label),
                  onTap: () => Navigator.pop(context, fill),
                ),
            ],
          ),
        );
        if (!mounted) return;
        if (chosen == null) return;
        _applyMagic(MagicRequest(action: MagicAction.highlight, value: chosen));
        return;
      case MagicAction.equation:
        final selected = _selectedText();
        final value = selected.isEmpty ? await _askText('Equation') : selected;
        if (value == null || value.isEmpty) return;
        _applyMagic(MagicRequest(action: action, value: value));
        return;
      case MagicAction.table:
        final size = await _askTableSize();
        if (size == null) return;
        _applyMagic(
          MagicRequest(
            action: MagicAction.table,
            rows: size.$1,
            columns: size.$2,
          ),
        );
        return;
      case MagicAction.noteLink:
        final target = await _chooseNote(create: true);
        if (target != null) {
          _applyMagic(
            MagicRequest(action: action, id: target.id, value: target.title),
          );
        }
        return;
      case MagicAction.mention:
        final target = await _chooseEntity();
        if (target != null) {
          _applyMagic(
            MagicRequest(action: action, id: target.id, value: target.title),
          );
        }
        return;
      case MagicAction.project:
        final target = await _chooseNote(kind: 'project', create: true);
        if (target == null) return;
        if (_selectedText().isNotEmpty) {
          _applyMagic(
            MagicRequest(action: action, id: target.id, value: target.title),
          );
        } else {
          final current = _currentNoteRef();
          if (current == null) return;
          _loadSource(
            replaceNoteHeader(
              _currentSource(),
              NoteMetadataDraft(
                id: current.id,
                title: current.title,
                kind: current.kind,
                project: target.id,
                date: current.date,
                tags: current.tags,
                aliases: current.aliases,
                properties: current.properties,
              ),
            ),
          );
          _queueAutosave();
        }
        return;
      case MagicAction.tag:
        final value = await _askText('Tag', initialValue: _selectedText());
        if (value != null && value.isNotEmpty) {
          _applyMagic(MagicRequest(action: action, value: value));
        }
        return;
      case MagicAction.task:
        final selected = _selectedText();
        if (selected.contains('\n')) {
          final lines = selected
              .split('\n')
              .map(
                (l) => l
                    .replaceFirst(RegExp(r'^(?:[•☐☑] |\d+\. |[-+] )'), '')
                    .trim(),
              )
              .where((l) => l.isNotEmpty)
              .toList();
          if (lines.length >= 2) {
            final reserved = <String>{};
            final tasks = <({String id, String text})>[];
            for (final line in lines) {
              final id = await vault!.nextTaskId(line, reserved: reserved);
              reserved.add(id);
              tasks.add((id: id, text: line));
            }
            if (mode == 'normal') {
              richController.insertTasks(tasks);
            } else {
              final snippets = tasks
                  .map((t) => taskSnippet(id: t.id, text: t.text))
                  .join('\n\n');
              final editor = sourceController;
              final selection = editor.selection;
              final start = selection.isValid
                  ? selection.start
                  : editor.text.length;
              final end = selection.isValid
                  ? selection.end
                  : editor.text.length;
              final before = editor.text.substring(0, start);
              final after = editor.text
                  .substring(end)
                  .replaceFirst(RegExp(r'^\n+'), '');
              final prefix = before.isEmpty
                  ? ''
                  : before.endsWith('\n\n')
                  ? ''
                  : before.endsWith('\n')
                  ? '\n'
                  : '\n\n';
              final inserted = '$prefix$snippets\n\n';
              editor.value = TextEditingValue(
                text: '$before$inserted$after',
                selection: TextSelection.collapsed(
                  offset: start + inserted.length,
                ),
              );
              _queueAutosave();
            }
            return;
          }
        }
        if (mode == 'normal') {
          await richController.createTaskLine();
        } else {
          final editor = sourceController;
          final caret = editor.selection.isValid
              ? editor.selection.extentOffset
              : editor.text.length;
          final start =
              editor.text.lastIndexOf(
                '\n',
                (caret - 1).clamp(0, editor.text.length),
              ) +
              1;
          final lineEnd = editor.text.indexOf('\n', caret);
          final end = lineEnd < 0 ? editor.text.length : lineEnd;
          final original = editor.text;
          final opened = vault!;
          final text = original.substring(start, end);
          final taskId = await vault!.nextTaskId(text);
          if (!mounted ||
              !identical(vault, opened) ||
              editor.text != original) {
            return;
          }
          final snippet = taskSnippet(id: taskId, text: text);
          editor.value = TextEditingValue(
            text: editor.text.replaceRange(start, end, snippet),
            selection: TextSelection.collapsed(offset: start + snippet.length),
          );
          _queueAutosave();
        }
        return;
      case MagicAction.time:
        _applyMagic(
          MagicRequest(action: action, value: localTime(DateTime.now())),
        );
        return;
      case MagicAction.date:
        final selected = _selectedText().replaceAll(RegExp(r'[^0-9-]'), '');
        final parsed = _parseMagicDate(selected);
        final date =
            parsed ??
            await showDatePicker(
              context: context,
              firstDate: DateTime(1900),
              lastDate: DateTime(2200),
              initialDate: DateTime.now(),
            );
        if (date != null) {
          _applyMagic(MagicRequest(action: action, value: isoDay(date)));
        }
        return;
      case MagicAction.citation:
        final key = await _chooseCitation();
        if (key != null) {
          _applyMagic(MagicRequest(action: action, value: key));
        }
        return;
      case MagicAction.attachment:
        await _insertAttachment();
        return;
      case MagicAction.audio:
        await _insertAudio();
        return;
      case MagicAction.report:
        await _createReport();
        return;
      case MagicAction.articles:
        await _saveLinksAsArticles();
        return;
    }
  }

  NoteRef? _currentNoteRef() {
    final v = vault;
    final file = note;
    if (v == null || file == null) return null;
    return index?.notesByPath[file];
  }

  DateTime? _parseMagicDate(String value) {
    if (RegExp(r'^\d{8}$').hasMatch(value)) {
      return DateTime(
        int.parse(value.substring(0, 4)),
        int.parse(value.substring(4, 6)),
        int.parse(value.substring(6, 8)),
      );
    }
    return DateTime.tryParse(value);
  }

  Future<(int, int)?> _askTableSize() async {
    final rows = TextEditingController(text: '2');
    final columns = TextEditingController(text: '2');
    String? error;
    final result = await showDialog<(int, int)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Table size'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _dialogField(
                      rows,
                      label: 'Rows',
                      autofocus: true,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: kSpace12),
                  Expanded(
                    child: _dialogField(
                      columns,
                      label: 'Columns',
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: kSpace8),
                  child: Text(error!),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final rowCount = int.tryParse(rows.text);
                final columnCount = int.tryParse(columns.text);
                if (rowCount == null ||
                    columnCount == null ||
                    rowCount < 1 ||
                    rowCount > 10 ||
                    columnCount < 1 ||
                    columnCount > 10) {
                  setDialogState(() => error = 'Use 1–10');
                  return;
                }
                Navigator.pop(context, (rowCount, columnCount));
              },
              child: const Text('Insert'),
            ),
          ],
        ),
      ),
    );
    return result;
  }

  void _magicFeedback(String message) {
    if (!mounted) return;
    showSnack(context, message);
  }

  /// Compiles the open note to PDF and hands it to the platform share sheet.
  ///
  /// Shares bytes rather than a path on purpose: on Android the vault lives
  /// behind SAF, so the note has no filesystem path to give anyone, and the
  /// exported PDF should not have to be written into the vault just to leave the
  /// app — reports already do that and land in `outputs/`, where a SAF user
  /// cannot easily reach them.
  ///
  /// Compiles the *preview* source and file map, so what gets shared is exactly
  /// what Preview renders, bibliography and all.
  Future<void> _sharePdf() async {
    final exportVault = vault;
    final exportPath = note;
    if (exportVault == null || exportPath == null) {
      _magicFeedback('Open a note first');
      return;
    }
    // A dirty buffer would otherwise share the last-saved bytes.
    if (dirty && !await _save(syncAfter: false)) return;
    if (!mounted || vault != exportVault || note != exportPath) return;
    final exportSource = _previewSource();
    final exportRevision = _assetRevision + 1;
    _refreshNoteAssets(exportSource);
    try {
      await _assetLoadFuture!;
    } catch (error) {
      _magicFeedback('Could not load assets: $error');
      return;
    }
    if (!mounted ||
        vault != exportVault ||
        note != exportPath ||
        _assetRevision != exportRevision ||
        _previewSource() != exportSource) {
      _magicFeedback('Note changed before PDF export');
      return;
    }
    final exportFiles = _typstFiles();
    _magicFeedback('Building PDF…');
    final Uint8List pdf;
    try {
      pdf = await (widget.onCompilePdf ?? compileSourcePdf)(
        source: exportSource,
        files: exportFiles,
        paper: vaultRegistry?.pdfPaper ?? 'a4',
      );
    } catch (error) {
      if (!mounted) return;
      // Same escape hatch the preview offers, since the cause is the same: the
      // note does not compile.
      unawaited(_showTypstHelp(error: error.toString()));
      return;
    }
    if (!mounted ||
        vault != exportVault ||
        note != exportPath ||
        _previewSource() != exportSource) {
      _magicFeedback('Note changed before PDF export');
      return;
    }
    final name = exportPath.split('/').last.replaceFirst(RegExp(r'\.typ$'), '');
    await (widget.onSharePdf ?? _sharePdfBytes)(name, pdf);
  }

  Future<void> _sharePdfBytes(String name, Uint8List pdf) async {
    // iPad and macOS anchor the share popover to a rect; without one they throw
    // or place it arbitrarily.
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            pdf,
            mimeType: 'application/pdf',
            name: '$name.pdf',
            length: pdf.length,
          ),
        ],
        fileNameOverrides: ['$name.pdf'],
        subject: name,
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  Future<void> _shareGraphSvg(NoteGraph graph) async {
    final positions = forceLayoutPositions(graph, const Size(1000, 1000));
    final svg = graphToSvg(
      nodes: [
        for (final node in graph.nodes)
          if (positions[node.path] case final point?)
            SvgGraphNode(
              id: node.path,
              label: node.title,
              x: point.dx,
              y: point.dy,
            ),
      ],
      edges: [
        for (final edge in graph.edges)
          SvgGraphEdge(from: edge.from, to: edge.to),
      ],
    );
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            Uint8List.fromList(utf8.encode(svg)),
            mimeType: 'image/svg+xml',
            name: 'tylog-graph.svg',
          ),
        ],
        fileNameOverrides: const ['tylog-graph.svg'],
        subject: 'TyLog graph',
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  Future<String?> _chooseCitation() async {
    final v = vault;
    if (v == null) return null;
    final hasYml = await v.storage.exists(Vault.bibliographyPath);
    final hasZotero = await v.storage.exists(Vault.zoteroBibPath);
    if (!hasYml && !hasZotero) {
      _magicFeedback('No bibliography entries');
      return null;
    }
    final entries = <HayagrivaEntry>[];
    if (hasYml) {
      final bib = await v.storage.readText(Vault.bibliographyPath);
      bibliographySource = bib;
      entries.addAll(parseHayagrivaBibliography(bib));
    }
    if (hasZotero) {
      final bib = await v.storage.readText(Vault.zoteroBibPath);
      zoteroBibSource = bib;
      entries.addAll(parseBibtexBibliography(bib));
    }
    if (!mounted) return null;
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: false,
      isScrollControlled: true,
      builder: (context) {
        var query = '';
        return AppSheet.body(
          title: 'Citations',
          child: StatefulBuilder(
            builder: (context, setSheetState) {
              final q = query.trim().toLowerCase();
              final filtered = q.isEmpty
                  ? entries
                  : entries
                        .where(
                          (entry) =>
                              entry.title.toLowerCase().contains(q) ||
                              entry.key.toLowerCase().contains(q) ||
                              (entry.author ?? '').toLowerCase().contains(q),
                        )
                        .toList();
              return Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        kSpace16,
                        0,
                        kSpace16,
                        kSpace8,
                      ),
                      child: TextField(
                        key: const Key('citation-search'),
                        autofocus: entries.length > 8,
                        onChanged: (value) =>
                            setSheetState(() => query = value),
                        decoration: const InputDecoration(
                          isDense: true,
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Search citations',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          if (filtered.isEmpty)
                            const ListTile(
                              title: Text('No bibliography entries'),
                            ),
                          for (final entry in filtered)
                            ListTile(
                              leading: const Icon(Icons.format_quote),
                              title: Text(entry.title),
                              subtitle: Text(
                                '${entry.key} · '
                                '${entry.author ?? entry.type}'
                                '${entry.year == null ? '' : ' ${entry.year}'}'
                                '${entry.source == 'zotero' ? ' · Zotero' : ''}',
                              ),
                              onTap: () => Navigator.pop(context, entry.key),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _insertAttachment() async {
    if (vault == null) return;
    final picked = await FilePicker.pickFiles();
    final sourcePath = picked?.files.single.path;
    if (sourcePath == null) return;
    await _attachFile(File(sourcePath));
  }

  Future<void> _attachFile(File source) async {
    final v = vault;
    if (v == null) return;
    final base = source.path.split(Platform.pathSeparator).last;
    var target = 'assets/$base';
    var suffix = 2;
    while (_pendingAttach.containsKey(target) ||
        await v.storage.existsNow(target)) {
      final dot = base.lastIndexOf('.');
      final stem = dot < 0 ? base : base.substring(0, dot);
      final extension = dot < 0 ? '' : base.substring(dot);
      target = 'assets/$stem-${suffix++}$extension';
    }
    const imageExtensions = {'.png', '.jpg', '.jpeg', '.gif', '.svg', '.webp'};
    final lower = target.toLowerCase();
    final image = imageExtensions.any(lower.endsWith);
    // Chip first, copy after: the SAF write can queue behind the index for
    // minutes, and the user must see the attachment land at once.
    _pendingAttach[target] = source;
    _applyMagic(
      MagicRequest(
        action: MagicAction.attachment,
        value: '/$target',
        kind: image
            ? 'image'
            : isAudioPath(lower)
            ? 'audio'
            : 'file',
      ),
    );
    _trackSave(base, target, importPlatformFile(v.storage, target, source));
  }

  Future<void> _createReport() async {
    final v = vault;
    final ix = index;
    if (v == null || ix == null) return;
    final title = await _askText('Report title');
    if (title == null || title.isEmpty) return;
    final project = await _chooseNote(
      kind: 'project',
      heading: 'Project filter (optional)',
    );
    if (!mounted) return;
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
      helpText: 'Date range (optional)',
    );
    final report = await writeReportStorage(
      v.storage,
      title,
      ix,
      includeZotero: await v.storage.exists(Vault.zoteroBibPath),
      ReportFilter(
        project: project?.id,
        from: range == null ? null : isoDay(range.start),
        to: range == null ? null : isoDay(range.end),
      ),
    );
    final export = await exportReportPdfStorage(
      v.storage,
      report,
      paper: vaultRegistry?.pdfPaper ?? 'a4',
    );
    if (mounted) {
      _magicFeedback('Created report and PDF');
      _queueCloudSync();
      // The PDF is already in outputs/; the share sheet is the natural
      // completion of "create a report", and dismissing it costs nothing.
      final name = export.path.split('/').last.replaceFirst('.pdf', '');
      await _sharePdfBytes(name, export.bytes);
    }
  }

  Future<void> _showMagicMenu() async {
    try {
      final action = await showModalBottomSheet<MagicAction>(
        context: context,
        showDragHandle: false,
        isScrollControlled: true,
        builder: (context) {
          final columns = MediaQuery.sizeOf(context).width < 500 ? 3 : 4;
          return AppSheet.body(
            title: 'Add to note',
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.8,
              child: CustomScrollView(
                slivers: [
                  for (final group in kMagicActionGroups.entries) ...[
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                        kSpace16,
                        kSpace16,
                        kSpace16,
                        kSpace8,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: Text(
                          group.key,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                    ),
                    SliverGrid.count(
                      crossAxisCount: columns,
                      children: group.value.map((action) {
                        final display = kMagicActionDisplay[action]!;
                        return InkWell(
                          onTap: () => Navigator.pop(context, action),
                          child: Semantics(
                            button: true,
                            label: display.$2,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (action == MagicAction.heading)
                                  Text(
                                    'H1',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleLarge,
                                  )
                                else
                                  Icon(display.$1),
                                const SizedBox(height: 6),
                                Text(display.$2, textAlign: TextAlign.center),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      );
      if (action != null) {
        try {
          await _runMagic(action);
        } catch (error) {
          _magicFeedback('Magic failed: $error');
        }
      }
    } finally {
      if (mounted && (mode == 'source' || mode == 'split')) {
        sourceEditorKey.currentState?.requestFocus();
      }
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
                  tile(_ShellAction.sharePdf, Icons.ios_share, 'Share as PDF'),
                ],
              ),
            AppSection(
              title: 'Views',
              children: [tile(_ShellAction.graph, AppIcons.graph, 'Graph')],
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
      case _ShellAction.sharePdf:
        await _sharePdf();
      case _ShellAction.settings:
        _showSettings();
    }
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
        return ScreenshotView(
          note: currentNote!,
          source: _currentSource(),
          imageResolver: _readAsset,
          onEdit: () => setState(() => _editScreenshot = true),
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
        onShelfPrefsChanged: (prefs) =>
            unawaited(vaultRegistry?.updateShelfPrefs(prefs) ?? Future.value()),
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
        communities: communities,
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
              ),
            ),
            if (stacked)
              const Divider(height: 1)
            else
              const VerticalDivider(width: 1),
            Expanded(
              child: LayoutBuilder(
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
        ScreenshotView(
          note: currentNote!,
          source: _currentSource(),
          imageResolver: _readAsset,
          onEdit: () => setState(() => _editScreenshot = true),
        ),
      'normal' when _usePlainLongEditor => VirtualPlainEditor(
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
          final matchedNotes = _mentionQueryCache.query(
            index,
            q,
            recency,
            excludedIds: eventIds,
            revision: workspace.indexRevision,
          );
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
          // Logseq lets `[[X]]` name a page that has no file yet. Without this
          // row a page that does not exist is simply unreachable from the
          // editor and the user has to accept whichever near-miss ranked
          // first. Selecting it emits an ordinary ref-note to the typed title,
          // which renders as the existing tappable "unresolved" chip — tapping
          // that runs _createFromLink, and until then the link shows up in the
          // broken-link triage like any other missing page.
          final typed = query.trim();
          if (typed.isNotEmpty &&
              !suggestions.any(
                (s) => s.title.toLowerCase() == typed.toLowerCase(),
              )) {
            suggestions.add(
              MentionSuggestion(
                id: typed,
                title: typed,
                subtitle: 'New page — not created yet',
                create: true,
              ),
            );
          }
          return suggestions;
        },
        onCommandSelected: _runMagic,
        onCreateNote: (title) {
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
              final file = await workspace.createPage(title, id: id);
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
    Widget documentContent = content;
    if (mode == 'normal' &&
        currentNote != null &&
        (isEntity || backlinks.isNotEmpty)) {
      final v = vault;
      documentContent = Column(
        children: [
          if (isEntity)
            EntityHeader(
              note: currentNote,
              imageResolver: _readAsset,
              onOpenUrl: _openUrl,
            ),
          Expanded(child: content),
          if (backlinks.isNotEmpty && v != null)
            LinkedReferences(
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
            ),
        ],
      );
    }
    final enrichDay = _enrichDecisions;
    if (mode == 'normal' &&
        enrichDay != null &&
        enrichDay.$1 == current &&
        (enrichDay.$2.decisions.isNotEmpty ||
            enrichDay.$2.tags.isNotEmpty ||
            enrichDay.$2.markers.isNotEmpty)) {
      documentContent = Column(
        children: [
          Expanded(child: documentContent),
          EnrichReview(
            decisions: enrichDay.$2.decisions,
            tags: enrichDay.$2.tags,
            markers: enrichDay.$2.markers,
            onAcceptMarker: (offer) =>
                unawaited(_enrichOnce(() => _acceptEnrichMarker(offer))),
            onRejectMarker: (offer) =>
                unawaited(_enrichOnce(() => _rejectEnrichMarker(offer))),
            onRejectTag: (tag) =>
                unawaited(_enrichOnce(() => _rejectEnrichTag(tag))),
            onAccept: (mention, target) =>
                unawaited(_enrichOnce(() => _acceptEnrich(mention, target))),
            onReject: (mention, target) =>
                unawaited(_enrichOnce(() => _rejectEnrich(mention, target))),
            onCreate: (mention) =>
                unawaited(_enrichOnce(() => _createFromEnrich(mention))),
          ),
        ],
      );
    }
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
          ScreenshotStrip(
            index: index,
            day: isoDay(currentDaily),
            onOpenPath: _openPath,
            imageResolver: _readAsset,
          ),
          Expanded(child: documentContent),
        ],
      );
    }
    final bodyContent = isTodayDocument
        ? PageStorage(
            bucket: _todayStorage,
            child: TodayPage(
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
                    kind: CalendarItemKind.dateRef,
                    title: event.title,
                    notePath: event.path,
                  ),
              ],
              tasks: index?.tasks ?? const [],
              notes: index?.notesByPath ?? const {},
              onAllTasks: () => unawaited(_selectDestination(2, libraryTab: 3)),
              recent: _recentNotes(),
              editor: documentContent,
              onOpenPath: _openPath,
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
        final failed = openFailed || saveFailed;
        final banner = failed
            ? appBanner(
                key: const ValueKey('status-error'),
                backgroundColor: Theme.of(context).colorScheme.errorContainer,
                content: Text(
                  saveFailed
                      ? 'Could not save your note. Your edits are still here.'
                      : status,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () =>
                        saveFailed ? unawaited(_save()) : unawaited(_open()),
                    child: Text(saveFailed ? 'Retry Save' : 'Retry'),
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
            : (syncing && syncStage != null)
            ? statusPill(
                key: const ValueKey('status-stage'),
                child: Text(
                  syncStageLabel(syncStage!),
                  style: Theme.of(context).textTheme.bodySmall,
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
    final typing = MediaQuery.viewInsetsOf(context).bottom > 0;
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
              ? CompactDateTitle(day: currentDaily ?? DateTime.now())
              : mode == 'library'
              ? const Text('Library')
              : mode == 'graph'
              ? const Text('Graph')
              : documentModes.contains(mode) && currentDaily != null
              // The date alone (no day arrows): it opens the calendar.
              ? Tooltip(
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
                          builder: (context, dirty, _) =>
                              CompactDateTitle(day: currentDaily, dirty: dirty),
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
                  PopupMenuItem(
                    value: 'conceptMap',
                    child: Text('Concept map'),
                  ),
                  PopupMenuItem(value: 'local', child: Text('Focused')),
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
