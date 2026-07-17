import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:typst_flutter/typst_flutter.dart';

import 'bibliography.dart';
import 'controlled_editor.dart';
import 'graph.dart';
import 'knowledge_screen.dart';
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
import 'widgets/app_version.dart';
import 'widgets/constants.dart';
import 'widgets/date_format.dart';
import 'widgets/dialogs.dart';
import 'widgets/editor_panel.dart';
import 'widgets/journal_feed.dart';
import 'widgets/links_panel.dart';
import 'widgets/loading.dart';
import 'widgets/reading_mode.dart';
import 'widgets/settings_sheet.dart';
import 'widgets/snack.dart';
import 'widgets/sync_dashboard.dart';
import 'widgets/sync_status.dart';
import 'widgets/vaults_sheet.dart';
import 'widgets/work_surface.dart';
import 'workspace_controller.dart';

export 'widgets/app_version.dart';
export 'widgets/date_format.dart';
export 'widgets/sync_status.dart';
export 'widgets/work_surface.dart' show isTaskInTodayAgenda;

enum _MarkdownImportOutcome { imported, replaced, kept, unchanged, failed }

class _MarkdownImportReportItem {
  const _MarkdownImportReportItem({
    required this.name,
    required this.outcome,
    this.detail,
  });

  final String name;
  final _MarkdownImportOutcome outcome;
  final String? detail;
}

class _PreparedMarkdownArticle {
  const _PreparedMarkdownArticle(this.name, this.draft);

  final String name;
  final MarkdownArticleDraft draft;
}

enum _MarkdownDuplicateChoice { keepExisting, useImported, merged }

class _MarkdownDuplicateDecision {
  const _MarkdownDuplicateDecision(this.choice, [this.source]);

  final _MarkdownDuplicateChoice choice;
  final String? source;
}

String? vaultEntryLocation(VaultEntry? entry) =>
    entry?.treeUri ??
    (entry == null || entry.path.isEmpty ? entry?.name : entry.path);

