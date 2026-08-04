import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:typst_flutter/typst_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'bibliography.dart';
import 'controlled_editor.dart';
import 'graph.dart';
import 'knowledge_screen.dart';
import 'saved_searches.dart';
import 'markdown_article_import.dart';
import 'models.dart';
import 'month_calendar.dart';
import 'nextcloud_sync.dart';
import 'pkms_registry.dart';
import 'platform_file_actions.dart';
import 'report.dart';
import 'rich_editor.dart';
import 'scanner.dart';
import 'search_index.dart';
import 'task_scheduler.dart';
import 'vault.dart';
import 'vault_registry.dart';
import 'vault_storage.dart';
import 'voronoi_view.dart';
import 'widgets/app_version.dart';
import 'widgets/constants.dart';
import 'widgets/date_format.dart';
import 'widgets/entity_header.dart';
import 'widgets/linked_references.dart';
import 'widgets/dialogs.dart';
import 'widgets/editor_panel.dart';
import 'widgets/journal_feed.dart';
import 'widgets/links_panel.dart';
import 'widgets/loading.dart';
import 'widgets/reading_mode.dart';
import 'widgets/settings_sheet.dart';
import 'widgets/snack.dart';
import 'desktop_updater.dart' as updater;
import 'widgets/sync_dashboard.dart';
import 'widgets/sync_status.dart';
import 'widgets/vaults_sheet.dart';
import 'widgets/work_surface.dart';
import 'workspace_controller.dart';

export 'widgets/app_version.dart';
export 'widgets/date_format.dart';
export 'widgets/sync_status.dart';
export 'widgets/work_surface.dart'
    show TodayPage, continueReadingEligible, isTaskInTodayAgenda, isTaskOverdue;

part 'app_mobile/desktop_update_flow.dart';
part 'app_mobile/markdown_import_flow.dart';
part 'app_mobile/vault_import_flow.dart';
part 'app_mobile/vault_lifecycle.dart';

const _autoRelatedMarker = '// tylog:auto-related';