class TyLogApp extends StatelessWidget {
  const TyLogApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'TyLog',
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF0F172A),
        brightness: Brightness.light,
        surface: const Color(0xFFF8FAFC),
      ),
      scaffoldBackgroundColor: const Color(0xFFF8FAFC),
      inputDecorationTheme: const InputDecorationTheme(
        border: InputBorder.none,
      ),
    ),
    home: const HomeScreen(),
  );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

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
  int primaryDestination = 0;
  String? selectedTag;
  VaultRegistry? vaultRegistry;
  final taskScheduler = TaskScheduler();
  final platformFileActions = const PlatformFileActions();
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
  set dirty(bool value) => workspace.dirty = value;
  int get editRevision => workspace.editRevision;
  set editRevision(int value) => workspace.editRevision = value;
  int get savedRevision => workspace.savedRevision;
  set savedRevision(int value) => workspace.savedRevision = value;
  int get indexedRevision => workspace.indexedRevision;
  set indexedRevision(int value) => workspace.indexedRevision = value;
  DateTime? get lastEditAt => workspace.lastEditAt;
  set lastEditAt(DateTime? value) => workspace.lastEditAt = value;
  String get helperSource => workspace.helperSource;
  Map<String, Uint8List> get typstPackageFiles => workspace.typstPackageFiles;
  String get bibliographySource => workspace.bibliographySource;
  set bibliographySource(String value) => workspace.bibliographySource = value;
  NextcloudConfig? get cloud => workspace.cloud;
  set cloud(NextcloudConfig? value) => workspace.cloud = value;
  PkmsSearchIndex get searchIndex => workspace.searchIndex;
  PkmsValidationReport? get validation => workspace.validation;
  set validation(PkmsValidationReport? value) => workspace.validation = value;
  SyncResult? get lastSync => workspace.lastSync;
  List<SyncConflict> get syncConflicts => workspace.syncConflicts;
  set syncConflicts(List<SyncConflict> value) =>
      workspace.syncConflicts = value;
  DateTime? get lastSyncAt => workspace.lastSyncAt;
  String? get syncError => workspace.syncError;
  set syncError(String? value) => workspace.syncError = value;
  bool get syncing => workspace.syncing;
  String? get syncStage => workspace.syncStage;
  bool? get storageHealthy => workspace.storageHealthy;
  set storageHealthy(bool? value) => workspace.storageHealthy = value;
  bool get rebuilding => workspace.rebuilding;
  bool get cancelRebuild => workspace.cancelRebuild;
  set cancelRebuild(bool value) => workspace.cancelRebuild = value;
  double? get rebuildProgress => workspace.rebuildProgress;

  @override
  void initState() {
    super.initState();
    richController = TyLogEditingController(
      source: '',
      onSourceChanged: _acceptRichSource,
      onError: _richEditorError,
      onProtectedTap: (id) => unawaited(_tapProtected(id)),
    );
    workspace = WorkspaceController(
      taskScheduler: taskScheduler,
      isComposing: () => richController.isComposing,
    )..addListener(_workspaceChanged);
    WidgetsBinding.instance.addObserver(this);
    _open();
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
      sourceController.text = workspace.source;
      richController.loadSource(workspace.source);
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

  void _closeVault(String message, {NextcloudConfig? nextCloud}) {
    selectedTag = null;
    workspace.close(message, nextCloud: nextCloud);
  }

  Future<void> _open() async {
    try {
      try {
        await taskScheduler.initialize((path) => unawaited(_openPath(path)));
      } catch (_) {
        // Notifications are optional on unsupported/test platforms.
      }
      final registry = await VaultRegistry.load();
      vaultRegistry = registry;
      if (Platform.isAndroid) {
        if (registry.entries.isEmpty) {
          if (!await _pickVault(closeCurrent: false)) {
            if (mounted) {
              setState(() => status = 'Choose a vault folder to continue');
            }
            return;
          }
        } else if (vaultNeedsAndroidTreeMigration(registry.active)) {
          if (!await _migrateAndroidVault(registry.active)) {
            _closeVault('Choose a vault folder to continue');
            return;
          }
        }
      }
      var active = registry.active;
      try {
        final storage = active.storage;
        if (storage is AndroidTreeVaultStorage &&
            (!await storage.hasAccess() ||
                !await storage.exists(Vault.settingsPath))) {
          throw PlatformException(
            code: 'saf_access_lost',
            message: 'Vault folder access must be granted again',
          );
        }
        await Vault.withStorage(storage).ensureCreated(
          createIfMissing:
              active.storageKind != 'android-tree' &&
              !vaultNeedsAndroidTreeMigration(active),
        );
      } on PlatformException {
        if (active.storageKind != 'android-tree') rethrow;
        final selected = await _chooseAndroidVault(
          allowEmpty: false,
          requiredUri: active.treeUri,
        );
        if (selected == null) {
          _closeVault('Folder access is required to open this vault');
          return;
        }
        active = await registry.rebindTree(active, selected.selection);
        await Vault.withStorage(
          active.storage,
        ).ensureCreated(createIfMissing: false);
      } on StateError {
        if (active.storageKind == 'android-tree') rethrow;
        var path = '${active.path}-v5';
        var suffix = 2;
        while (await Directory(path).exists()) {
          try {
            await Vault(Directory(path)).ensureCreated();
            break;
          } on StateError {
            path = '${active.path}-v5-${suffix++}';
          }
        }
        active = await registry.add(path);
        await registry.select(active);
      }
      await _openVault(active, trigger: 'startup');
      if (!registry.onboardingComplete) await registry.completeOnboarding();
    } catch (e) {
      _closeVault('Open failed: $e', nextCloud: _activeRegistryEntry?.cloud);
    }
  }

  Future<void> _openVault(VaultEntry entry, {String? trigger}) async {
    if (vaultNeedsAndroidTreeMigration(entry)) {
      if (!await _migrateAndroidVault(entry)) {
        _closeVault(
          'Choose a vault folder to continue',
          nextCloud: entry.cloud,
        );
        return;
      }
      return _openVault(vaultRegistry!.active, trigger: trigger);
    }
    await workspace.openVault(entry, trigger: trigger);
    if (mounted) {
      setState(() {
        selectedTag = null;
        mode = 'normal';
      });
    }
  }

  Future<void> _ensureIndexed() async {
    await workspace.ensureIndexed();
  }

  Future<void> _switchVault(VaultEntry entry) async {
    final registry = vaultRegistry;
    if (registry == null || registry.activeId == entry.id) return;
    if (dirty) await _save(syncAfter: false);
    var next = entry;
    if (vaultNeedsAndroidTreeMigration(next)) {
      if (!await _migrateAndroidVault(next)) {
        _closeVault('Choose a vault folder to continue', nextCloud: next.cloud);
        return;
      }
      next = registry.active;
    } else {
      await registry.select(next);
    }
    await _openVault(next);
  }

  Future<bool> _pickVault({bool closeCurrent = true}) async {
    if (closeCurrent && Navigator.canPop(context)) Navigator.pop(context);
    if (Platform.isAndroid) {
      final selected = await _chooseAndroidVault(allowEmpty: true);
      if (selected == null) return false;
      final selection = selected.selection;
      final storage = AndroidTreeVaultStorage(
        uri: selection.uri,
        name: selection.name,
      );
      try {
        final next = Vault.withStorage(storage);
        await next.ensureCreated();
        final registry = vaultRegistry!;
        final entry = await registry.addTree(selection);
        await registry.select(entry);
        await _openVault(entry);
        return true;
      } catch (error) {
        if (mounted) {
          setState(() => status = 'Could not open selected folder: $error');
        }
        return false;
      }
    }
    final path = await FilePicker.getDirectoryPath(
      dialogTitle: 'Choose vault folder',
    );
    if (path == null) return false;
    try {
      final probe = File('$path/.tylog-access-test.tmp');
      await probe.writeAsString('ok', flush: true);
      await probe.delete();
    } catch (e) {
      if (mounted) {
        setState(() => status = 'Selected folder is not writable: $e');
      }
      return false;
    }
    final registry = vaultRegistry!;
    final entry = await registry.add(path);
    await _switchVault(entry);
    if (registry.activeId != entry.id) {
      await registry.select(entry);
      await _openVault(entry);
    }
    return true;
  }

  Future<bool> _migrateAndroidVault(VaultEntry entry) async {
    final selected = await _chooseAndroidVault(allowEmpty: true);
    if (selected == null) return false;
    final selection = selected.selection;
    try {
      final registry = vaultRegistry!;

      Future<void> adoptSelectedVault() async {
        final storage = AndroidTreeVaultStorage(
          uri: selection.uri,
          name: selection.name,
        );
        await Vault.withStorage(storage).ensureCreated();
        final replacement = await registry.addTree(selection);
        await registry.select(replacement);
        await registry.forget(entry);
      }

      if (selected.inspection.kind == VaultStorageKind.validVault) {
        await adoptSelectedVault();
      } else {
        final source = await inspectVaultStorage(entry.storage);
        if (source.kind == VaultStorageKind.validVault) {
          final migrated = await registry.migrateToTree(entry, selection);
          await registry.select(migrated);
        } else if (source.kind == VaultStorageKind.empty) {
          await adoptSelectedVault();
        } else {
          throw StateError(
            'The previous app vault is not a valid v5 vault; its files were kept.',
          );
        }
      }
      return true;
    } catch (error) {
      if (mounted) {
        setState(
          () => status = 'Vault migration failed; original kept: $error',
        );
      }
      return false;
    }
  }

  Future<({AndroidTreeSelection selection, VaultStorageInspection inspection})?>
  _chooseAndroidVault({required bool allowEmpty, String? requiredUri}) async {
    Future<bool> chooseAgain(String message) async {
      if (!mounted) return false;
      return showConfirmDialog(
        context,
        title: 'Folder cannot be used',
        message: message,
        confirmLabel: 'Choose another folder',
        barrierDismissible: false,
      );
    }

    var explainAccess = true;
    while (mounted) {
      AndroidTreeSelection? selection;
      try {
        selection = explainAccess
            ? await _requestAndroidVaultAccess()
            : await AndroidTreeVaultStorage.pick();
        explainAccess = false;
      } catch (error) {
        if (!await chooseAgain('TyLog could not open this folder: $error')) {
          return null;
        }
        continue;
      }
      if (selection == null) return null;
      final storage = AndroidTreeVaultStorage(
        uri: selection.uri,
        name: selection.name,
      );
      VaultStorageInspection? inspection;
      Object? inspectionError;
      try {
        inspection = await inspectVaultStorage(storage);
        final acceptedKind =
            inspection.kind == VaultStorageKind.validVault ||
            allowEmpty && inspection.kind == VaultStorageKind.empty;
        if (acceptedKind &&
            (requiredUri == null || selection.uri == requiredUri)) {
          await storage.persistAccess();
          return (selection: selection, inspection: inspection);
        }
      } catch (error) {
        inspectionError = error;
      }
      final message = inspectionError != null
          ? 'TyLog could not inspect this folder: $inspectionError'
          : requiredUri != null && selection.uri != requiredUri
          ? 'This is a different folder. Select the original vault folder.'
          : inspection!.kind == VaultStorageKind.incompatibleVault
          ? 'This folder has a malformed or unsupported TyLog vault marker.'
          : allowEmpty
          ? 'This folder contains other files. Choose an empty folder or an existing TyLog vault.'
          : 'This is not the existing TyLog vault. Select its original folder.';
      if (!await chooseAgain(message)) return null;
    }
    return null;
  }

  Future<AndroidTreeSelection?> _requestAndroidVaultAccess() async {
    final allowed = await showConfirmDialog(
      context,
      title: 'Allow vault folder access',
      message:
          'TyLog needs access to one folder to read and save your notes. '
          'Android will open its folder picker. Choose your vault, then tap '
          '“Use this folder”. TyLog cannot access other folders.',
      confirmLabel: 'Choose folder',
      barrierDismissible: false,
    );
    if (!allowed || !mounted) return null;
    return AndroidTreeVaultStorage.pick();
  }

  Future<void> _forgetVault(VaultEntry entry) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Disconnect this vault?',
      message:
          '${entry.name} will be removed from this list. Its files stay on disk untouched, and you can re-add the vault later.',
      confirmLabel: 'Disconnect',
    );
    if (!confirmed || !mounted) return;
    final registry = vaultRegistry!;
    try {
      workspace.cancelPendingWork();
      final wasActive = entry.id == registry.activeId;
      await registry.forget(entry);
      if (registry.entries.isEmpty) {
        _closeVault('Forgot ${entry.name}; add a vault to continue');
        return;
      }
      if (wasActive) await _openVault(registry.active);
      if (mounted) setState(() => status = 'Forgot ${entry.name}; files kept');
    } catch (e) {
      if (mounted) setState(() => status = 'Forget failed: $e');
    }
  }

  Future<void> _deleteVault(VaultEntry entry) async {
    final warned = await showConfirmDialog(
      context,
      title: 'Delete vault and files?',
      message:
          'This permanently deletes all notes, pages, assets, metadata, and sync state in ${entry.name}. There is no recovery.',
      confirmLabel: 'Continue',
      destructive: true,
    );
    if (!warned || !mounted) return;
    final typed = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Confirm permanent deletion'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Type ${entry.name} to delete this vault and every file in it.',
              ),
              TextField(
                controller: typed,
                autofocus: true,
                onChanged: (_) => setDialogState(() {}),
                decoration: const InputDecoration(labelText: 'Vault name'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: typed.text == entry.name
                  ? () => Navigator.pop(context, true)
                  : null,
              child: const Text('Delete permanently'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    workspace.cancelPendingWork();
    try {
      final registry = vaultRegistry!;
      final wasActive = registry.activeId == entry.id;
      await registry.delete(entry);
      if (shouldCreateDefaultReplacementVault(
        entriesEmpty: registry.entries.isEmpty,
      )) {
        final replacement = defaultVaultDirectory(
          await getApplicationDocumentsDirectory(),
        );
        await Vault(replacement).ensureCreated();
        final replacementEntry = await registry.add(replacement.path);
        await registry.select(replacementEntry);
      }
      if (registry.entries.isEmpty && Platform.isAndroid) {
        _closeVault('Choose a vault folder to continue');
        await _pickVault(closeCurrent: false);
        return;
      }
      if (wasActive && registry.entries.isNotEmpty) {
        await _openVault(registry.active);
      }
      if (mounted) {
        setState(() => status = 'Deleted ${entry.name} and its files');
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => status = entry.storageKind == 'android-tree'
              ? 'Delete failed; use Android Files to delete ${entry.name}: $e'
              : 'Delete failed; vault kept: $e',
        );
      }
    }
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

  FileSource _typstFiles() => FileSource.bytes({
    '_system/tylog.typ': Uint8List.fromList(utf8.encode(helperSource)),
    '/_system/tylog.typ': Uint8List.fromList(utf8.encode(helperSource)),
    ...typstPackageFiles,
    if (bibliographySource.isNotEmpty) ...{
      Vault.bibliographyPath: Uint8List.fromList(
        utf8.encode(bibliographySource),
      ),
      '/${Vault.bibliographyPath}': Uint8List.fromList(
        utf8.encode(bibliographySource),
      ),
    },
  });

  /// Preview-only source: cited notes get a bibliography section appended so
  /// `@key` references resolve; the stored note is never modified.
  String _previewSource() {
    final source = sourceController.text;
    final bib = bibliographySource.trim();
    if (bib.isEmpty || bib == '{}') return source;
    if (!RegExp(r'(^|[\s\[(])@[A-Za-z0-9_-]+').hasMatch(source)) return source;
    return '$source\n#bibliography("/${Vault.bibliographyPath}")\n';
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
    final match = RegExp(
      r'^#tylog\.date-ref\("(\d{4})-(\d{2})-(\d{2})"',
    ).firstMatch(richController.protectedSource(id).trim());
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
    await _editProtectedBlock(id);
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
    if (entry != null) unawaited(vaultRegistry!.recordOpen(entry, path));
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
  }

  Future<void> _newPage() async {
    final v = vault;
    if (v == null) return;
    final title = await _askPageTitle();
    if (title == null || title.trim().isEmpty) return;
    final template = await _chooseTemplate(v);
    if (dirty) await _save();
    final file = await v.page(title, template: template);
    await workspace.refreshIndex(force: true);
    await _openNote(file);
    setState(() {
      status = 'Created $file';
    });
  }

  Future<void> _importMarkdownArticles() async {
    final opened = vault;
    if (opened == null) return;
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['md', 'markdown'],
    );
    if (picked == null || picked.files.isEmpty) return;
    if (dirty) await _save(syncAfter: false);
    if (!mounted || vault != opened) return;

    final progress = ValueNotifier<String>(
      'Preparing 0 of ${picked.files.length}',
    );
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Importing Markdown articles'),
          content: ValueListenableBuilder<String>(
            valueListenable: progress,
            builder: (context, message, _) => SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const LinearProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(message),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final prepared = <_PreparedMarkdownArticle>[];
    final report = <_MarkdownImportReportItem>[];
    for (var index = 0; index < picked.files.length; index++) {
      final file = picked.files[index];
      progress.value =
          'Preparing ${index + 1} of ${picked.files.length}\n${file.name}';
      try {
        final lower = file.name.toLowerCase();
        if (!lower.endsWith('.md') && !lower.endsWith('.markdown')) {
          throw const FormatException(
            'Only .md and .markdown files are supported',
          );
        }
        prepared.add(
          _PreparedMarkdownArticle(
            file.name,
            await buildMarkdownArticleDraft(
              bytes: await file.readAsBytes(),
              sourceName: file.name,
            ),
          ),
        );
      } catch (error) {
        report.add(
          _MarkdownImportReportItem(
            name: file.name,
            outcome: _MarkdownImportOutcome.failed,
            detail: error.toString(),
          ),
        );
      }
    }
    if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    progress.dispose();
    if (!mounted) return;

    final articles = (index?.notes ?? const <NoteRef>[])
        .where((note) => note.kind == 'article')
        .toList();
    var wroteFiles = false;
    for (final item in prepared) {
      final draft = item.draft;
      try {
        final duplicate = classifyMarkdownDuplicate(draft, articles);
        final warningDetail = draft.diagnostics.isEmpty
            ? null
            : '${draft.diagnostics.length} conversion warning${draft.diagnostics.length == 1 ? '' : 's'}';
        switch (duplicate.kind) {
          case MarkdownDuplicateKind.newArticle:
            final path = await nextMarkdownArticlePath(
              opened.storage,
              draft.title,
            );
            await opened.saveNote(path, draft.typstSource);
            articles.add(_noteForImportedArticle(path, draft));
            wroteFiles = true;
            report.add(
              _MarkdownImportReportItem(
                name: item.name,
                outcome: _MarkdownImportOutcome.imported,
                detail: warningDetail ?? path,
              ),
            );
            break;
          case MarkdownDuplicateKind.unchanged:
            report.add(
              _MarkdownImportReportItem(
                name: item.name,
                outcome: _MarkdownImportOutcome.unchanged,
                detail: duplicate.existing?.path,
              ),
            );
            break;
          case MarkdownDuplicateKind.changed:
            final existing = duplicate.existing!;
            final existingSource = await opened.readText(existing.path);
            final decision = await _resolveMarkdownDuplicate(
              existing: existingSource,
              incoming: draft.typstSource,
              title: draft.title,
            );
            if (decision.choice == _MarkdownDuplicateChoice.keepExisting) {
              report.add(
                _MarkdownImportReportItem(
                  name: item.name,
                  outcome: _MarkdownImportOutcome.kept,
                  detail: existing.path,
                ),
              );
              continue;
            }
            final source = decision.choice == _MarkdownDuplicateChoice.merged
                ? decision.source!
                : draft.typstSource;
            await opened.saveNote(existing.path, source);
            final position = articles.indexOf(existing);
            if (position >= 0) {
              articles[position] = _noteForImportedArticle(
                existing.path,
                draft,
              );
            }
            wroteFiles = true;
            report.add(
              _MarkdownImportReportItem(
                name: item.name,
                outcome: _MarkdownImportOutcome.replaced,
                detail: decision.choice == _MarkdownDuplicateChoice.merged
                    ? 'Manual merge · ${existing.path}'
                    : warningDetail ?? existing.path,
              ),
            );
            break;
        }
      } catch (error) {
        report.add(
          _MarkdownImportReportItem(
            name: item.name,
            outcome: _MarkdownImportOutcome.failed,
            detail: error.toString(),
          ),
        );
      }
    }

    if (wroteFiles) {
      await workspace.refreshIndex(updateStatus: false, force: true);
      _queueCloudSync();
    }
    if (!mounted) return;
    final successful = report
        .where((item) => item.outcome != _MarkdownImportOutcome.failed)
        .length;
    setState(() {
      status =
          'Markdown import: $successful succeeded, '
          '${report.length - successful} failed';
    });
    await _showMarkdownImportReport(report);
  }

  NoteRef _noteForImportedArticle(String path, MarkdownArticleDraft draft) =>
      NoteRef(
        id: draft.id,
        path: path,
        title: draft.title,
        kind: 'article',
        date: draft.date,
        tags: draft.tags,
        aliases: draft.aliases,
        outgoingLinks: const [],
        properties: draft.properties,
        metadataSource: 'typst-query',
      );

  Future<_MarkdownDuplicateDecision> _resolveMarkdownDuplicate({
    required String existing,
    required String incoming,
    required String title,
  }) async {
    final merged = TextEditingController(text: incoming);
    final result = await showDialog<_MarkdownDuplicateDecision>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        insetPadding: const EdgeInsets.all(16),
        title: Text('Article changed: $title'),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 1000,
            maxHeight: MediaQuery.sizeOf(context).height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final panes = [
                      _markdownSourcePane('Existing Typst', existing),
                      _markdownSourcePane('Incoming Typst', incoming),
                    ];
                    return constraints.maxWidth >= 700
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: panes[0]),
                              const SizedBox(width: 12),
                              Expanded(child: panes[1]),
                            ],
                          )
                        : ListView(
                            children: [
                              SizedBox(height: 180, child: panes[0]),
                              const SizedBox(height: 12),
                              SizedBox(height: 180, child: panes[1]),
                            ],
                          );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  TextButton(
                    onPressed: () => merged.text = existing,
                    child: const Text('Edit existing'),
                  ),
                  TextButton(
                    onPressed: () => merged.text = incoming,
                    child: const Text('Edit imported'),
                  ),
                ],
              ),
              SizedBox(
                height: 180,
                child: TextField(
                  key: const ValueKey('markdown-manual-merge'),
                  controller: merged,
                  expands: true,
                  maxLines: null,
                  minLines: null,
                  textAlignVertical: TextAlignVertical.top,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Manual merged Typst source',
                    alignLabelWithHint: true,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(
              context,
              const _MarkdownDuplicateDecision(
                _MarkdownDuplicateChoice.keepExisting,
              ),
            ),
            child: const Text('Keep existing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(
              context,
              const _MarkdownDuplicateDecision(
                _MarkdownDuplicateChoice.useImported,
              ),
            ),
            child: const Text('Use imported'),
          ),
          FilledButton(
            onPressed: () {
              if (merged.text.trim().isEmpty) {
                showSnack(context, 'Merged Typst cannot be empty');
                return;
              }
              Navigator.pop(
                context,
                _MarkdownDuplicateDecision(
                  _MarkdownDuplicateChoice.merged,
                  merged.text,
                ),
              );
            },
            child: const Text('Save manual merge'),
          ),
        ],
      ),
    );
    merged.dispose();
    return result ??
        const _MarkdownDuplicateDecision(_MarkdownDuplicateChoice.keepExisting);
  }

  Widget _markdownSourcePane(String title, String source) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(title, style: Theme.of(context).textTheme.titleSmall),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(8),
            child: SelectableText(
              source,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
        ),
      ],
    ),
  );

  Future<void> _showMarkdownImportReport(
    List<_MarkdownImportReportItem> report,
  ) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Markdown import complete'),
      content: SizedBox(
        width: 560,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final item in report)
              ListTile(
                dense: true,
                leading: Icon(switch (item.outcome) {
                  _MarkdownImportOutcome.imported => Icons.file_download_done,
                  _MarkdownImportOutcome.replaced => Icons.swap_horiz,
                  _MarkdownImportOutcome.kept => Icons.inventory_2_outlined,
                  _MarkdownImportOutcome.unchanged =>
                    Icons.check_circle_outline,
                  _MarkdownImportOutcome.failed => Icons.error_outline,
                }),
                title: Text(item.name),
                subtitle: Text(
                  '${item.outcome.name}${item.detail == null ? '' : ' · ${item.detail}'}',
                ),
              ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    ),
  );

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
          properties: current.properties,
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
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => KnowledgeScreen(
          initialView: initialView,
          index: ix,
          search: searchIndex,
          problems: (validation?.problems ?? ix.problems)
              .where((problem) => !problem.code.startsWith('sync-'))
              .toList(),
          onOpenNote: _openPath,
        ),
      ),
    );
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

  Future<void> _setReadStatus(NoteRef note, String status) async {
    final v = vault;
    if (v == null) return;
    final source = await v.storage.readText(note.path);
    await v.saveNote(
      note.path,
      replaceNoteHeader(
        source,
        NoteMetadataDraft(
          id: note.id,
          title: note.title,
          kind: note.kind,
          project: note.project,
          date: note.date,
          tags: note.tags,
          aliases: note.aliases,
          properties: {...note.properties, 'status': status},
        ),
      ),
    );
    await _rebuildIndex();
  }

  String? _pathForLink(String title) {
    final ix = index;
    return ix == null ? null : resolveLinkPath(ix, title);
  }

  LinkResolution _resolveLink(String title) {
    final ix = index;
    return ix == null
        ? LinkResolution(target: title, status: LinkResolutionStatus.unresolved)
        : resolveLink(ix, title);
  }

  Future<void> _rebuildIndex() async {
    await workspace.rebuildIndex();
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
    await workspace.refreshIndex(force: true);
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
      return;
    }
    if (state == AppLifecycleState.resumed) {
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
    final registry = vaultRegistry;
    final activeLocation = vaultEntryLocation(_activeRegistryEntry);
    final openError = status.startsWith('Open failed:');
    final vaultPath = openError
        ? [activeLocation, status].whereType<String>().join('\n')
        : activeLocation ?? status;

    // Compute sync status using the same helpers as the dashboard
    final kind = syncStatusKind(
      vaultOpen: vault != null,
      storageHealthy: storageHealthy ?? false,
      cloudConfigured: cloud?.isReady ?? false,
      desktopManaged:
          _localVaultDirectory != null &&
          isNextcloudManagedVault(_localVaultDirectory!),
      syncing: syncing,
      error: syncError,
      conflicts: syncConflicts.length,
      result: lastSync,
    );
    final syncStatusSubtitle = syncStatusTitle(
      kind,
      conflicts: syncConflicts.length,
    );

    showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SettingsSheet(
            vaultPath: vaultPath,
            cloud: cloud,
            syncing: syncing,
            syncStatusSubtitle: syncStatusSubtitle,
            vaultCount: registry?.entries.length ?? 0,
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
          ),
        ),
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
      await platformFileActions.openExternal(
        v.storage,
        path,
        localRoot: _localVaultDirectory,
      );
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

  Future<void> _recordReadingProgress(String path, double progress) async {
    final entry = _activeRegistryEntry;
    if (entry == null) return;
    await vaultRegistry!.recordProgress(entry, path, progress);
  }

  List<(NoteRef note, double progress)> _recentNotes() {
    final notesByPath = index?.notesByPath;
    if (notesByPath == null) return const [];
    final result = <(NoteRef, double)>[];
    for (final recent in _activeRegistryEntry?.recent ?? const []) {
      final note = notesByPath[recent.path];
      if (note == null) continue;
      result.add((note, recent.progress));
      if (result.length == 8) break;
    }
    return result;
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
    await workspace.refreshIndex(force: true);
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
    await workspace.refreshIndex(force: true);
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
          properties: created.properties,
        ),
      ),
    );
    await workspace.refreshIndex(force: true);
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

  Future<String?> _chooseCitation() async {
    final v = vault;
    if (v == null || !await v.storage.exists(Vault.bibliographyPath)) {
      _magicFeedback('No bibliography entries');
      return null;
    }
    final bib = await v.storage.readText(Vault.bibliographyPath);
    bibliographySource = bib;
    final entries = parseHayagrivaBibliography(bib);
    if (!mounted) return null;
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            if (entries.isEmpty)
              const ListTile(title: Text('No bibliography entries')),
            for (final entry in entries)
              ListTile(
                leading: const Icon(Icons.format_quote),
                title: Text(entry.title),
                subtitle: Text('${entry.key} · ${entry.type}'),
                onTap: () => Navigator.pop(context, entry.key),
              ),
          ],
        ),
      ),
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
    await platformFileActions.importFile(v.storage, target, source);
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
      ReportFilter(
        project: project?.id,
        from: range == null ? null : isoDay(range.start),
        to: range == null ? null : isoDay(range.end),
      ),
    );
    final pdf = await exportReportPdfStorage(v.storage, report);
    if (mounted) {
      setState(() => status = 'Created $report and $pdf');
      _magicFeedback('Created report and PDF');
      _queueCloudSync();
    }
  }

  Future<void> _showMagicMenu() async {
    try {
      final action = await showModalBottomSheet<MagicAction>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (context) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.8,
            child: GridView.count(
              crossAxisCount: MediaQuery.sizeOf(context).width < 500 ? 3 : 4,
              children: [
                for (final entry in kMagicActionDisplay.entries)
                  InkWell(
                    onTap: () => Navigator.pop(context, entry.key),
                    child: Semantics(
                      button: true,
                      label: entry.value.$2,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (entry.key == MagicAction.heading)
                            Text(
                              'H1',
                              style: Theme.of(context).textTheme.titleLarge,
                            )
                          else
                            Icon(entry.value.$1),
                          const SizedBox(height: 6),
                          Text(entry.value.$2, textAlign: TextAlign.center),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
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
              _ShellAction.problems: (Icons.warning_amber, 'Problems'),
              _ShellAction.rebuild: (Icons.refresh, 'Rebuild index'),
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
      case _ShellAction.problems:
        await _showKnowledge(initialView: KnowledgeView.problems);
      case _ShellAction.rebuild:
        await _rebuildIndex();
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
      return ReadingMode(
        source: _currentSource(),
        path: current,
        fontScale: vaultRegistry?.readingFontScale ?? 1,
        nightMode: vaultRegistry?.readingNightMode ?? false,
        onExit: _showEditor,
        onPreferencesChanged: _updateReadingPreferences,
        onProgress: _recordReadingProgress,
      );
    }
    final backlinks = current == null
        ? const <String>[]
        : index?.backlinksByTarget[current] ?? const <String>[];
    final outgoing = current == null
        ? const <String>[]
        : index?.notesByPath[current]?.outgoingLinks ?? const <String>[];
    final resolver = index == null ? null : LinkResolver(index!.notes);
    final graph = index == null ? null : buildLocalNoteGraph(index!, current);
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
        onOpenPath: (path) {
          primaryDestination = 1;
          unawaited(_openPath(path));
        },
      ),
      'library' => LibraryView(
        index: index,
        progressByPath: {
          for (final r in _activeRegistryEntry?.recent ?? const [])
            r.path: r.progress,
        },
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
        onCreateEntity: () => unawaited(_createEntity()),
        onImportMarkdownArticles: _importMarkdownArticles,
      ),
      'graph' => GraphView(
        graph: graph ?? const NoteGraph(nodes: [], edges: []),
        currentPath: current,
        onOpenPath: _openPath,
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
      'split' =>
        MediaQuery.sizeOf(context).width < 600
            ? Column(
                children: [
                  Expanded(
                    child: Editor(
                      key: sourceEditorKey,
                      controller: sourceController,
                      onChanged: _queueAutosave,
                      monospace: true,
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: TypstDocumentViewer(
                      source: _debouncedPreview(),
                      files: _typstFiles(),
                    ),
                  ),
                ],
              )
            : Row(
                children: [
                  Expanded(
                    child: Editor(
                      key: sourceEditorKey,
                      controller: sourceController,
                      onChanged: _queueAutosave,
                      monospace: true,
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: TypstDocumentViewer(
                      source: _debouncedPreview(),
                      files: _typstFiles(),
                    ),
                  ),
                ],
              ),
      'normal' => TyLogRichEditor(
        controller: richController,
        onInsert: _showMagicMenu,
        onMentionQuery: (query) async {
          // Query the note index (populated the moment the vault opens), not
          // the full-text search index — the latter can take a while to finish
          // building on large SAF vaults, and mentions must resolve instantly.
          final q = query.trim().toLowerCase();
          if (q.isEmpty) return const <MentionSuggestion>[];
          bool matches(String s) => s.toLowerCase().startsWith(q);
          final notes =
              (index?.notes ?? const <NoteRef>[])
                  .where(
                    (n) =>
                        matches(n.title) ||
                        matches(n.id) ||
                        n.aliases.any(matches),
                  )
                  .toList()
                ..sort((a, b) => a.title.compareTo(b.title));
          return notes
              .take(8)
              .map((n) => MentionSuggestion(id: n.id, title: n.title))
              .toList();
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
    final bodyContent = isTodayDocument
        ? TodayPage(
            tasks: index?.tasks ?? const [],
            recent: _recentNotes(),
            editor: content,
            onOpenPath: _openPath,
            onSetStatus: _setTaskStatus,
          )
        : content;
    final statusBanner = ListenableBuilder(
      listenable: Listenable.merge([workspace, workspace.syncProgressTick]),
      builder: (context, _) {
        final openFailed = status.startsWith('Open failed:');
        return openFailed
            ? MaterialBanner(
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
            ? Material(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        status,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(value: rebuildProgress),
                    ],
                  ),
                ),
              )
            : (syncing && syncStage != null)
            ? Material(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Text(
                    syncStage!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              )
            : const SizedBox.shrink();
      },
    );
    final workArea = WorkSurface(
      child: Column(
        children: [statusBanner, Expanded(child: bodyContent)],
      ),
    );

    final wideNavigation = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 0,
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
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 8,
                          ),
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
            listenable: Listenable.merge([workspace, workspace.syncProgressTick]),
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
  graph,
  split,
  backlinks,
  problems,
  rebuild,
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