String stripAutoRelated(String source) {
  final marker = RegExp(
    '(?:^|\\n)${RegExp.escape(_autoRelatedMarker)}(?:\\r?\\n|\$)',
  ).firstMatch(source);
  if (marker == null) return source;
  return source
      .substring(0, marker.start)
      .replaceFirst(RegExp(r'[\r\n]+$'), '');
}

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
    final darkColorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0B2F44),
      brightness: Brightness.dark,
    );
    return MaterialApp(
      title: 'TyLog',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0B2F44),
          brightness: Brightness.light,
          surface: const Color(0xFFF8FAFC),
          onSurfaceVariant: const Color(0xFF3F414A),
        ),
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        hintColor: const Color(0xFF5F616A),
        inputDecorationTheme: const InputDecorationTheme(
          border: InputBorder.none,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: darkColorScheme,
        scaffoldBackgroundColor: darkColorScheme.surface,
        inputDecorationTheme: const InputDecorationTheme(
          border: InputBorder.none,
        ),
      ),
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
  });

  /// Current app-wide appearance and the callback to change it, both owned by
  /// [TyLogApp]. Optional so tests can mount HomeScreen without wiring theming.
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final sourceController = TextEditingController();
  final sourceEditorKey = GlobalKey<EditorState>();
  late final TyLogEditingController richController;
  late final WorkspaceController workspace;
  // Launch lands in the journal editor with today's file open.
  String mode = 'normal';
  // Graph overview mode: 'conceptMap' (default), 'local', or 'allFiles'.
  String _graphMode = 'conceptMap';
  // Concept/note path the local graph is rooted at when expanded from the map.
  String? _graphFocusPath;

  NoteGraph? _graphCache;
  ({int revision, String mode, String? focus, String? current})? _graphKey;

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
    final cached = _graphCache;
    if (cached != null && _graphKey == key) return cached;
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
    _graphCache = built;
    _graphKey = key;
    return built;
  }
  int primaryDestination = 0;
  String? selectedTag;
  VaultRegistry? vaultRegistry;
  final taskScheduler = TaskScheduler();
  Timer? _previewDebounceTimer;
  String? _debouncedPreviewSource;
  String? _pendingPreviewSource;
  // Path/date of the daily note last opened via _openToday(), so a resume
  // after midnight can detect the Today screen is showing a stale day.
  String? _todayNotePath;
  DateTime? _todayOpenedAt;
  // Last syncError/conflict count a snackbar fired for, so background sync
  // polling (which calls notifyListeners repeatedly while unchanged) doesn't
  // spam a snackbar per tick — only a genuinely new failure/conflict does.
  String? _lastSnackedSyncError;
  int _lastSnackedConflictCount = 0;

  Vault? get vault => workspace.vault;
  VaultIndex? get index => workspace.index;
  set index(VaultIndex? value) => workspace.index = value;
  String? get note => workspace.note;
  set note(String? value) => workspace.note = value;
  String get status => workspace.status;
  set status(String value) => workspace.status = value;
  bool get dirty => workspace.dirty;
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

  // setState is @protected; this shim lets the flow extensions in
  // app_mobile/*.dart trigger rebuilds without tripping the analyzer.
  void _rebuild(VoidCallback fn) => setState(fn);

  @override
  void initState() {
    super.initState();
    richController = TyLogEditingController(
      source: '',
      onSourceChanged: _acceptRichSource,
      onError: _richEditorError,
      onProtectedTap: (id) => unawaited(_tapProtected(id)),
      imageResolver: _readAsset,
      resolveKind: _resolveKind,
    );
    workspace = WorkspaceController(
      taskScheduler: taskScheduler,
      isComposing: () => richController.isComposing,
    )..addListener(_workspaceChanged);
    WidgetsBinding.instance.addObserver(this);
    _open();
    // One silent update check per launch on macOS (only prompts if newer).
    // Skipped under `flutter test`: it would hit GitHub and leave an unawaited
    // rootBundle/HTTP load pending past teardown, wedging the asset channel for
    // the next test (appVersion hangs).
    if (Platform.isMacOS &&
        !Platform.environment.containsKey('FLUTTER_TEST')) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(_checkForUpdates(silent: true)),
      );
    }
  }

  @override
  void dispose() {
    _previewDebounceTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    workspace
      ..removeListener(_workspaceChanged)
      ..dispose();
    richController.dispose();
    sourceController.dispose();
    super.dispose();
  }

  void _workspaceChanged() {
    if (!mounted) return;
    if (sourceController.text != workspace.source) {
      // A save/sync round-trip can hand back a cosmetically different but
      // semantically identical source — e.g. trailing blank lines left by an
      // exited list. Reloading the rich editor then would clobber its live
      // state, wiping the empty line the user just opened to type on. Only
      // reload on a genuine visible-content change.
      final changed =
          TyLogDocument.parse(workspace.source).visibleText !=
          TyLogDocument.parse(sourceController.text).visibleText;
      sourceController.text = workspace.source;
      if (changed) richController.loadSource(workspace.source);
    }
    _maybeSnackNewSyncTrouble();
    setState(() {});
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


  Future<void> _save({bool syncAfter = true}) async {
    if (_currentSource() != workspace.source) {
      workspace.source = _currentSource();
    }
    await workspace.save(syncAfter: syncAfter);
  }

  void _queueCloudSync() => workspace.queueCloudSync();

  void _startCloudPolling() => workspace.startCloudPolling();

  void _stopCloudPolling() => workspace.stopCloudPolling();

  bool get _editingRecently => workspace.editingRecently;

  void _queueAutosave() {
    workspace.edit(_currentSource());
  }

  String _currentSource() => sourceController.text;

  /// Vault-relative asset bytes for the open note, loaded by [_loadNoteAssets]
  /// so the synchronous [_typstFiles] can hand them to the Typst compiler.
  final Map<String, Uint8List> _noteAssetFiles = {};

  /// The `kind` of the note a `#tylog.ref-note("target")` points at, so its chip
  /// shows a person/place/project icon; null when the index or target is absent.
  String? _resolveKind(String target) {
    final ix = index;
    // The retained resolver, never a fresh one: this runs once per mention chip
    // per span rebuild, and constructing a LinkResolver is O(vault). It is built
    // wherever the index is published, so it is non-null whenever `ix` is.
    final resolved = workspace.linkResolver?.resolve(target);
    if (ix == null || resolved == null) return null;
    return resolved.status == LinkResolutionStatus.resolved
        ? ix.notesByPath[resolved.path]?.kind
        : null;
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
      return await v.storage.readBytes(path.replaceFirst(RegExp(r'^/+'), ''));
    } catch (_) {
      return null;
    }
  }

  /// Loads every `assets/...` image referenced by [source] into
  /// [_noteAssetFiles] (keyed with and without a leading slash) so `#image(...)`
  /// resolves at compile time. Async; triggers a rebuild when it finishes.
  Future<void> _loadNoteAssets(String source) async {
    _noteAssetFiles.clear();
    final v = vault;
    if (v == null) return;
    final paths = RegExp(
      r'"(/?assets/[^"]+\.(?:png|jpe?g|gif|svg|webp|bmp))"',
      caseSensitive: false,
    ).allMatches(source).map((m) => m.group(1)!).toSet();
    for (final path in paths) {
      final relative = path.replaceFirst(RegExp(r'^/+'), '');
      try {
        final bytes = await v.storage.readBytes(relative);
        _noteAssetFiles[relative] = bytes;
        _noteAssetFiles['/$relative'] = bytes;
      } catch (_) {
        // Missing asset: leave it out; the compiler reports file-not-found.
      }
    }
    if (mounted && _noteAssetFiles.isNotEmpty) setState(() {});
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
  String _debouncedPreview() {
    final live = _previewSource();
    if (_debouncedPreviewSource == null) {
      _debouncedPreviewSource = live;
      _pendingPreviewSource = live;
      return live;
    }
    if (live != _pendingPreviewSource) {
      _pendingPreviewSource = live;
      _previewDebounceTimer?.cancel();
      _previewDebounceTimer = Timer(const Duration(milliseconds: 400), () {
        if (!mounted) return;
        setState(() => _debouncedPreviewSource = live);
      });
    }
    return _debouncedPreviewSource!;
  }

  void _loadSource(String source) {
    sourceController.text = source;
    richController.loadSource(source);
    unawaited(_loadNoteAssets(source));
  }

  void _acceptRichSource(String source) {
    if (sourceController.text == source) return;
    sourceController.text = source;
    _queueAutosave();
  }

  void _richEditorError(Object error) {
    if (!mounted) return;
    setState(() => status = 'Edit kept safe: $error');
  }

  // Logseq behavior: tapping a date reference navigates to that day's journal
  // page; every other protected chip opens the raw Typst editor.
  Future<void> _tapProtected(String id) async {
    final source = richController.protectedSource(id).trim();
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
        setState(() => status = "Couldn't open ${link.group(1)}");
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
      final resolution =
          workspace.linkResolver?.resolve(target) ?? _resolveLink(target);
      switch (resolution.status) {
        case LinkResolutionStatus.resolved:
          await _openNote(resolution.path!);
        case LinkResolutionStatus.ambiguous:
          await _chooseLinkOwner(target, resolution.candidates);
        case LinkResolutionStatus.unresolved:
          await _createFromLink(target);
      }
      return;
    }
    await _editProtectedBlock(id);
  }

  Future<void> _createFromLink(String target) async {
    final v = vault;
    if (v == null) return;
    // The resolver lags behind a just-created note until the background
    // rescan lands (minutes on a big vault), so check the direct
    // title->file mapping before claiming the note doesn't exist. Same
    // sanitization as Vault.page.
    final direct =
        'notes/${target.trim().replaceAll(RegExp(r'[\\/]'), '-')}.typ';
    if (await v.storage.exists(direct)) {
      await _openNote(direct);
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
    final file = await v.page(target);
    // Open first — the refresh only serves future link resolution and can
    // block for minutes behind an in-flight full rebuild.
    await _openNote(file);
    setState(() => status = 'Created $file');
    unawaited(workspace.refreshIndex(always: true));
  }

  Future<void> _chooseLinkOwner(String target, List<String> candidates) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(title: Text('“$target” matches ${candidates.length} notes')),
            for (final path in candidates)
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(path),
                onTap: () => Navigator.pop(context, path),
              ),
          ],
        ),
      ),
    );
    if (choice != null) await _openNote(choice);
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

  Future<void> _openNote(String path) async {
    final v = vault;
    if (v == null) return;
    if (dirty) await _save();
    final source = await v.storage.readText(path);
    _loadSource(source);
    workspace.replaceNote(path, source);
    setState(() {
      mode = 'normal';
      status = 'Opened $path';
    });
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
  }

  Future<void> _openToday() async {
    final v = vault;
    if (v == null) return;
    final path = await v.todayNote();
    await _openNote(path);
    _todayNotePath = path;
    _todayOpenedAt = DateTime.now();
  }

  Future<void> _openDay(DateTime day) async {
    final v = vault;
    if (v == null) return;
    await _openNote(await v.dailyNote(day));
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
            padding: const EdgeInsets.all(12),
            child: MonthCalendar(
              index: index,
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
    final v = vault;
    if (v == null) return;
    final existing = _pathForLink(title);
    if (existing != null) {
      await _openNote(existing);
      return;
    }
    final file = await v.page(title);
    await _openNote(file);
    setState(() => status = 'Created $file');
    // Without the refresh the new note stays unresolvable to every chip
    // until the next unrelated scan; run it behind the navigation.
    unawaited(workspace.refreshIndex(always: true));
  }

  Future<void> _newPage({String kind = 'note'}) async {
    final v = vault;
    if (v == null) return;
    final title = await _askPageTitle();
    if (title == null || title.trim().isEmpty) return;
    final template = await _chooseTemplate(v);
    if (dirty) await _save();
    final file = await v.page(title, kind: kind, template: template);
    await workspace.refreshIndex(always: true);
    await _openNote(file);
    setState(() {
      status = 'Created $file';
    });
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
        content: TextField(
          controller: title,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Title'),
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
              TextField(
                controller: title,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              TextField(
                controller: tagsText,
                decoration: const InputDecoration(
                  labelText: 'Tags, comma-separated',
                ),
              ),
              TextField(
                controller: aliases,
                decoration: const InputDecoration(
                  labelText: 'Aliases, comma-separated',
                ),
              ),
              TextField(
                controller: kindField,
                decoration: const InputDecoration(
                  labelText: 'Kind',
                  hintText: 'note, project, person, place…',
                ),
              ),
              TextField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
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
  }) async {
    await _ensureIndexed();
    if (!mounted || dirty) return;
    final v = vault;
    final ix = index;
    if (v == null || ix == null) return;
    final searchStore = SavedSearchStore(v.storage);
    final savedSearches = await searchStore.load();
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => KnowledgeScreen(
          initialView: initialView,
          index: ix,
          search: (query, tag, status) =>
              workspace.searchNotes(query, tag: tag, status: status),
          savedSearches: savedSearches,
          onSaveSearch: (search) async {
            final next = [
              ...savedSearches.where((s) => s.name != search.name),
              search,
            ];
            await searchStore.save(next);
            _queueCloudSync();
          },
          onDeleteSearch: (search) async {
            await searchStore.save(
              savedSearches.where((s) => s.name != search.name).toList(),
            );
            _queueCloudSync();
          },
          problems: _knowledgeProblems(),
          onOpenNote: _openPath,
          onFixProblems: _fixProblems,
        ),
      ),
    );
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
      default:
        return null;
    }
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
  Future<List<PkmsProblem>?> _repairArticles(
    List<PkmsProblem> problems,
  ) async {
    final v = vault;
    if (v == null) return null;
    for (final problem in problems) {
      final source = await v.storage.readText(problem.subject);
      final repaired = repairArticleTypst(source);
      if (repaired != source) {
        await v.saveNote(problem.subject, repaired);
      }
    }
    await workspace.refreshIndex(always: true);
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
      final source = await v.storage.readText(problem.subject);
      if (source.contains('tylog.note.with(')) {
        // The header is fine — the note is flagged because Typst couldn't
        // verify it (engine timeout/death). Rewriting the header from
        // fallback-parsed metadata fixes nothing and risks baking
        // body-recovered tags into it.
        alreadyManaged++;
        continue;
      }
      final updated = replaceNoteHeader(
        source,
        NoteMetadataDraft.fromNote(note),
      );
      if (updated != source) {
        await v.saveNote(problem.subject, updated);
        converted++;
      }
    }
    await workspace.refreshIndex(always: true);
    if (!mounted) return null;
    final remaining = _stillFlagged(problems, 'metadata-fallback');
    final parts = [
      if (converted > 0) 'Converted $converted note${converted == 1 ? '' : 's'}',
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
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              subtitle: Text('Open each to compare, then merge or delete one.'),
            ),
            for (final problem in problems) ...[
              ListTile(
                title: Text(
                  '“${problem.subject}” is claimed by ${owners(problem).length} files',
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
      ),
    );
    if (choice == null || !mounted) return;
    Navigator.pop(context); // leave the Problems screen
    await _openPath(choice);
  }

  Future<void> _setTaskStatus(TaskRef task, String nextStatus) async {
    final v = vault;
    if (v == null) return;
    final file = task.notePath;
    final source = await v.storage.readText(file);
    await v.saveNote(
      file,
      task.recurrence != null && nextStatus == 'done'
          ? completeTaskOccurrence(
              source,
              task.id,
              DateTime.now().toUtc().toIso8601String(),
            )
          : replaceTaskStatus(source, task.id, nextStatus),
    );
    await _rebuildIndex();
  }

  Future<void> _setNoteProperty(NoteRef note, String name, String value) async {
    final v = vault;
    if (v == null) return;
    final source = await v.storage.readText(note.path);
    await v.saveNote(note.path, replaceNoteProperty(source, name, value));
    await _rebuildIndex();
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

  /// One-off maintenance action: folds the legacy `properties["type"]`
  /// entity classifier into `kind` across every note in the vault (see
  /// [migrateEntityTypeToKind]). Safe to run multiple times.
  Future<void> _migrateEntityTypes() async {
    final v = vault;
    final ix = index;
    if (v == null || ix == null) return;
    var migrated = 0;
    for (final note in ix.notes) {
      final source = await v.storage.readText(note.path);
      final updated = migrateEntityTypeToKind(source);
      if (updated != source) {
        await v.saveNote(note.path, updated);
        migrated++;
      }
    }
    await workspace.refreshIndex(always: true);
    if (!mounted) return;
    showSnack(
      context,
      migrated == 0
          ? 'No notes needed entity-type migration'
          : 'Migrated $migrated note${migrated == 1 ? '' : 's'} to '
                'kind-based entity types',
    );
  }

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
    final cfg =
        await NextcloudConfig.load(vaultId: vaultId) ??
        cloud ??
        await NextcloudConfig.load();
    if (!mounted) return false;
    final url = TextEditingController(text: cfg?.serverUrl ?? '');
    final user = TextEditingController(text: cfg?.username ?? '');
    final pass = TextEditingController(text: cfg?.password ?? '');
    final folder = TextEditingController(
      text: cfg?.remoteFolder ?? 'TyLogVault',
    );
    NextcloudConfig draft() => NextcloudConfig(
      serverUrl: url.text,
      username: user.text,
      password: pass.text,
      remoteFolder: folder.text,
    );
    while (true) {
      if (!mounted) return false;
      if (workspace.syncing) {
        showSnack(context, 'Sync already in progress');
        return false;
      }
      final saved = await showDialog<NextcloudConfig>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Connect Nextcloud'),
            content: SingleChildScrollView(
              child: AutofillGroup(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: url,
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.url],
                      onChanged: (_) => setDialogState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Server URL',
                        hintText: 'https://cloud.example.com',
                      ),
                    ),
                    TextField(
                      controller: user,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.username],
                      onChanged: (_) => setDialogState(() {}),
                      decoration: const InputDecoration(labelText: 'Login'),
                    ),
                    TextField(
                      controller: pass,
                      obscureText: true,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.password],
                      onChanged: (_) => setDialogState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Password or app password',
                      ),
                    ),
                    TextField(
                      controller: folder,
                      textInputAction: TextInputAction.done,
                      onChanged: (_) => setDialogState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Remote folder',
                        helperText: 'Created inside your Nextcloud files.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: draft().isReady
                    ? () {
                        TextInput.finishAutofillContext();
                        Navigator.pop(context, draft());
                      }
                    : null,
                child: const Text('Check folder'),
              ),
            ],
          ),
        ),
      );
      if (saved == null || !mounted) return false;
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
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      // Android may kill the app inside the 400 ms autosave debounce; flush
      // pending edits now so backgrounding never loses keystrokes.
      if (dirty) unawaited(_save(syncAfter: false));
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
          unawaited(_syncNow(trigger: 'resume'));
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
      showDragHandle: true,
      builder: (context) => VaultsSheet(
        vaults: registry?.entries ?? const [],
        activeVaultId: registry?.activeId,
        onAddVault: () {
          if (vaultRegistry != null) unawaited(_pickVault());
        },
        onSwitchVault: (entry) => unawaited(_switchVault(entry)),
        onForgetVault: (entry) => unawaited(_forgetVault(entry)),
        onDeleteVault: (entry) => unawaited(_deleteVault(entry)),
      ),
    );
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

    showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
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
            vaultPath: vaultPath,
            cloud: cloud,
            syncing: syncing,
            syncStatusSubtitle: syncStatusSubtitle,
            vaultCount: registry?.entries.length ?? 0,
            themeMode: widget.themeMode,
            onThemeModeChanged: (mode) {
              widget.onThemeModeChanged?.call(mode);
              unawaited(registry?.setThemeMode(themeModeName(mode)) ??
                  Future.value());
            },
            onManageVaults: () => Navigator.pop(context, true),
            onNextcloud: () {
              Navigator.pop(context);
              unawaited(_showSyncDashboard());
            },
            onEnableReminders: () async {
              await taskScheduler.requestPermission();
              await taskScheduler.reconcile(index?.tasks ?? const []);
              if (mounted) setState(() => status = 'Task reminders enabled');
            },
            onMigrateEntityTypes: () async {
              Navigator.pop(context);
              await _migrateEntityTypes();
            },
            onImportVault: () async {
              Navigator.pop(context);
              await _importVault();
            },
            onCheckForUpdates: Platform.isMacOS
                ? () {
                    Navigator.pop(context);
                    unawaited(_checkForUpdates(silent: false));
                  }
                : null,
          );
        },
      ),
    ).then((manageVaults) {
      if (manageVaults == true && mounted) _showVaults();
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
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(fix),
                    ),
                ],
                Wrap(
                  spacing: 8,
                  children: [
                    for (final entry in const {
                      'Heading': '= Heading',
                      'Note link': '#tylog.ref-note("note-id")[Title]',
                      'Tag': '#tylog.tag("topic")',
                      'Date': '#tylog.date-ref("2026-07-05")[5 July]',
                      'Task':
                          '#tylog.task(id: "task-id", text: "Task", due: none, project: none)',
                    }.entries)
                      ActionChip(
                        label: Text(entry.key),
                        onPressed: () {
                          Navigator.pop(context);
                          _insertTypstSnippet(entry.value);
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
      await openPlatformFile(v.storage, path, localRoot: _localVaultDirectory);
    } catch (error) {
      if (mounted) setState(() => status = 'Could not open file: $error');
    }
  }

  void _insertTypstSnippet(String snippet) {
    final source = _currentSource();
    _loadSource('${source.trimRight()}\n\n$snippet\n');
    setState(() => mode = 'source');
    _queueAutosave();
  }

  Future<void> _openPath(String path) async {
    final v = vault;
    if (v == null) return;
    await _openNote(path);
  }

  void _showEditor() {
    if (mode == 'source' || mode == 'split') {
      richController.loadSource(sourceController.text);
    }
    setState(() => mode = 'normal');
  }

  Future<void> _showToday() async {
    if (dirty) await _save();
    if (!mounted) return;
    setState(() => primaryDestination = 0);
    await _openToday();
  }

  void _setEditorMode(String next) {
    if (next == 'normal') {
      _showEditor();
    } else {
      if (mode == 'normal') sourceController.text = _currentSource();
      setState(() => mode = next);
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
    }
  }

  /// Appends a reading-log line to today's daily note so "what I read"
  /// survives even after the article file itself is deleted. Plain text on
  /// purpose — a link would dangle once the article is gone.
  Future<void> _logReading(String title, {String? rating}) async {
    final v = vault;
    if (v == null || title.trim().isEmpty) return;
    try {
      final dayPath = await v.todayNote();
      final safeTitle = typstContent(title.trim());
      final stars = int.tryParse(rating ?? '');
      final line = rating == null
          ? '- Read: $safeTitle'
          : stars != null
          ? '- Read: $safeTitle — ${'★' * stars}${'☆' * (5 - stars)}'
          : '- Read: $safeTitle — 🗑';
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
        await v.saveNote(dayPath, updated);
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
    primaryDestination = 2;
    unawaited(
      _openPath(path).then((_) {
        if (mounted) setState(() => mode = 'read');
      }),
    );
  }

  Future<void> _deleteArticle(NoteRef ref) async {
    final v = vault;
    if (v == null) return;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete article?',
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
      await _openToday();
      if (mounted) setState(() => mode = 'library');
    }
    await v.storage.delete(ref.path);
    await _rebuildIndex();
    if (mounted) setState(() => status = 'Deleted ${ref.title}');
  }

  Future<void> _rateArticle(String path, String value) async {
    final v = vault;
    if (v == null) return;
    final source = await v.storage.readText(path);
    await v.saveNote(path, replaceNoteProperty(source, 'rating', value));
    final title = index?.notesByPath[path]?.title;
    if (title != null) await _logReading(title, rating: value);
    await _rebuildIndex();
    if (value != 'shit' || !mounted) return;
    final rated = index?.notesByPath[path];
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
        stage: syncStage,
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
    if (await v.storage.exists(tracePath)) {
      for (final line in (await v.storage.readText(tracePath)).split('\n')) {
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
      storageLocation: entry.storageKind == 'android-tree'
          ? entry.treeUri ?? entry.name
          : entry.path,
      backupPath: entry.backupPath,
      cloud: cloud,
      syncing: syncing,
      stage: syncStage,
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

  Future<void> _resolveSyncConflict(SyncConflict conflict) async {
    final v = vault;
    final cfg = cloud;
    if (v == null || cfg == null || !cfg.isReady) return;
    final localBytes = await v.storage.exists(conflict.path)
        ? await v.storage.readBytes(conflict.path)
        : null;
    final remoteBytes = conflict.remoteSnapshot == null
        ? null
        : await v.storage.readBytes(conflict.remoteSnapshot!);
    final localText = conflict.isText && localBytes != null
        ? utf8.decode(localBytes, allowMalformed: true)
        : null;
    final remoteText = conflict.isText && remoteBytes != null
        ? utf8.decode(remoteBytes, allowMalformed: true)
        : null;
    if (!mounted) return;
    final selected = ValueNotifier<SyncConflictResolution>(
      SyncConflictResolution.keepLocal,
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
              icon: const Icon(Icons.close),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                conflict.path,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              ValueListenableBuilder<SyncConflictResolution>(
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
                            subtitle: localBytes == null
                                ? const Text('File deleted')
                                : Text('${localBytes.length} bytes'),
                          ),
                          RadioListTile<SyncConflictResolution>(
                            value: SyncConflictResolution.keepRemote,
                            title: Text(
                              conflict.remoteExists
                                  ? 'Keep Nextcloud version'
                                  : 'Keep deletion from Nextcloud',
                            ),
                            subtitle: remoteBytes == null
                                ? const Text('File deleted')
                                : Text('${remoteBytes.length} bytes'),
                          ),
                        ],
                      ),
                    ),
              ),
              if (localText != null && remoteText != null) ...[
                const SizedBox(height: 16),
                Text(
                  'Final version',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
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
              padding: const EdgeInsets.all(12),
              child: FilledButton.icon(
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(Icons.check),
                label: const Text('Save resolution'),
              ),
            ),
          ),
        ),
      ),
    );
    if (save == true) {
      try {
        await workspace.resolveConflict(
          conflict,
          selected.value,
          mergedText: selected.value == SyncConflictResolution.merge
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
    final trace = await v.storage.exists(path)
        ? await v.storage.readText(path)
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
        content: TextField(
          controller: input,
          autofocus: true,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: title,
          ),
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
    final notes = (index?.notes ?? const <NoteRef>[])
        .where((note) => kind == null || note.kind == kind)
        .toList();
    final chosen = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            if (heading != null)
              ListTile(
                title: Text(heading),
                subtitle: const Text('Dismiss to use no filter'),
              ),
            if (create)
              ListTile(
                leading: const Icon(Icons.add),
                title: Text('Create ${kind ?? 'note'}'),
                onTap: () => Navigator.pop(context, 'create'),
              ),
            for (final item in notes)
              ListTile(
                leading: Icon(
                  item.kind == 'project' ? Icons.work_outline : Icons.notes,
                ),
                title: Text(item.title),
                subtitle: Text(item.id),
                onTap: () => Navigator.pop(context, item),
              ),
          ],
        ),
      ),
    );
    if (chosen is NoteRef) return chosen;
    if (chosen != 'create') return null;
    final title = await _askText(
      'New ${kind ?? 'note'}',
      initialValue: _selectedText(),
    );
    if (title == null || title.isEmpty || vault == null) return null;
    final file = await vault!.page(title, kind: kind ?? 'note');
    await workspace.refreshIndex(always: true);
    return index?.notesByPath[file];
  }

  List<NoteRef> get _entities =>
      (index?.notes ?? const <NoteRef>[])
          .where((item) => !structuralNoteKinds.contains(item.kind))
          .toList()
        ..sort((a, b) => a.title.compareTo(b.title));

  Future<NoteRef?> _chooseEntity() async {
    final chosen = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('New entity'),
              onTap: () => Navigator.pop(context, 'create'),
            ),
            for (final item in _entities)
              ListTile(
                leading: const Icon(Icons.alternate_email),
                title: Text(item.title),
                subtitle: Text(item.kind),
                onTap: () => Navigator.pop(context, item),
              ),
          ],
        ),
      ),
    );
    if (chosen is NoteRef) return chosen;
    return chosen == 'create' ? _createEntity() : null;
  }

  Future<NoteRef?> _createEntity() async {
    final title = TextEditingController();
    final kind = TextEditingController(text: 'person');
    final aliases = TextEditingController();
    final email = TextEditingController();
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New entity'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: title,
              autofocus: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Name',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: kind,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Kind',
                hintText: 'person, place, castle…',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: aliases,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Aliases, comma-separated',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Email (optional)',
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
      ),
    );
    final name = title.text.trim();
    final entityKind = kind.text.trim();
    final v = vault;
    if (save != true || name.isEmpty || entityKind.isEmpty || v == null) {
      return null;
    }
    final file = await v.page(name);
    await workspace.refreshIndex(always: true);
    final created = index?.notesByPath[file];
    if (created == null) return null;
    await v.saveNote(
      file,
      replaceNoteHeader(
        await v.storage.readText(file),
        NoteMetadataDraft(
          id: created.id,
          title: created.title,
          kind: entityKind,
          tags: created.tags,
          aliases: _csvValues(aliases.text),
          properties: {
            ...created.properties,
            if (email.text.trim().isNotEmpty) 'email': email.text.trim(),
          },
        ),
      ),
    );
    await workspace.refreshIndex(always: true);
    return index?.notesByPath[file];
  }

  Future<void> _runMagic(MagicAction action) async {
    switch (action) {
      case MagicAction.bold:
      case MagicAction.italic:
      case MagicAction.heading:
      case MagicAction.strike:
      case MagicAction.underline:
      case MagicAction.mono:
      case MagicAction.highlight:
        _applyMagic(MagicRequest(action: action));
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
              .map((l) => l.replaceFirst(RegExp(r'^(?:[•☐☑] |\d+\. |[-+] )'), '').trim())
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
              final start = selection.isValid ? selection.start : editor.text.length;
              final end = selection.isValid ? selection.end : editor.text.length;
              final before = editor.text.substring(0, start);
              final after = editor.text.substring(end).replaceFirst(RegExp(r'^\n+'), '');
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
                selection: TextSelection.collapsed(offset: start + inserted.length),
              );
              _queueAutosave();
            }
            return;
          }
        }
        final text = await _askText('Task', initialValue: _selectedText());
        if (text == null || text.isEmpty) return;
        if (!mounted) return;
        final due = await showDatePicker(
          context: context,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
          initialDate: DateTime.now(),
          helpText: 'Due date (optional)',
        );
        final taskId = await vault!.nextTaskId(text);
        if (!mounted) return;
        _applyMagic(
          MagicRequest(
            action: action,
            id: taskId,
            value: text,
            due: due == null ? null : isoDay(due),
          ),
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
      case MagicAction.report:
        await _createReport();
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
                    child: TextField(
                      controller: rows,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Rows'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: columns,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Columns'),
                    ),
                  ),
                ],
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
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
    final path = note;
    if (path == null) {
      _magicFeedback('Open a note first');
      return;
    }
    // A dirty buffer would otherwise share the last-saved bytes.
    if (dirty) await _save(syncAfter: false);
    _magicFeedback('Building PDF…');
    final Uint8List pdf;
    try {
      pdf = await compileSourcePdf(
        source: _previewSource(),
        files: _typstFiles(),
      );
    } catch (error) {
      if (!mounted) return;
      // Same escape hatch the preview offers, since the cause is the same: the
      // note does not compile.
      unawaited(_showTypstHelp(error: error.toString()));
      return;
    }
    if (!mounted) return;
    final name = path.split('/').last.replaceFirst(RegExp(r'\.typ$'), '');
    await _sharePdfBytes(name, pdf);
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
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        var query = '';
        return SafeArea(
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
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
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
    final v = vault;
    if (v == null) return;
    final picked = await FilePicker.pickFiles();
    final sourcePath = picked?.files.single.path;
    if (sourcePath == null) return;
    final source = File(sourcePath);
    final base = source.path.split(Platform.pathSeparator).last;
    var target = 'assets/$base';
    var suffix = 2;
    while (await v.storage.exists(target)) {
      final dot = base.lastIndexOf('.');
      final stem = dot < 0 ? base : base.substring(0, dot);
      final extension = dot < 0 ? '' : base.substring(dot);
      target = 'assets/$stem-${suffix++}$extension';
    }
    await importPlatformFile(v.storage, target, source);
    final relative = target;
    const imageExtensions = {'.png', '.jpg', '.jpeg', '.gif', '.svg', '.webp'};
    final lower = target.toLowerCase();
    final image = imageExtensions.any(lower.endsWith);
    _applyMagic(
      MagicRequest(
        action: MagicAction.attachment,
        value: '/$relative',
        kind: image ? 'image' : 'file',
      ),
    );
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
    final export = await exportReportPdfStorage(v.storage, report);
    if (mounted) {
      setState(() => status = 'Created $report and ${export.path}');
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
        showDragHandle: true,
        isScrollControlled: true,
        builder: (context) {
          final columns = MediaQuery.sizeOf(context).width < 500 ? 3 : 4;
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.8,
              child: CustomScrollView(
                slivers: [
                  for (final group in kMagicActionGroups.entries) ...[
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      sliver: SliverToBoxAdapter(
                        child: Text(
                          group.key,
                          style: Theme.of(context).textTheme.titleMedium,
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

  Future<void> _selectDestination(int destination) async {
    if (destination == 3) {
      await _showKnowledge();
      return;
    }
    if (destination == 4) return;
    if (dirty) await _save();
    if (!mounted) return;
    switch (destination) {
      case 0:
        await _showToday();
        return;
      case 1:
        setState(() {
          primaryDestination = 1;
          mode = 'journal';
        });
        return;
      case 2:
        setState(() {
          primaryDestination = 2;
          mode = 'library';
        });
        return;
    }
  }

  Future<void> _showMoreMenu(Widget linksPanel) async {
    final action = await showModalBottomSheet<_ShellAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final entry in const <_ShellAction, (IconData, String)>{
              _ShellAction.vaults: (Icons.folder_outlined, 'Vaults'),
              _ShellAction.settings: (Icons.settings, 'Settings'),
              _ShellAction.newPage: (Icons.note_add_outlined, 'New page'),
              _ShellAction.graph: (Icons.account_tree_outlined, 'Graph'),
              _ShellAction.split: (Icons.vertical_split, 'Split editor'),
              _ShellAction.backlinks: (Icons.link, 'Context'),
              _ShellAction.sharePdf: (Icons.ios_share, 'Share as PDF'),
              _ShellAction.problems: (Icons.warning_amber, 'Problems'),
              _ShellAction.rebuild: (Icons.refresh, 'Rebuild index'),
              _ShellAction.relink: (Icons.auto_fix_high, 'Relink vault'),
              _ShellAction.typstHelp: (Icons.help_outline, 'Typst help'),
            }.entries)
              ListTile(
                leading: Icon(entry.value.$1),
                title: Text(entry.value.$2),
                onTap: () => Navigator.pop(context, entry.key),
              ),
          ],
        ),
      ),
    );
    if (action == null) return;
    await _runShellAction(action, linksPanel);
  }

  Future<void> _runShellAction(_ShellAction action, Widget linksPanel) async {
    switch (action) {
      case _ShellAction.vaults:
        _showVaults();
      case _ShellAction.newPage:
        await _newPage();
      case _ShellAction.graph:
        setState(() => mode = 'graph');
      case _ShellAction.split:
        sourceController.text = _currentSource();
        setState(() => mode = 'split');
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
      case _ShellAction.problems:
        await _showKnowledge(initialView: KnowledgeView.problems);
      case _ShellAction.rebuild:
        await _rebuildIndex(force: true);
      case _ShellAction.relink:
        await _relinkVault();
      case _ShellAction.typstHelp:
        await _showTypstHelp();
      case _ShellAction.settings:
        _showSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (mode != 'preview' && mode != 'split') {
      _previewDebounceTimer?.cancel();
      _previewDebounceTimer = null;
      _debouncedPreviewSource = null;
      _pendingPreviewSource = null;
    }
    final v = vault;
    final current = v == null || note == null ? null : note;
    final currentTitle = _currentTitle(current);
    if (mode == 'read') {
      final currentNote = current == null ? null : index?.notesByPath[current];
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
        onExit: _showEditor,
        onPreferencesChanged: _updateReadingPreferences,
        onProgress: _recordReadingProgress,
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
    final currentDaily = _dailyDateOf(current);
    final dayItems = currentDaily == null
        ? const <CalendarItem>[]
        : (index?.calendar ?? const <CalendarItem>[])
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
      'journal' => JournalFeed(
        vault: v,
        index: index,
        resolveKind: _resolveKind,
        onOpenPath: (path) {
          primaryDestination = 1;
          unawaited(_openPath(path));
        },
      ),
      'library' => LibraryView(
        index: index,
        indexing: rebuilding || syncing,
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
        onSetReadStatus: _setReadStatus,
        onSetRelevance: _setRelevance,
        noteToCluster: communities?.noteToCluster ?? const {},
        shelfPrefs: vaultRegistry?.shelfPrefs ?? const {},
        onShelfPrefsChanged: (prefs) =>
            unawaited(vaultRegistry?.updateShelfPrefs(prefs) ?? Future.value()),
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
      ),
      'graph' => GraphView(
        graph: graph ?? const NoteGraph(nodes: [], edges: []),
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
      'preview' => TypstDocumentViewer(
        source: _debouncedPreview(),
        files: _typstFiles(),
        loadingBuilder: (_) => const Center(child: LoadingIndicator()),
        errorBuilder: (_, error) => Padding(
          padding: const EdgeInsets.all(16),
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
              child: TypstDocumentViewer(
                source: _debouncedPreview(),
                files: _typstFiles(),
              ),
            ),
          ],
        );
      }(),
      'normal' => TyLogRichEditor(
        controller: richController,
        onInsert: _showMagicMenu,
        onMentionQuery: (query, kind) async {
          // Query the note index (populated the moment the vault opens), not
          // the full-text search index — the latter can take a while to finish
          // building on large SAF vaults, and mentions must resolve instantly.
          final q = query.trim().toLowerCase();
          if (q.isEmpty) return const <MentionSuggestion>[];
          bool matches(String s) => s.toLowerCase().startsWith(q);
          final notes = index?.notes ?? const <NoteRef>[];
          final matchedNotes =
              notes
                  .where(
                    (n) =>
                        matches(n.title) ||
                        matches(n.id) ||
                        n.aliases.any(matches),
                  )
                  .toList()
                ..sort((a, b) => a.title.compareTo(b.title));
          final suggestions = matchedNotes
              .take(8)
              .map((n) => MentionSuggestion(id: n.id, title: n.title))
              .toList();
          // `[[` also completes existing tags into concepts; `@` stays notes.
          if (kind == AutocompleteTriggerKind.wikiLink) {
            final tags =
                <String>{for (final n in notes) ...n.tags}.where(matches).toList()
                  ..sort();
            suggestions.addAll(
              tags.take(8).map(
                (t) => MentionSuggestion(
                  id: t,
                  title: t,
                  kind: MentionKind.concept,
                ),
              ),
            );
          }
          return suggestions;
        },
        onCommandSelected: _runMagic,
      ),
      _ => const SizedBox.shrink(),
    };
    final today = DateTime.now();
    final isTodayDocument =
        primaryDestination == 0 &&
        documentModes.contains(mode) &&
        currentDaily != null &&
        isoDay(currentDaily) == isoDay(today);
    // A person/place/… note gets a Logseq-style page: an info header above the
    // body and a linked-references (backlinks) block below it. Any note that is
    // mentioned elsewhere gets the references block too.
    final currentNote = current == null ? null : index?.notesByPath[current];
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
    final bodyContent = isTodayDocument
        ? TodayPage(
            tasks: index?.tasks ?? const [],
            recent: _recentNotes(),
            editor: content,
            onOpenPath: _openPath,
            onSetStatus: _setTaskStatus,
            onReadPath: _readPath,
          )
        : documentContent;
    // Floats over the body (see workArea's Stack): transient status must
    // never take part in content layout, or every screen jumps when a sync
    // starts, changes stage, and ends.
    Widget statusPill({required Widget child, Key? key}) => IgnorePointer(
      key: key,
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            elevation: 2,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 360),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: child,
            ),
          ),
        ),
      ),
    );
    final statusBanner = ListenableBuilder(
      listenable: Listenable.merge([workspace, workspace.syncProgressTick]),
      builder: (context, _) {
        final openFailed = status.startsWith('Open failed:');
        final banner = openFailed
            ? MaterialBanner(
                key: const ValueKey('status-error'),
                backgroundColor: Theme.of(context).colorScheme.errorContainer,
                content: Text(
                  status,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => unawaited(_open()),
                    child: const Text('Retry'),
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
                      syncing && syncStage != null ? syncStage! : status,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(value: rebuildProgress),
                  ],
                ),
              )
            : (syncing && syncStage != null)
            ? statusPill(
                key: const ValueKey('status-stage'),
                child: Text(
                  syncStage!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              )
            : const SizedBox.shrink(key: ValueKey('status-none'));
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: banner,
        );
      },
    );
    final workArea = WorkSurface(
      child: Stack(
        children: [
          Positioned.fill(child: bodyContent),
          Positioned(top: 0, left: 0, right: 0, child: statusBanner),
        ],
      ),
    );

    final wideNavigation = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: false,
        title: mode == 'journal'
            ? const Text('Journal')
            : mode == 'library'
            ? const Text('Library')
            : mode == 'graph'
            ? const Text('Graph')
            : documentModes.contains(mode) && currentDaily != null
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Previous day',
                    icon: const Icon(Icons.chevron_left),
                    // Calendar day, not 24h: DST-safe.
                    onPressed: () => unawaited(
                      _openDay(
                        DateTime(
                          currentDaily.year,
                          currentDaily.month,
                          currentDaily.day - 1,
                        ),
                      ),
                    ),
                  ),
                  Flexible(
                    child: Tooltip(
                      message: 'Calendar',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => unawaited(_showCalendarPicker()),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 48),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Center(
                              child: ValueListenableBuilder<bool>(
                                valueListenable: workspace.dirtyNotifier,
                                builder: (context, dirty, _) => Text(
                                  '${MediaQuery.sizeOf(context).width < 390 ? compactHumanDate(currentDaily) : humanDate(currentDaily)}${dirty ? ' •' : ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next day',
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () => unawaited(
                      _openDay(
                        DateTime(
                          currentDaily.year,
                          currentDaily.month,
                          currentDaily.day + 1,
                        ),
                      ),
                    ),
                  ),
                ],
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
          if (mode == 'journal')
            IconButton(
              tooltip: 'Choose journal date',
              onPressed: () => unawaited(_showCalendarPicker()),
              icon: const Icon(Icons.calendar_month),
            ),
          if (mode == 'graph')
            PopupMenuButton<String>(
              tooltip: 'Graph view',
              icon: Icon(switch (_graphMode) {
                'conceptMap' => Icons.bubble_chart,
                'allFiles' => Icons.hub,
                'timeline' => Icons.timeline,
                'voronoi' => Icons.hive,
                _ => Icons.center_focus_strong,
              }),
              onSelected: (value) => setState(() {
                _graphMode = value;
                _graphFocusPath = null;
              }),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'conceptMap', child: Text('Concept map')),
                PopupMenuItem(value: 'local', child: Text('Focused')),
                PopupMenuItem(value: 'allFiles', child: Text('All files')),
                PopupMenuItem(value: 'timeline', child: Text('Timeline')),
                PopupMenuItem(value: 'voronoi', child: Text('Voronoi')),
              ],
            ),
          if (documentModes.contains(mode))
            PopupMenuButton<String>(
              tooltip: 'View mode',
              icon: Icon(switch (mode) {
                'read' => Icons.chrome_reader_mode_outlined,
                'preview' => Icons.picture_as_pdf_outlined,
                'source' => Icons.code,
                _ => Icons.edit_outlined,
              }),
              onSelected: _setEditorMode,
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'normal', child: Text('Edit')),
                PopupMenuItem(value: 'read', child: Text('Read')),
                PopupMenuItem(value: 'preview', child: Text('Preview')),
                PopupMenuItem(value: 'source', child: Text('Source')),
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
          documentModes.contains(mode) && (mode == 'source' || mode == 'split')
          ? Padding(
              padding: const EdgeInsets.only(bottom: 52),
              child: FloatingActionButton.extended(
                onPressed: _showMagicMenu,
                icon: const Icon(Icons.auto_fix_high),
                label: const Text('Magic'),
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
                NavigationDestination(icon: Icon(Icons.today), label: 'Today'),
                NavigationDestination(
                  icon: Icon(Icons.edit_note),
                  label: 'Journal',
                ),
                NavigationDestination(
                  icon: Icon(Icons.library_books),
                  label: 'Library',
                ),
                NavigationDestination(
                  icon: Icon(Icons.search),
                  label: 'Search',
                ),
                NavigationDestination(
                  icon: Icon(Icons.more_horiz),
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
                  labelType: NavigationRailLabelType.all,
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.today),
                      label: Text('Today'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.edit_note),
                      label: Text('Journal'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.library_books),
                      label: Text('Library'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.search),
                      label: Text('Search'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.more_horiz),
                      label: Text('More'),
                    ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: workArea),
              ],
            )
          : workArea,
    );
  }

  String _currentTitle(String? current) => current == null
      ? 'Today'
      : index?.notesByPath[current]?.title ??
            current.split('/').last.replaceFirst('.typ', '');
}

enum _ShellAction {
  vaults,
  newPage,
  sharePdf,
  graph,
  split,
  backlinks,
  problems,
  rebuild,
  relink,
  typstHelp,
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
