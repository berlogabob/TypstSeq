import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_file/open_file.dart';
import 'package:typst_flutter/typst_flutter.dart';

import 'bibliography.dart';
import 'controlled_editor.dart';
import 'graph.dart';
import 'knowledge_screen.dart';
import 'models.dart';
import 'month_calendar.dart';
import 'nextcloud_sync.dart';
import 'pkms_registry.dart';
import 'report.dart';
import 'rich_editor.dart';
import 'scanner.dart';
import 'search_index.dart';
import 'task_scheduler.dart';
import 'vault.dart';
import 'vault_registry.dart';
import 'vault_storage.dart';

Future<String> appVersion() async =>
    RegExp(r'^version:\s*(.+)$', multiLine: true)
        .firstMatch(await rootBundle.loadString('pubspec.yaml'))
        ?.group(1)
        ?.trim() ??
    'unknown';

enum SyncStatusKind {
  vaultClosed,
  storageUnavailable,
  desktopManaged,
  notConfigured,
  syncing,
  paused,
  conflicts,
  ready,
  upToDate,
  synced,
}

SyncStatusKind syncStatusKind({
  required bool vaultOpen,
  required bool storageHealthy,
  required bool cloudConfigured,
  required bool desktopManaged,
  required bool syncing,
  required String? error,
  required int conflicts,
  required SyncResult? result,
}) {
  if (!vaultOpen) return SyncStatusKind.vaultClosed;
  if (!storageHealthy) return SyncStatusKind.storageUnavailable;
  if (desktopManaged) return SyncStatusKind.desktopManaged;
  if (!cloudConfigured) return SyncStatusKind.notConfigured;
  if (syncing) return SyncStatusKind.syncing;
  if (error != null) return SyncStatusKind.paused;
  if (conflicts > 0) return SyncStatusKind.conflicts;
  if (result == null) return SyncStatusKind.ready;
  final changed =
      result.uploaded +
      result.downloaded +
      result.deletedLocal +
      result.deletedRemote;
  return changed == 0 ? SyncStatusKind.upToDate : SyncStatusKind.synced;
}

String syncStatusTitle(
  SyncStatusKind kind, {
  int conflicts = 0,
}) => switch (kind) {
  SyncStatusKind.vaultClosed => 'Vault not open',
  SyncStatusKind.storageUnavailable => 'Folder access unavailable',
  SyncStatusKind.desktopManaged => 'Nextcloud Desktop',
  SyncStatusKind.notConfigured => 'Sync not connected',
  SyncStatusKind.syncing => 'Syncing…',
  SyncStatusKind.paused => 'Sync paused',
  SyncStatusKind.conflicts =>
    '$conflicts ${conflicts == 1 ? 'conflict needs' : 'conflicts need'} review',
  SyncStatusKind.ready => 'Ready to sync',
  SyncStatusKind.upToDate => 'Up to date',
  SyncStatusKind.synced => 'Synced',
};

String? syncStatusAction(SyncStatusKind kind) => switch (kind) {
  SyncStatusKind.notConfigured => 'Set up',
  SyncStatusKind.paused => 'Retry',
  SyncStatusKind.conflicts => 'Review',
  SyncStatusKind.ready ||
  SyncStatusKind.upToDate ||
  SyncStatusKind.synced => 'Sync now',
  _ => null,
};

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
  Vault? vault;
  VaultIndex? index;
  String? note;
  final sourceController = TextEditingController();
  late final TyLogEditingController richController;
  Timer? autosave;
  Timer? cloudAutosave;
  Timer? cloudPoll;
  String status = 'Opening vault...';
  bool dirty = false;
  int editRevision = 0;
  int savedRevision = 0;
  int indexedRevision = 0;
  DateTime? lastEditAt;
  // Launch lands in the journal editor with today's file open.
  String mode = 'normal';
  String helperSource = tylogHelperSource;
  String bibliographySource = '';
  NextcloudConfig? cloud;
  PkmsSearchIndex searchIndex = PkmsSearchIndex.empty();
  PkmsValidationReport? validation;
  SyncResult? lastSync;
  List<SyncConflict> syncConflicts = const [];
  DateTime? lastSyncAt;
  String? syncError;
  String? selectedTag;
  bool syncing = false;
  String? syncStage;
  bool? storageHealthy;
  bool rebuilding = false;
  bool cancelRebuild = false;
  double? rebuildProgress;
  VaultRegistry? vaultRegistry;
  final taskScheduler = TaskScheduler();

  @override
  void initState() {
    super.initState();
    richController = TyLogEditingController(
      source: '',
      onSourceChanged: _acceptRichSource,
      onError: _richEditorError,
      onProtectedTap: (id) => unawaited(_tapProtected(id)),
    );
    WidgetsBinding.instance.addObserver(this);
    _open();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    autosave?.cancel();
    cloudAutosave?.cancel();
    cloudPoll?.cancel();
    richController.dispose();
    sourceController.dispose();
    super.dispose();
  }

  VaultEntry? get _activeRegistryEntry {
    final registry = vaultRegistry;
    if (registry == null) return null;
    return registry.entries
        .where((entry) => entry.id == registry.activeId)
        .firstOrNull;
  }

  void _closeVault(String message, {NextcloudConfig? nextCloud}) {
    autosave?.cancel();
    cloudAutosave?.cancel();
    cloudPoll?.cancel();
    _loadSource('');
    setState(() {
      vault = null;
      note = null;
      index = null;
      validation = null;
      searchIndex = PkmsSearchIndex.empty();
      helperSource = tylogHelperSource;
      cloud = nextCloud;
      selectedTag = null;
      lastSync = null;
      syncConflicts = const [];
      lastSyncAt = null;
      syncError = null;
      storageHealthy = false;
      dirty = false;
      savedRevision = editRevision;
      indexedRevision = editRevision;
      lastEditAt = null;
      status = message;
    });
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
        await Vault.withStorage(active.storage).ensureCreated(
          createIfMissing: !vaultNeedsAndroidTreeMigration(active),
        );
      } on PlatformException {
        if (active.storageKind != 'android-tree') rethrow;
        final selection = await AndroidTreeVaultStorage.pick();
        if (selection == null) {
          _closeVault('Folder access is required to open this vault');
          return;
        }
        active = await registry.rebindTree(active, selection);
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
    try {
      autosave?.cancel();
      cloudAutosave?.cancel();
      cloudPoll?.cancel();
      final v = Vault.withStorage(entry.storage);
      await v.ensureCreated(
        createIfMissing: !vaultNeedsAndroidTreeMigration(entry),
      );
      // ponytail: offline-first — render local vault immediately, sync in background
      final openStatus = 'Vault: ${v.storage.displayName}';
      final today = await v.todayNote();
      final ix = await v.rebuildIndex();
      final pkms = await _readPkms(v, ix);
      final loadedHelper = await v.storage.readText(Vault.helperPath);
      final loadedBibliography = await v.storage.exists(Vault.bibliographyPath)
          ? await v.storage.readText(Vault.bibliographyPath)
          : '';
      final conflicts = await loadSyncConflicts(v);
      _loadSource(await v.storage.readText(today));
      setState(() {
        vault = v;
        note = today;
        index = _retainIndex(ix);
        validation = _retainValidation(pkms.report);
        searchIndex = pkms.search;
        helperSource = loadedHelper;
        bibliographySource = loadedBibliography;
        cloud = entry.cloud;
        selectedTag = null;
        lastSync = null;
        syncConflicts = conflicts;
        lastSyncAt = null;
        syncError = null;
        storageHealthy = null;
        savedRevision = editRevision;
        indexedRevision = editRevision;
        lastEditAt = null;
        mode = 'normal';
        status = '$openStatus · ${pkms.report.summary()}';
      });
      unawaited(taskScheduler.reconcile(ix.tasks));
      unawaited(_sweepSafBackups(v));
      if (entry.cloud != null && entry.cloud!.isReady) {
        if (trigger != null) unawaited(_syncNow(trigger: trigger));
        _startCloudPolling();
      }
    } catch (e) {
      _closeVault('Open failed: $e', nextCloud: entry.cloud);
    }
  }

  // Delete orphans of interrupted SAF atomic replaces so they never sync.
  Future<void> _sweepSafBackups(Vault v) async {
    try {
      final entries = await v.storage.list(recursive: true);
      for (final e in entries) {
        if (!e.isDirectory && isSafBackupPath(e.path)) {
          await v.storage.delete(e.path);
        }
      }
    } catch (_) {
      // Best-effort cleanup; sync filtering is the hard guarantee.
    }
  }

  Future<({PkmsValidationReport report, PkmsSearchIndex search})> _readPkms(
    Vault v,
    VaultIndex ix,
  ) async {
    final report = await validatePkmsStorage(v.storage, ix);
    final cached = await PkmsSearchIndex.loadStorage(
      v.storage,
      Vault.searchIndexPath,
    );
    final search = await PkmsSearchIndex.buildStorage(
      v.storage,
      ix,
      previous: cached,
    );
    await search.saveStorage(v.storage, Vault.searchIndexPath);
    return (report: report, search: search);
  }

  Future<void> _refreshIndex({
    bool updateStatus = true,
    bool force = false,
  }) async {
    final v = vault;
    if (v == null || (!force && indexedRevision >= savedRevision)) return;
    final revision = savedRevision;
    try {
      final ix = await v.rebuildIndex();
      final pkms = await _readPkms(v, ix);
      if (!mounted || v != vault) return;
      setState(() {
        index = _retainIndex(ix);
        validation = _retainValidation(pkms.report);
        searchIndex.replaceWith(pkms.search);
        indexedRevision = revision;
        if (updateStatus) status = 'Indexed · ${pkms.report.summary()}';
      });
      unawaited(taskScheduler.reconcile(ix.tasks));
    } catch (error) {
      if (mounted && updateStatus) {
        setState(() => status = 'Index refresh failed: $error');
      }
    }
  }

  Future<void> _ensureIndexed() async {
    if (dirty) await _save(syncAfter: false);
    await _refreshIndex();
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
      final selection = await AndroidTreeVaultStorage.pick();
      if (selection == null) return false;
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
    final path = await FilePicker.platform.getDirectoryPath(
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
    final selection = await AndroidTreeVaultStorage.pick();
    if (selection == null) return false;
    try {
      final migrated = await vaultRegistry!.migrateToTree(entry, selection);
      await vaultRegistry!.select(migrated);
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

  Future<void> _forgetVault(VaultEntry entry) async {
    final registry = vaultRegistry!;
    try {
      if (entry.id == registry.activeId && registry.entries.length > 1) {
        await _switchVault(
          registry.entries.firstWhere((item) => item.id != entry.id),
        );
      }
      await registry.forget(entry);
      if (registry.entries.isEmpty) {
        _closeVault('Forgot ${entry.name}; add a vault to continue');
        return;
      }
      if (mounted) setState(() => status = 'Forgot ${entry.name}; files kept');
    } catch (e) {
      if (mounted) setState(() => status = 'Forget failed: $e');
    }
  }

  Future<void> _deleteVault(VaultEntry entry) async {
    final warned = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete vault and files?'),
        content: Text(
          'This permanently deletes all notes, pages, assets, metadata, and sync state in ${entry.name}. There is no recovery.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (warned != true || !mounted) return;
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
    typed.dispose();
    if (confirmed != true) return;

    autosave?.cancel();
    cloudAutosave?.cancel();
    cloudPoll?.cancel();
    try {
      final registry = vaultRegistry!;
      final wasActive = registry.activeId == entry.id;
      await registry.delete(entry);
      if (shouldCreateDefaultReplacementVault(
        entriesEmpty: registry.entries.isEmpty,
      )) {
        final replacement = await Vault.openDefault();
        final replacementEntry = await registry.add(replacement.root.path);
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
        setState(() => status = 'Delete failed; vault kept: $e');
      }
    }
  }

  Future<void> _save({bool syncAfter = true}) async {
    autosave?.cancel();
    final v = vault;
    final n = note;
    if (v == null || n == null) return;
    final revision = editRevision;
    final source = _currentSource();
    try {
      await v.saveNote(n, source);
      final editorUnchanged = revision == editRevision && n == note;
      if (editorUnchanged) {
        setState(() {
          savedRevision = revision;
          dirty = false;
          status = 'Saved ${v.relativePath(n)}';
        });
      }
      if (syncAfter && editorUnchanged) _queueCloudSync();
    } catch (e) {
      if (revision == editRevision && n == note) {
        setState(() => status = 'Save failed: $e');
      }
    }
  }

  void _queueCloudSync() {
    cloudAutosave?.cancel();
    final edited = lastEditAt;
    final elapsed = edited == null
        ? Duration.zero
        : DateTime.now().difference(edited);
    final remaining = const Duration(seconds: 10) - elapsed;
    cloudAutosave = Timer(
      remaining.isNegative ? Duration.zero : remaining,
      _runIdleMaintenance,
    );
  }

  Future<void> _runIdleMaintenance() async {
    if (!mounted) return;
    if (dirty || richController.isComposing) return;
    if (_editingRecently) {
      _queueCloudSync();
      return;
    }
    if (syncing) {
      cloudAutosave = Timer(const Duration(seconds: 1), _runIdleMaintenance);
      return;
    }
    final cfg = cloud;
    if (cfg != null && cfg.isReady && !_hasSyncConflicts) {
      await _syncNow(trigger: 'autosave');
      return;
    }
    await _refreshIndex();
  }

  void _startCloudPolling() {
    cloudPoll?.cancel();
    final cfg = cloud;
    if (cfg == null || !cfg.isReady) return;
    cloudPoll = Timer.periodic(const Duration(seconds: 25), (_) {
      if (!syncing && !_editingRecently && !_hasSyncConflicts && mounted) {
        unawaited(_syncNow(trigger: 'poll'));
      }
    });
  }

  bool get _hasSyncConflicts => syncConflicts.isNotEmpty;

  bool get _editingRecently {
    if (dirty || richController.isComposing) return true;
    final edited = lastEditAt;
    return edited != null &&
        DateTime.now().difference(edited) < const Duration(seconds: 10);
  }

  void _queueAutosave() {
    editRevision++;
    lastEditAt = DateTime.now();
    final becameDirty = !dirty;
    dirty = true;
    if (becameDirty) setState(() => status = 'Autosave pending...');
    autosave?.cancel();
    autosave = Timer(const Duration(milliseconds: 700), _save);
  }

  String _currentSource() => sourceController.text;

  FileSource _typstFiles() => FileSource.bytes({
    '_system/tylog.typ': Uint8List.fromList(utf8.encode(helperSource)),
    '/_system/tylog.typ': Uint8List.fromList(utf8.encode(helperSource)),
    '_system/theme.typ': Uint8List.fromList(utf8.encode(tylogThemeSource)),
    '/_system/theme.typ': Uint8List.fromList(utf8.encode(tylogThemeSource)),
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
    input.dispose();
    if (updated != null) richController.replaceProtected(id, updated);
  }

  Future<void> _openNote(String path) async {
    final v = vault;
    if (v == null) return;
    if (dirty) await _save();
    final source = await v.storage.readText(path);
    _loadSource(source);
    setState(() {
      note = path;
      dirty = false;
      savedRevision = editRevision;
      mode = 'normal';
      status = 'Opened $path';
    });
  }

  Future<void> _openToday() async {
    final v = vault;
    if (v == null) return;
    await _openNote(await v.todayNote());
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
                vault == null || note == null
                    ? null
                    : vault!.relativePath(note!),
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
    final ix = await v.rebuildIndex();
    await _openNote(file);
    setState(() {
      index = ix;
      status = 'Created ${v.relativePath(file)}';
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
    final path = v.relativePath(n);
    final current = ix.notesByPath[path];
    if (current == null) return;
    if (current.metadataSource != 'typst-query') {
      final convert = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Convert metadata header?'),
          content: const Text(
            'This legacy or dynamic header could not be verified by Typst. Saving will replace only the metadata call with a canonical literal header; the note body is preserved.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Convert'),
            ),
          ],
        ),
      );
      if (convert != true) return;
      if (!mounted) return;
    }
    final title = TextEditingController(text: current.title);
    final tagsText = TextEditingController(text: current.tags.join(', '));
    final aliases = TextEditingController(text: current.aliases.join(', '));
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
      final updated = replaceNoteHeader(
        _currentSource(),
        NoteMetadataDraft(
          id: current.id,
          title: title.text.trim(),
          kind: current.kind,
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
    for (final value in [title, tagsText, aliases]) {
      value.dispose();
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
          onSetTaskStatus: _setTaskStatus,
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

  PkmsValidationReport _retainValidation(PkmsValidationReport next) {
    final current = validation;
    if (current == null) return next;
    current.problems
      ..clear()
      ..addAll(next.problems);
    return current;
  }

  VaultIndex _retainIndex(VaultIndex next) {
    final current = index;
    if (current == null || current.version != next.version) return next;
    current.notesByPath
      ..clear()
      ..addAll(next.notesByPath);
    current.backlinksByTarget
      ..clear()
      ..addAll(next.backlinksByTarget);
    current.attachmentBacklinksByPath
      ..clear()
      ..addAll(next.attachmentBacklinksByPath);
    current.problems
      ..clear()
      ..addAll(next.problems);
    current.tasks
      ..clear()
      ..addAll(next.tasks);
    return current;
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
    final v = vault;
    if (v == null) return;
    if (rebuilding) {
      cancelRebuild = true;
      return;
    }
    setState(() {
      rebuilding = true;
      cancelRebuild = false;
      rebuildProgress = 0;
      status = 'Rebuilding index...';
    });
    try {
      final ix = await v.rebuildIndex(
        force: true,
        isCancelled: () => cancelRebuild,
        onProgress: (complete, total) {
          if (!mounted || (complete % 100 != 0 && complete != total)) return;
          setState(() {
            rebuildProgress = total == 0 ? 1 : complete / total;
            status = 'Rebuilding index: $complete / $total';
          });
        },
      );
      final pkms = await _readPkms(v, ix);
      if (!mounted) return;
      setState(() {
        index = _retainIndex(ix);
        validation = _retainValidation(pkms.report);
        searchIndex.replaceWith(pkms.search);
        indexedRevision = savedRevision;
        status = 'Index rebuilt · ${pkms.report.summary()}';
      });
      unawaited(taskScheduler.reconcile(ix.tasks));
    } on IndexBuildCancelled {
      if (mounted) setState(() => status = 'Index rebuild cancelled');
    } finally {
      if (mounted) {
        setState(() {
          rebuilding = false;
          rebuildProgress = null;
        });
      }
    }
  }

  Future<void> _syncNow({String trigger = 'manual'}) async {
    final v = vault;
    final cfg = cloud;
    if (v == null) return;
    if (cfg == null || !cfg.isReady) {
      await _showSyncSettings();
      return;
    }
    if (syncing) return;
    if (v.localRoot case final root? when isNextcloudManagedVault(root)) {
      setState(() => status = 'Sync handled by Nextcloud Desktop');
      return;
    }
    setState(() {
      syncing = true;
      syncError = null;
      status = 'Syncing…';
    });
    try {
      cloudAutosave?.cancel();
      if (dirty) {
        await _save(syncAfter: false);
        if (dirty) return;
      }
      final syncedNote = note;
      final sourceBeforeSync = syncedNote == null ? null : _currentSource();
      final revisionBeforeSync = editRevision;
      final result = await NextcloudSync(
        cfg,
        onProgress: (stage, path) {
          if (!mounted) return;
          setState(() => syncStage = path == null ? stage : '$stage · $path');
        },
        canReplaceLocal: (path) =>
            path != syncedNote ||
            (revisionBeforeSync == editRevision && !dirty),
      ).sync(v, trigger: trigger);
      var concurrentConflict = false;
      if (syncedNote != null && syncedNote == note) {
        final diskExists = await v.storage.exists(syncedNote);
        final diskSource = diskExists
            ? await v.storage.readText(syncedNote)
            : null;
        final editorChanged = revisionBeforeSync != editRevision || dirty;
        if (editorChanged && diskSource != sourceBeforeSync) {
          final editorSource = _currentSource();
          await createSyncConflict(
            v,
            syncedNote,
            localBytes: utf8.encode(editorSource),
            remoteBytes: diskSource == null ? null : utf8.encode(diskSource),
          );
          // The conflict snapshots both outcomes; keep the live editor version
          // authoritative on disk so a sync race can never erase keystrokes.
          await v.saveNote(syncedNote, editorSource);
          concurrentConflict = true;
        } else if (!editorChanged && diskSource != sourceBeforeSync) {
          if (diskSource != null) _loadSource(diskSource);
        }
      }
      final indexedThroughRevision = savedRevision;
      final ix = await v.rebuildIndex();
      final pkms = await _readPkms(v, ix);
      final conflicts = await loadSyncConflicts(v);
      setState(() {
        index = _retainIndex(ix);
        validation = _retainValidation(pkms.report);
        searchIndex.replaceWith(pkms.search);
        indexedRevision = indexedThroughRevision;
        lastSync = result;
        lastSyncAt = DateTime.now();
        syncConflicts = conflicts;
        final changed =
            result.uploaded +
            result.downloaded +
            result.deletedLocal +
            result.deletedRemote +
            result.repaired;
        status = conflicts.isNotEmpty || concurrentConflict
            ? 'Needs attention'
            : changed == 0
            ? 'Up to date'
            : 'Synced';
      });
    } on SyncDeferred {
      if (mounted) setState(() => status = 'Sync deferred while editing');
      _queueCloudSync();
    } catch (e, stack) {
      debugPrintStack(label: 'Nextcloud sync failed: $e', stackTrace: stack);
      final conflicts = await loadSyncConflicts(v);
      await _refreshIndex(updateStatus: false, force: true);
      if (mounted) {
        setState(() {
          syncConflicts = conflicts;
          syncError = conflicts.isEmpty ? _friendlySyncError(e) : null;
          status = conflicts.isEmpty ? syncError! : 'Needs attention';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          syncing = false;
          syncStage = null;
        });
      }
    }
    if (!mounted) return;
  }

  Future<bool> _showSyncSettings() async {
    final vaultId = vaultRegistry!.activeId;
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
    var draftWrites = Future<void>.value();
    NextcloudConfig draft() => NextcloudConfig(
      serverUrl: url.text,
      username: user.text,
      password: pass.text,
      remoteFolder: folder.text,
    );

    void remember(StateSetter refresh) {
      refresh(() {});
      final snapshot = draft();
      draftWrites = draftWrites
          .then((_) => snapshot.save(vaultId: vaultId))
          .catchError((_) {});
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
                    onChanged: (_) => remember(setDialogState),
                    decoration: const InputDecoration(
                      labelText: 'Server URL',
                      hintText: 'https://cloud.example.com',
                    ),
                  ),
                  TextField(
                    controller: user,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.username],
                    onChanged: (_) => remember(setDialogState),
                    decoration: const InputDecoration(labelText: 'Login'),
                  ),
                  TextField(
                    controller: pass,
                    obscureText: true,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.password],
                    onChanged: (_) => remember(setDialogState),
                    decoration: const InputDecoration(
                      labelText: 'Password or app password',
                    ),
                  ),
                  TextField(
                    controller: folder,
                    textInputAction: TextInputAction.done,
                    onChanged: (_) => remember(setDialogState),
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
              child: const Text('Save and connect'),
            ),
          ],
        ),
      ),
    );
    await draftWrites;
    url.dispose();
    user.dispose();
    pass.dispose();
    folder.dispose();
    if (saved == null) return false;
    if (!mounted) return false;
    await saved.save(vaultId: vaultId);
    final registry = vaultRegistry!;
    await registry.setCloud(registry.active, saved);
    setState(() {
      cloud = saved;
      status = 'Nextcloud saved';
    });
    _startCloudPolling();
    unawaited(_syncNow(trigger: 'settings'));
    return true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      // Android may kill the app inside the 700 ms autosave debounce; flush
      // pending edits now so backgrounding never loses keystrokes.
      if (dirty) unawaited(_save(syncAfter: false));
      return;
    }
    if (state == AppLifecycleState.resumed && (cloud?.isReady ?? false)) {
      if (_editingRecently) {
        _queueCloudSync();
      } else {
        unawaited(_syncNow(trigger: 'resume'));
      }
    }
  }

  void _showSettings() {
    final v = vault;
    final registry = vaultRegistry;
    final activeLocation = vaultEntryLocation(_activeRegistryEntry);
    final openError = status.startsWith('Open failed:');
    final vaultPath =
        v?.storage.location ??
        (openError
            ? [activeLocation, status].whereType<String>().join('\n')
            : activeLocation ?? status);
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: _SettingsSheet(
            vaultPath: vaultPath,
            cloud: cloud,
            syncing: syncing,
            vaults: registry?.entries ?? const [],
            activeVaultId: registry?.activeId,
            onAddVault: () => unawaited(_pickVault()),
            onSwitchVault: (entry) {
              Navigator.pop(context);
              unawaited(_switchVault(entry));
            },
            onForgetVault: (entry) {
              Navigator.pop(context);
              unawaited(_forgetVault(entry));
            },
            onDeleteVault: (entry) {
              Navigator.pop(context);
              unawaited(_deleteVault(entry));
            },
            onNextcloud: () {
              Navigator.pop(context);
              unawaited(_showSyncDashboard());
            },
            onEnableReminders: () async {
              await taskScheduler.requestPermission();
              await taskScheduler.reconcile(index?.tasks ?? const []);
              if (mounted) setState(() => status = 'Task reminders enabled');
            },
          ),
        ),
      ),
    );
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
    if (v.storage is AndroidTreeVaultStorage) {
      try {
        await v.storage.open(path);
      } catch (error) {
        if (mounted) setState(() => status = 'Could not open file: $error');
      }
      return;
    }
    final result = await OpenFile.open('${v.localRoot!.path}/$path');
    if (result.type != ResultType.done && mounted) {
      setState(() => status = 'Could not open file: ${result.message}');
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

  void _showPreview() {
    setState(() => mode = 'preview');
  }

  void _showJournal() {
    if (mode == 'source' || mode == 'split') {
      richController.loadSource(sourceController.text);
    }
    setState(() => mode = 'normal');
  }

  void _showToday() {
    if (!dirty) setState(() => mode = 'today');
  }

  void _showSource() => setState(() => mode = 'source');

  void _cycleEditorMode() {
    switch (mode) {
      case 'preview':
        _showSource();
      case 'source':
        _showJournal();
      default:
        _showPreview();
    }
  }

  Future<void> _showSyncDashboard() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => _SyncDashboardScreen(
          load: _loadSyncDashboard,
          onSync: () => _syncNow(),
          onConfigure: _showSyncSettings,
          onResolve: _resolveSyncConflict,
          onCopyDiagnostics: _copySyncDiagnostics,
        ),
      ),
    );
  }

  Future<_SyncDashboardData> _loadSyncDashboard() async {
    final v = vault;
    if (v == null) {
      final active = _activeRegistryEntry;
      final error = syncError ?? (status == 'Opening vault...' ? null : status);
      return _SyncDashboardData(
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
    final healthy = storageHealthy ??= await _probeStorage(v.storage);
    return _SyncDashboardData(
      storageName: v.storage.displayName,
      storageLocation: v.storage.location,
      backupPath: entry.backupPath,
      cloud: cloud,
      syncing: syncing,
      stage: syncStage,
      error: syncError,
      result: lastSync,
      lastSyncAt: lastSyncAt,
      vaultOpen: true,
      desktopManaged:
          v.localRoot != null && isNextcloudManagedVault(v.localRoot!),
      storageHealthy: healthy,
      conflicts: await loadSyncConflicts(v),
      events: events.reversed.toList(),
    );
  }

  Future<bool> _probeStorage(VaultStorage storage) async {
    const path = '.tylog/.storage-health';
    try {
      await storage.writeText(path, 'ok');
      final valid = await storage.readText(path) == 'ok';
      await storage.delete(path);
      return valid;
    } catch (_) {
      try {
        await storage.delete(path);
      } catch (_) {}
      return false;
    }
  }

  Future<void> _resolveSyncConflict(SyncConflict conflict) async {
    final v = vault;
    final cfg = cloud;
    if (v == null || cfg == null || !cfg.isReady) return;
    final localBytes = conflict.localSnapshot == null
        ? null
        : await v.storage.readBytes(conflict.localSnapshot!);
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
                              conflict.localExists
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
        await NextcloudSync(cfg).resolveConflict(
          v,
          conflict,
          selected.value,
          mergedText: selected.value == SyncConflictResolution.merge
              ? merged.text
              : null,
        );
        final ix = await v.rebuildIndex();
        final pkms = await _readPkms(v, ix);
        if (mounted) {
          setState(() {
            index = _retainIndex(ix);
            validation = _retainValidation(pkms.report);
            searchIndex.replaceWith(pkms.search);
            syncConflicts = syncConflicts
                .where((item) => item.id != conflict.id)
                .toList();
            status = 'Conflict resolved';
          });
        }
      } catch (error) {
        if (mounted) setState(() => syncError = _friendlySyncError(error));
      }
    }
    selected.dispose();
    merged.dispose();
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Sync diagnostics copied')));
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
    input.dispose();
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

  Future<NoteRef?> _chooseNote({String? kind, bool create = false}) async {
    final notes = (index?.notes ?? const <NoteRef>[])
        .where((note) => kind == null || note.kind == kind)
        .toList();
    final chosen = await showModalBottomSheet<NoteRef>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            if (create)
              ListTile(
                leading: const Icon(Icons.add),
                title: Text('Create ${kind ?? 'note'}'),
                onTap: () => Navigator.pop(context),
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
    if (chosen != null || !create) return chosen;
    final title = await _askText(
      'New ${kind ?? 'note'}',
      initialValue: _selectedText(),
    );
    if (title == null || title.isEmpty || vault == null) return null;
    final file = await vault!.page(title, kind: kind ?? 'note');
    final rebuilt = await vault!.rebuildIndex();
    setState(() => index = _retainIndex(rebuilt));
    return rebuilt.notesByPath[vault!.relativePath(file)];
  }

  Future<void> _runMagic(MagicAction action) async {
    switch (action) {
      case MagicAction.bold:
      case MagicAction.italic:
      case MagicAction.heading:
      case MagicAction.equation:
        _applyMagic(MagicRequest(action: action));
        return;
      case MagicAction.table:
        _applyMagic(const MagicRequest(action: MagicAction.table));
        return;
      case MagicAction.noteLink:
        final target = await _chooseNote(create: true);
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
        );
        _applyMagic(
          MagicRequest(
            action: action,
            id: 'task-${DateTime.now().microsecondsSinceEpoch}',
            value: text,
            due: due == null ? null : _isoDay(due),
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
          _applyMagic(MagicRequest(action: action, value: _isoDay(date)));
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
    return index?.notesByPath[v.relativePath(file)];
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

  Future<String?> _chooseCitation() async {
    final v = vault;
    if (v == null || !await v.storage.exists(Vault.bibliographyPath)) {
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
    final picked = await FilePicker.platform.pickFiles();
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
    await v.storage.importFile(target, source);
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
    final project = await _chooseNote(kind: 'project');
    if (!mounted) return;
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
    );
    final report = await writeReportStorage(
      v.storage,
      title,
      ix,
      ReportFilter(
        project: project?.id,
        from: range == null ? null : _isoDay(range.start),
        to: range == null ? null : _isoDay(range.end),
      ),
    );
    final pdf = await exportReportPdfStorage(v.storage, report);
    if (mounted) {
      setState(() => status = 'Created $report and $pdf');
      _queueCloudSync();
    }
  }

  Future<void> _showMagicMenu() async {
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
              for (final entry in const <MagicAction, (IconData, String)>{
                MagicAction.noteLink: (Icons.link, 'Note link'),
                MagicAction.tag: (Icons.tag, 'Tag'),
                MagicAction.task: (Icons.task_alt, 'Task'),
                MagicAction.date: (Icons.event, 'Date'),
                MagicAction.project: (Icons.work_outline, 'Project'),
                MagicAction.citation: (Icons.format_quote, 'Citation'),
                MagicAction.attachment: (Icons.attach_file, 'Attachment'),
                MagicAction.heading: (Icons.title, 'Heading'),
                MagicAction.bold: (Icons.format_bold, 'Bold'),
                MagicAction.italic: (Icons.format_italic, 'Italic'),
                MagicAction.table: (Icons.table_chart, 'Table'),
                MagicAction.equation: (Icons.functions, 'Equation'),
                MagicAction.report: (Icons.picture_as_pdf, 'Report'),
              }.entries)
                InkWell(
                  onTap: () => Navigator.pop(context, entry.key),
                  child: Semantics(
                    button: true,
                    label: entry.value.$2,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
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
    if (action != null) await _runMagic(action);
  }

  int get _destination => switch (mode) {
    'today' => 0,
    'tasks' => 2,
    'library' => 3,
    _ => 1,
  };

  Future<void> _showTasks() async {
    await _ensureIndexed();
    if (mounted && !dirty) setState(() => mode = 'tasks');
  }

  void _selectDestination(int destination) {
    switch (destination) {
      case 0:
        _showToday();
        return;
      case 1:
        _showJournal();
        return;
      case 2:
        unawaited(_showTasks());
        return;
      case 3:
        setState(() => mode = 'library');
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = vault;
    final current = v == null || note == null ? null : v.relativePath(note!);
    final currentTitle = _currentTitle(current);
    final backlinks = current == null
        ? const <String>[]
        : index?.backlinksByTarget[current] ?? const <String>[];
    final outgoing = current == null
        ? const <String>[]
        : index?.notesByPath[current]?.outgoingLinks ?? const <String>[];
    final resolver = index == null ? null : LinkResolver(index!.notes);
    final graph = index == null ? null : buildLocalNoteGraph(index!, current);
    final syncConflictCount = syncConflicts.length;
    final desktopManaged =
        v?.localRoot != null && isNextcloudManagedVault(v!.localRoot!);
    final currentDaily = _dailyDateOf(current);
    final dayItems = currentDaily == null
        ? const <CalendarItem>[]
        : (index?.calendar ?? const <CalendarItem>[])
              .where(
                (item) =>
                    item.date == _isoDay(currentDaily) &&
                    item.notePath != current,
              )
              .toList();
    final linksPanel = _LinksPanel(
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
    final journalMode = const {'normal', 'preview', 'source', 'split'};
    final workArea = _WorkSurface(
      child: switch (mode) {
        'today' => _TodayView(
          index: index,
          onOpenToday: _openToday,
          onOpenPath: _openPath,
        ),
        'tasks' => _PrimaryTasksView(
          tasks: index?.tasks ?? const [],
          onOpenPath: _openPath,
          onSetStatus: _setTaskStatus,
        ),
        'library' => _LibraryView(
          index: index,
          onOpenPath: _openPath,
          onOpenDay: (day) => unawaited(_openDay(day)),
        ),
        'graph' => GraphView(
          graph: graph ?? const NoteGraph(nodes: [], edges: []),
          currentPath: current,
          onOpenPath: _openPath,
        ),
        'preview' => TypstDocumentViewer(
          source: _previewSource(),
          files: _typstFiles(),
          loadingBuilder: (_) =>
              const Center(child: CircularProgressIndicator()),
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
        'source' => _Editor(
          controller: sourceController,
          onChanged: _queueAutosave,
          monospace: true,
        ),
        'split' => Row(
          children: [
            Expanded(
              child: _Editor(
                controller: sourceController,
                onChanged: _queueAutosave,
                monospace: true,
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: TypstDocumentViewer(
                source: _previewSource(),
                files: _typstFiles(),
              ),
            ),
          ],
        ),
        'normal' => TyLogRichEditor(
          controller: richController,
          onInsert: _showMagicMenu,
        ),
        _ => const SizedBox.shrink(),
      },
    );

    final wideNavigation = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      appBar: AppBar(
        leading: PopupMenuButton<String>(
          tooltip: 'Vaults',
          icon: const Icon(Icons.folder_outlined),
          onSelected: (id) {
            if (id == 'settings') {
              _showSettings();
              return;
            }
            final entries = vaultRegistry?.entries ?? const <VaultEntry>[];
            for (final entry in entries) {
              if (entry.id == id) unawaited(_switchVault(entry));
            }
          },
          itemBuilder: (_) => [
            for (final entry in vaultRegistry?.entries ?? const <VaultEntry>[])
              PopupMenuItem(
                value: entry.id,
                child: Row(
                  children: [
                    Icon(
                      entry.id == vaultRegistry?.activeId
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(entry.name)),
                  ],
                ),
              ),
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: 'settings',
              child: Text('Manage vaults'),
            ),
          ],
        ),
        titleSpacing: 0,
        title: journalMode.contains(mode) && currentDaily != null
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
                          child: Text(
                            dirty
                                ? '${humanDate(currentDaily)} •'
                                : humanDate(currentDaily),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
            : Text(
                dirty ? '$currentTitle •' : currentTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
        actions: [
          IconButton(
            onPressed: _showKnowledge,
            icon: const Icon(Icons.search),
            tooltip: 'Search knowledge',
          ),
          IconButton(
            onPressed: _cycleEditorMode,
            icon: Icon(switch (mode) {
              'preview' => Icons.code,
              'source' => Icons.visibility_off,
              _ => Icons.visibility,
            }),
            tooltip: switch (mode) {
              'preview' => 'Source',
              'source' => 'Editor',
              _ => 'Preview',
            },
          ),
          _SyncIconButton(
            syncing: syncing,
            vaultOpen: v != null,
            storageHealthy: storageHealthy ?? true,
            configured: cloud?.isReady ?? false,
            desktopManaged: desktopManaged,
            error: syncError,
            conflicts: syncConflictCount,
            result: lastSync,
            onPressed: _showSyncDashboard,
          ),
          PopupMenuButton<_ShellAction>(
            tooltip: 'More actions',
            onSelected: (action) {
              switch (action) {
                case _ShellAction.today:
                  _showToday();
                case _ShellAction.newPage:
                  unawaited(_newPage());
                case _ShellAction.graph:
                  mode == 'graph'
                      ? _showJournal()
                      : setState(() => mode = 'graph');
                case _ShellAction.split:
                  sourceController.text = _currentSource();
                  setState(() => mode = 'split');
                case _ShellAction.backlinks:
                  showDialog<void>(
                    context: context,
                    builder: (_) => Dialog.fullscreen(
                      child: Scaffold(
                        appBar: AppBar(title: const Text('Context')),
                        body: SafeArea(child: linksPanel),
                      ),
                    ),
                  );
                case _ShellAction.rebuild:
                  unawaited(_rebuildIndex());
                case _ShellAction.settings:
                  _showSettings();
                case _ShellAction.typstHelp:
                  unawaited(_showTypstHelp());
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: _ShellAction.today,
                child: Text('Today'),
              ),
              const PopupMenuItem(
                value: _ShellAction.newPage,
                child: Text('New page'),
              ),
              PopupMenuItem(
                value: _ShellAction.graph,
                child: Text(mode == 'graph' ? 'Journal' : 'Graph'),
              ),
              const PopupMenuItem(
                value: _ShellAction.split,
                child: Text('Split editor'),
              ),
              const PopupMenuItem(
                value: _ShellAction.backlinks,
                child: Text('Backlinks and files'),
              ),
              const PopupMenuItem(
                value: _ShellAction.rebuild,
                child: Text('Rebuild index'),
              ),
              const PopupMenuItem(
                value: _ShellAction.typstHelp,
                child: Text('Typst help'),
              ),
              const PopupMenuItem(
                value: _ShellAction.settings,
                child: Text('Settings'),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton:
          _destination == 1 && (mode == 'source' || mode == 'split')
          ? FloatingActionButton.extended(
              onPressed: _showMagicMenu,
              icon: const Icon(Icons.auto_fix_high),
              label: const Text('Magic'),
            )
          : null,
      bottomNavigationBar: wideNavigation
          ? null
          : NavigationBar(
              selectedIndex: _destination,
              onDestinationSelected: _selectDestination,
              destinations: const [
                NavigationDestination(icon: Icon(Icons.today), label: 'Today'),
                NavigationDestination(
                  icon: Icon(Icons.edit_note),
                  label: 'Journal',
                ),
                NavigationDestination(
                  icon: Icon(Icons.task_alt),
                  label: 'Tasks',
                ),
                NavigationDestination(
                  icon: Icon(Icons.library_books),
                  label: 'Library',
                ),
              ],
            ),
      body: wideNavigation
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: _destination,
                  onDestinationSelected: _selectDestination,
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
                      icon: Icon(Icons.task_alt),
                      label: Text('Tasks'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.library_books),
                      label: Text('Library'),
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
  today,
  newPage,
  graph,
  split,
  backlinks,
  rebuild,
  typstHelp,
  settings,
}

String _friendlySyncError(Object error) {
  if (error is SocketException || error is TimeoutException) {
    return 'Nextcloud is unreachable. Your changes are safe on this device.';
  }
  if (error is HandshakeException) {
    return 'Nextcloud security certificate could not be verified.';
  }
  if (error is FileSystemException) {
    return 'TyLog could not update the local vault: ${error.osError?.message ?? error.message}';
  }
  if (error is FormatException) {
    return 'Sync data could not be read.';
  }
  final text = error.toString();
  if (text.contains('401') || text.contains('403')) {
    return 'Nextcloud rejected the login. Check Sync settings.';
  }
  if (text.contains('404')) {
    return 'The configured Nextcloud folder was not found.';
  }
  if (text.contains('PROPFIND invalid file metadata')) {
    return 'Nextcloud returned invalid file metadata.';
  }
  if (text.contains('507')) return 'Nextcloud is out of storage space.';
  return 'Sync stopped before completion: $text';
}

class _SyncDashboardData {
  const _SyncDashboardData({
    required this.storageName,
    required this.storageLocation,
    required this.cloud,
    required this.syncing,
    required this.vaultOpen,
    required this.desktopManaged,
    required this.storageHealthy,
    required this.conflicts,
    required this.events,
    this.backupPath,
    this.stage,
    this.error,
    this.result,
    this.lastSyncAt,
  });

  final String storageName;
  final String storageLocation;
  final String? backupPath;
  final String? stage;
  final NextcloudConfig? cloud;
  final bool syncing;
  final bool vaultOpen;
  final bool desktopManaged;
  final bool storageHealthy;
  final String? error;
  final SyncResult? result;
  final DateTime? lastSyncAt;
  final List<SyncConflict> conflicts;
  final List<Map<String, Object?>> events;
}

class _SyncDashboardScreen extends StatefulWidget {
  const _SyncDashboardScreen({
    required this.load,
    required this.onSync,
    required this.onConfigure,
    required this.onResolve,
    required this.onCopyDiagnostics,
  });

  final Future<_SyncDashboardData> Function() load;
  final Future<void> Function() onSync;
  final Future<bool> Function() onConfigure;
  final Future<void> Function(SyncConflict) onResolve;
  final Future<void> Function() onCopyDiagnostics;

  @override
  State<_SyncDashboardScreen> createState() => _SyncDashboardScreenState();
}

class _SyncDashboardScreenState extends State<_SyncDashboardScreen> {
  _SyncDashboardData? data;
  Object? loadError;
  bool running = false;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    try {
      final loaded = await widget.load();
      if (mounted) setState(() => data = loaded);
    } catch (error) {
      if (mounted) setState(() => loadError = error);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => running = true);
    final refresh = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => unawaited(_reload()),
    );
    try {
      await action();
    } finally {
      refresh.cancel();
      await _reload();
      if (mounted) setState(() => running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = data;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync'),
        actions: [
          IconButton(
            tooltip: 'Configure Nextcloud',
            onPressed: () => _run(() async {
              await widget.onConfigure();
            }),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: value == null
          ? Center(
              child: loadError == null
                  ? const CircularProgressIndicator()
                  : Text('Could not load sync dashboard: $loadError'),
            )
          : RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if ((running || value.syncing) && value.stage != null) ...[
                    LinearProgressIndicator(semanticsLabel: 'Sync progress'),
                    const SizedBox(height: 8),
                    Text(value.stage!),
                    const SizedBox(height: 12),
                  ],
                  _SyncStatusCard(
                    syncing: running || value.syncing,
                    vaultOpen: value.vaultOpen,
                    storageHealthy: value.storageHealthy,
                    cloudConfigured: value.cloud?.isReady ?? false,
                    desktopManaged: value.desktopManaged,
                    result: value.result,
                    lastSyncAt: value.lastSyncAt,
                    error: value.error,
                    conflicts: value.conflicts.length,
                    onSync:
                        running ||
                            value.syncing ||
                            !value.vaultOpen ||
                            !value.storageHealthy ||
                            value.conflicts.isNotEmpty
                        ? null
                        : () => unawaited(_run(widget.onSync)),
                    onReview: value.conflicts.isEmpty
                        ? () {}
                        : () => unawaited(
                            _run(() => widget.onResolve(value.conflicts.first)),
                          ),
                    onSetup: () => unawaited(
                      _run(() async {
                        await widget.onConfigure();
                      }),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.folder_open),
                      title: Text(value.storageName),
                      subtitle: Text(
                        [
                          value.storageLocation,
                          value.storageHealthy
                              ? 'Permission and safe writes verified'
                              : 'Folder access or safe writes unavailable',
                          if (value.backupPath != null)
                            'Recovery backup: ${value.backupPath}',
                        ].join('\n'),
                      ),
                      isThreeLine: true,
                    ),
                  ),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.cloud_outlined),
                      title: Text(
                        value.cloud?.isReady ?? false
                            ? value.cloud!.serverUrl
                            : 'Nextcloud not configured',
                      ),
                      subtitle: value.cloud?.isReady ?? false
                          ? Text(
                              '${value.cloud!.username} · ${value.cloud!.remoteFolder}',
                            )
                          : const Text(
                              'Local folder remains available offline.',
                            ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _run(() async {
                        await widget.onConfigure();
                      }),
                    ),
                  ),
                  if (value.conflicts.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Conflicts',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    for (final conflict in value.conflicts)
                      Card(
                        color: Theme.of(context).colorScheme.errorContainer,
                        child: ListTile(
                          leading: const Icon(Icons.warning_amber_rounded),
                          title: Text(conflict.path),
                          subtitle: Text(
                            conflict.localExists && conflict.remoteExists
                                ? 'Both copies changed'
                                : conflict.localExists
                                ? 'Nextcloud deleted; this device changed'
                                : 'This device deleted; Nextcloud changed',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _run(() => widget.onResolve(conflict)),
                        ),
                      ),
                  ],
                  if (value.result != null) ...[
                    const SizedBox(height: 16),
                    _SyncDistribution(result: value.result!),
                  ],
                  const SizedBox(height: 20),
                  Text(
                    'Diagnostics log',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (value.events.isEmpty)
                    const ListTile(title: Text('No sync events recorded')),
                  for (final event in value.events)
                    ExpansionTile(
                      title: Text(
                        '${event['event'] ?? 'event'} · ${event['trigger'] ?? 'unknown'}',
                      ),
                      subtitle: Text(event['timestamp']?.toString() ?? ''),
                      children: [
                        if (event['stage'] != null)
                          ListTile(
                            title: Text('Stage: ${event['stage']}'),
                            subtitle: event['path'] == null
                                ? null
                                : Text(event['path'].toString()),
                          ),
                        if (event['errorMessage'] != null)
                          ListTile(
                            leading: const Icon(Icons.error_outline),
                            title: Text(event['errorMessage'].toString()),
                          ),
                        for (final decision
                            in event['decisions'] is List
                                ? event['decisions']! as List
                                : const [])
                          ListTile(
                            dense: true,
                            title: Text((decision as Map)['path'].toString()),
                            subtitle: Text(
                              '${decision['action']} · ${decision['reason']}',
                            ),
                          ),
                      ],
                    ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: widget.onCopyDiagnostics,
                    icon: const Icon(Icons.copy_all_outlined),
                    label: const Text('Copy diagnostics'),
                  ),
                ],
              ),
            ),
    );
  }
}

class _SyncIconButton extends StatelessWidget {
  const _SyncIconButton({
    required this.syncing,
    required this.vaultOpen,
    required this.storageHealthy,
    required this.configured,
    required this.desktopManaged,
    required this.error,
    required this.conflicts,
    required this.result,
    required this.onPressed,
  });

  final bool syncing;
  final bool vaultOpen;
  final bool storageHealthy;
  final bool configured;
  final bool desktopManaged;
  final String? error;
  final int conflicts;
  final SyncResult? result;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final kind = syncStatusKind(
      vaultOpen: vaultOpen,
      storageHealthy: storageHealthy,
      cloudConfigured: configured,
      desktopManaged: desktopManaged,
      syncing: syncing,
      error: error,
      conflicts: conflicts,
      result: result,
    );
    final label = syncStatusTitle(kind, conflicts: conflicts);
    final icon = switch (kind) {
      SyncStatusKind.vaultClosed => Icons.folder_open,
      SyncStatusKind.storageUnavailable => Icons.cloud_off_outlined,
      SyncStatusKind.desktopManaged => Icons.cloud_done_outlined,
      SyncStatusKind.notConfigured => Icons.cloud_off_outlined,
      SyncStatusKind.syncing => Icons.sync,
      SyncStatusKind.paused => Icons.cloud_off_outlined,
      SyncStatusKind.conflicts => Icons.warning_amber_rounded,
      SyncStatusKind.ready => Icons.cloud_outlined,
      SyncStatusKind.upToDate ||
      SyncStatusKind.synced => Icons.cloud_done_outlined,
    };
    return IconButton(
      onPressed: onPressed,
      tooltip: label,
      icon: syncing
          ? const SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            )
          : Icon(icon),
    );
  }
}

class _SyncDistribution extends StatelessWidget {
  const _SyncDistribution({required this.result});

  final SyncResult result;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final values = [
      ('Uploaded', result.uploaded, colors.primary),
      ('Downloaded', result.downloaded, colors.tertiary),
      ('Deleted here', result.deletedLocal, colors.secondary),
      ('Deleted remote', result.deletedRemote, colors.secondary),
      ('Unchanged', result.skipped, colors.outlineVariant),
      ('Repaired', result.repaired, colors.secondary),
      ('Conflicts', result.conflicts, colors.error),
    ];
    final visible = values.where((item) => item.$2 > 0).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Latest sync', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        if (visible.isEmpty)
          const Text('No files needed changes.')
        else
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 12,
              child: Row(
                children: [
                  for (final item in visible)
                    Expanded(
                      flex: item.$2,
                      child: ColoredBox(color: item.$3),
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 10,
          children: [
            for (final item in visible)
              _SyncMetric(label: item.$1, value: item.$2, color: item.$3),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '${result.remoteCount} files on Nextcloud',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _SyncMetric extends StatelessWidget {
  const _SyncMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text('$label $value'),
    ],
  );
}

class _SyncStatusCard extends StatelessWidget {
  const _SyncStatusCard({
    required this.syncing,
    required this.vaultOpen,
    required this.storageHealthy,
    required this.cloudConfigured,
    required this.desktopManaged,
    required this.result,
    required this.lastSyncAt,
    required this.error,
    required this.conflicts,
    required this.onSync,
    required this.onReview,
    required this.onSetup,
  });

  final bool syncing;
  final bool vaultOpen;
  final bool storageHealthy;
  final bool cloudConfigured;
  final bool desktopManaged;
  final SyncResult? result;
  final DateTime? lastSyncAt;
  final String? error;
  final int conflicts;
  final VoidCallback? onSync;
  final VoidCallback onReview;
  final VoidCallback onSetup;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final kind = syncStatusKind(
      vaultOpen: vaultOpen,
      storageHealthy: storageHealthy,
      cloudConfigured: cloudConfigured,
      desktopManaged: desktopManaged,
      syncing: syncing,
      error: error,
      conflicts: conflicts,
      result: result,
    );
    final icon = switch (kind) {
      SyncStatusKind.vaultClosed => Icons.folder_open,
      SyncStatusKind.storageUnavailable => Icons.cloud_off_outlined,
      SyncStatusKind.desktopManaged => Icons.cloud_done_outlined,
      SyncStatusKind.notConfigured => Icons.cloud_off_outlined,
      SyncStatusKind.syncing => Icons.sync,
      SyncStatusKind.paused => Icons.cloud_off_outlined,
      SyncStatusKind.conflicts => Icons.warning_amber_rounded,
      SyncStatusKind.ready => Icons.cloud_done_outlined,
      SyncStatusKind.upToDate ||
      SyncStatusKind.synced => Icons.cloud_done_outlined,
    };
    final title = syncStatusTitle(kind, conflicts: conflicts);
    final subtitle = switch (kind) {
      SyncStatusKind.vaultClosed =>
        error ?? 'Choose a vault folder before syncing.',
      SyncStatusKind.storageUnavailable =>
        error ?? 'Reselect the vault folder before syncing.',
      SyncStatusKind.desktopManaged => 'This folder syncs through the system.',
      SyncStatusKind.notConfigured => 'Connect Nextcloud to sync this vault.',
      SyncStatusKind.syncing => 'Checking this device and Nextcloud.',
      SyncStatusKind.paused => error!,
      SyncStatusKind.conflicts =>
        'Sync is paused until you review the conflicts. Your files are safe.',
      SyncStatusKind.ready => 'No sync has completed in this session.',
      SyncStatusKind.upToDate => _lastChecked(lastSyncAt),
      SyncStatusKind.synced =>
        '${result!.uploaded} uploaded · ${result!.downloaded} downloaded · ${_lastChecked(lastSyncAt).toLowerCase()}',
    };
    final color = switch (kind) {
      SyncStatusKind.vaultClosed ||
      SyncStatusKind.storageUnavailable => colors.errorContainer,
      SyncStatusKind.desktopManaged ||
      SyncStatusKind.notConfigured => colors.surfaceContainerHighest,
      SyncStatusKind.syncing => colors.secondaryContainer,
      SyncStatusKind.paused => colors.errorContainer,
      SyncStatusKind.conflicts => colors.tertiaryContainer,
      SyncStatusKind.ready ||
      SyncStatusKind.upToDate ||
      SyncStatusKind.synced => colors.primaryContainer,
    };
    final action = syncStatusAction(kind);
    final onAction = switch (kind) {
      SyncStatusKind.notConfigured => onSetup,
      SyncStatusKind.paused => onSync,
      SyncStatusKind.conflicts => onReview,
      SyncStatusKind.ready ||
      SyncStatusKind.upToDate ||
      SyncStatusKind.synced => onSync,
      _ => null,
    };

    return Semantics(
      liveRegion: true,
      label: '$title. $subtitle',
      child: Card(
        color: color,
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  syncing
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : Icon(icon, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (action != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(onPressed: onAction, child: Text(action)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _lastChecked(DateTime? value) {
    if (value == null) return 'Ready to sync';
    final minutes = DateTime.now().difference(value).inMinutes;
    if (minutes < 1) return 'Checked just now';
    if (minutes == 1) return 'Checked 1 minute ago';
    return 'Checked $minutes minutes ago';
  }
}

class _LinksPanel extends StatelessWidget {
  const _LinksPanel({
    required this.current,
    required this.outgoing,
    required this.backlinks,
    required this.fileRefs,
    required this.index,
    required this.resolveLink,
    required this.onOpenLink,
    required this.onOpenPath,
    required this.onOpenFile,
    required this.onEditMetadata,
    this.dayItems = const [],
  });

  final String? current;
  final List<String> outgoing;
  final List<String> backlinks;
  final List<String> fileRefs;
  final List<CalendarItem> dayItems;
  final VaultIndex? index;
  final LinkResolution Function(String title) resolveLink;
  final ValueChanged<String> onOpenLink;
  final ValueChanged<String> onOpenPath;
  final ValueChanged<String> onOpenFile;
  final VoidCallback onEditMetadata;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    child: ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text('Context', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(current ?? '-', maxLines: 2, overflow: TextOverflow.ellipsis),
        TextButton.icon(
          onPressed: current == null ? null : onEditMetadata,
          icon: const Icon(Icons.tune),
          label: const Text('Edit metadata'),
        ),
        const Divider(height: 28),
        _SectionTitle('Outgoing'),
        if (outgoing.isEmpty) const _EmptyHint('No links from this page yet.'),
        for (final link in outgoing)
          Builder(
            builder: (context) {
              final resolved = resolveLink(link);
              final icon = switch (resolved.status) {
                LinkResolutionStatus.resolved => Icons.open_in_new,
                LinkResolutionStatus.ambiguous => Icons.error_outline,
                LinkResolutionStatus.unresolved => Icons.add,
              };
              final subtitle = switch (resolved.status) {
                LinkResolutionStatus.resolved => resolved.path!,
                LinkResolutionStatus.ambiguous => 'Ambiguous target',
                LinkResolutionStatus.unresolved => 'Unresolved',
              };
              return ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                title: Text(link),
                subtitle: Text(subtitle),
                trailing: Icon(icon),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                onTap: resolved.status == LinkResolutionStatus.ambiguous
                    ? null
                    : () => onOpenLink(link),
              );
            },
          ),
        const Divider(height: 28),
        _SectionTitle('Linked files'),
        if (fileRefs.isEmpty) const _EmptyHint('No linked files on this note.'),
        for (final path in fileRefs)
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            leading: const Icon(Icons.attach_file),
            title: Text(path.split('/').last),
            subtitle: Text(path),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            onTap: () => onOpenFile(path),
          ),
        if (dayItems.isNotEmpty) ...[
          const Divider(height: 28),
          _SectionTitle('On this day'),
          for (final item in dayItems)
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              leading: Icon(
                item.kind == CalendarItemKind.task
                    ? Icons.task_alt
                    : Icons.event,
              ),
              title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                item.notePath,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              onTap: () => onOpenPath(item.notePath),
            ),
        ],
        const Divider(height: 28),
        _SectionTitle('Backlinks'),
        if (backlinks.isEmpty)
          const _EmptyHint('Mention this page elsewhere and it appears here.'),
        for (final path in backlinks)
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            leading: const Icon(Icons.link),
            title: Text(
              index?.notesByPath[path]?.title ?? path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(path, maxLines: 1, overflow: TextOverflow.ellipsis),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            onTap: () => onOpenPath(path),
          ),
      ],
    ),
  );
}

class _SettingsSheet extends StatelessWidget {
  const _SettingsSheet({
    required this.vaultPath,
    required this.cloud,
    required this.syncing,
    required this.onNextcloud,
    required this.vaults,
    required this.activeVaultId,
    required this.onAddVault,
    required this.onSwitchVault,
    required this.onForgetVault,
    required this.onDeleteVault,
    required this.onEnableReminders,
  });

  final String vaultPath;
  final NextcloudConfig? cloud;
  final bool syncing;
  final VoidCallback onNextcloud;
  final List<VaultEntry> vaults;
  final String? activeVaultId;
  final VoidCallback onAddVault;
  final ValueChanged<VaultEntry> onSwitchVault;
  final ValueChanged<VaultEntry> onForgetVault;
  final ValueChanged<VaultEntry> onDeleteVault;
  final Future<void> Function() onEnableReminders;

  @override
  Widget build(BuildContext context) {
    final ready = cloud?.isReady ?? false;
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Settings',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              _SettingsTile(
                icon: Icons.folder_open,
                title: 'Local folder',
                subtitle: vaultPath,
              ),
              _SettingsTile(
                icon: Icons.create_new_folder,
                title: 'Vaults',
                subtitle: '${vaults.length} vaults · manage and switch',
                onTap: () => showModalBottomSheet<void>(
                  context: context,
                  showDragHandle: true,
                  builder: (context) => _VaultsSheet(
                    vaults: vaults,
                    activeVaultId: activeVaultId,
                    onAddVault: onAddVault,
                    onSwitchVault: onSwitchVault,
                    onForgetVault: onForgetVault,
                    onDeleteVault: onDeleteVault,
                  ),
                ),
              ),
              _SettingsTile(
                icon: Icons.sync,
                title: 'Sync',
                subtitle: syncing
                    ? 'Syncing...'
                    : (ready ? cloud!.serverUrl : 'Not configured'),
                onTap: onNextcloud,
              ),
              _SettingsTile(
                icon: Icons.notifications_outlined,
                title: 'Task reminders',
                subtitle: 'Enable local scheduled notifications',
                onTap: () => unawaited(onEnableReminders()),
              ),
              FutureBuilder<String>(
                future: appVersion(),
                builder: (context, snapshot) => _SettingsTile(
                  icon: Icons.info_outline,
                  title: 'App version',
                  subtitle: snapshot.data ?? '...',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VaultsSheet extends StatelessWidget {
  const _VaultsSheet({
    required this.vaults,
    required this.activeVaultId,
    required this.onAddVault,
    required this.onSwitchVault,
    required this.onForgetVault,
    required this.onDeleteVault,
  });

  final List<VaultEntry> vaults;
  final String? activeVaultId;
  final VoidCallback onAddVault;
  final ValueChanged<VaultEntry> onSwitchVault;
  final ValueChanged<VaultEntry> onForgetVault;
  final ValueChanged<VaultEntry> onDeleteVault;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        Text('Vaults', style: Theme.of(context).textTheme.headlineSmall),
        for (final entry in vaults)
          ListTile(
            leading: Icon(
              entry.id == activeVaultId
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
            ),
            title: Text(entry.name),
            subtitle: Text(
              entry.treeUri ?? entry.path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: entry.id == activeVaultId
                ? null
                : () {
                    Navigator.pop(context);
                    onSwitchVault(entry);
                  },
            trailing: PopupMenuButton<String>(
              onSelected: (action) {
                Navigator.pop(context);
                if (action == 'forget') onForgetVault(entry);
                if (action == 'delete') onDeleteVault(entry);
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'forget', child: Text('Forget vault')),
                PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete vault and files'),
                ),
              ],
            ),
          ),
        _SettingsTile(
          icon: Icons.create_new_folder,
          title: 'Add or create vault',
          subtitle: 'Choose an existing or empty folder',
          onTap: () {
            Navigator.pop(context);
            onAddVault();
          },
        ),
      ],
    ),
  );
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    child: ListTile(
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
        child: Icon(icon),
      ),
      title: Text(title),
      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      onTap: onTap,
    ),
  );
}

class _WorkSurface extends StatelessWidget {
  const _WorkSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: child,
    ),
  );
}

class _TodayView extends StatelessWidget {
  const _TodayView({
    required this.index,
    required this.onOpenToday,
    required this.onOpenPath,
  });

  final VaultIndex? index;
  final Future<void> Function() onOpenToday;
  final ValueChanged<String> onOpenPath;

  @override
  Widget build(BuildContext context) {
    final today = _isoDay(DateTime.now());
    final notes = index?.notes ?? const <NoteRef>[];
    final daily = notes
        .where((note) => note.kind == 'daily' && note.date == today)
        .firstOrNull;
    final due = (index?.tasks ?? const <TaskRef>[])
        .where(
          (task) =>
              task.status != 'done' &&
              task.due != null &&
              task.due!.split('T').first.compareTo(today) <= 0,
        )
        .toList();
    final recent = notes.where((note) => note.kind != 'daily').toList()
      ..sort(
        (a, b) => (b.modifiedMillis ?? 0).compareTo(a.modifiedMillis ?? 0),
      );
    final inbox = notes
        .where(
          (note) =>
              note.kind == 'note' && note.project == null && note.tags.isEmpty,
        )
        .toList();
    final backlinks = daily == null
        ? const <String>[]
        : index?.backlinksByTarget[daily.path] ?? const <String>[];
    final calendar =
        index?.calendar
            .where((item) => item.date.compareTo(today) >= 0)
            .take(7)
            .toList() ??
        const <CalendarItem>[];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Today', style: Theme.of(context).textTheme.headlineMedium),
        Text(today, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: onOpenToday,
          icon: const Icon(Icons.edit_note),
          label: const Text('Open today’s journal'),
        ),
        _DashboardSection(
          title: 'Due and overdue',
          empty: 'No due tasks',
          children: [
            for (final task in due)
              ListTile(
                leading: const Icon(Icons.task_alt),
                title: Text(task.text),
                subtitle: Text(task.due ?? ''),
                onTap: () => onOpenPath(task.notePath),
              ),
          ],
        ),
        _DashboardSection(
          title: 'Next dates',
          empty: 'No upcoming dates',
          children: [
            for (final item in calendar)
              ListTile(
                leading: const Icon(Icons.event),
                title: Text(item.title),
                subtitle: Text(item.date),
                onTap: () => onOpenPath(item.notePath),
              ),
          ],
        ),
        _DashboardSection(
          title: 'Recent notes',
          empty: 'No notes yet',
          children: [
            for (final item in recent.take(5))
              ListTile(
                leading: const Icon(Icons.notes),
                title: Text(item.title),
                subtitle: Text(item.path),
                onTap: () => onOpenPath(item.path),
              ),
          ],
        ),
        _DashboardSection(
          title: 'Today’s mentions',
          empty: 'No backlinks to today',
          children: [
            for (final path in backlinks)
              ListTile(
                leading: const Icon(Icons.link),
                title: Text(index?.notesByPath[path]?.title ?? path),
                onTap: () => onOpenPath(path),
              ),
          ],
        ),
        _DashboardSection(
          title: 'Inbox',
          empty: 'No unclassified notes',
          children: [
            for (final item in inbox.take(5))
              ListTile(
                leading: const Icon(Icons.inbox_outlined),
                title: Text(item.title),
                onTap: () => onOpenPath(item.path),
              ),
          ],
        ),
      ],
    );
  }
}

class _DashboardSection extends StatelessWidget {
  const _DashboardSection({
    required this.title,
    required this.empty,
    required this.children,
  });

  final String title;
  final String empty;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        if (children.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(empty),
          )
        else
          ...children,
      ],
    ),
  );
}

class _PrimaryTasksView extends StatelessWidget {
  const _PrimaryTasksView({
    required this.tasks,
    required this.onOpenPath,
    required this.onSetStatus,
  });

  final List<TaskRef> tasks;
  final ValueChanged<String> onOpenPath;
  final Future<void> Function(TaskRef task, String status) onSetStatus;

  @override
  Widget build(BuildContext context) {
    final sorted = tasks.toList()
      ..sort((a, b) => (a.due ?? '9999').compareTo(b.due ?? '9999'));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Tasks', style: Theme.of(context).textTheme.headlineMedium),
        if (sorted.isEmpty) const ListTile(title: Text('No indexed tasks')),
        for (final task in sorted)
          CheckboxListTile(
            value: task.status == 'done',
            title: Text(task.text),
            subtitle: Text(
              [
                if (task.project != null) task.project!,
                if (task.due != null) 'due ${task.due}',
              ].join(' · '),
            ),
            onChanged: (done) =>
                onSetStatus(task, done == true ? 'done' : 'todo'),
            secondary: IconButton(
              tooltip: 'Open source note',
              icon: const Icon(Icons.open_in_new),
              onPressed: () => onOpenPath(task.notePath),
            ),
          ),
      ],
    );
  }
}

class _LibraryView extends StatelessWidget {
  const _LibraryView({
    required this.index,
    required this.onOpenPath,
    required this.onOpenDay,
  });

  final VaultIndex? index;
  final ValueChanged<String> onOpenPath;
  final ValueChanged<DateTime> onOpenDay;

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 4,
    child: Column(
      children: [
        const TabBar(
          isScrollable: true,
          tabs: [
            Tab(text: 'Notes'),
            Tab(text: 'Projects'),
            Tab(text: 'Articles'),
            Tab(text: 'Calendar'),
          ],
        ),
        Expanded(
          child: TabBarView(
            children: [
              _notes('note'),
              _notes('project'),
              _notes('article'),
              _CalendarTab(
                index: index,
                onOpenPath: onOpenPath,
                onOpenDay: onOpenDay,
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _notes(String kind) => ListView(
    children: [
      for (final note in (index?.notes ?? const <NoteRef>[]).where(
        (note) => note.kind == kind,
      ))
        ListTile(
          leading: Icon(switch (kind) {
            'project' => Icons.work_outline,
            'article' => Icons.article_outlined,
            _ => Icons.notes,
          }),
          title: Text(note.title),
          subtitle: Text(note.path),
          onTap: () => onOpenPath(note.path),
        ),
    ],
  );
}

class _CalendarTab extends StatefulWidget {
  const _CalendarTab({
    required this.index,
    required this.onOpenPath,
    required this.onOpenDay,
  });

  final VaultIndex? index;
  final ValueChanged<String> onOpenPath;
  final ValueChanged<DateTime> onOpenDay;

  @override
  State<_CalendarTab> createState() => _CalendarTabState();
}

class _CalendarTabState extends State<_CalendarTab> {
  DateTime selected = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final iso = _isoDay(selected);
    final items = (widget.index?.calendar ?? const <CalendarItem>[])
        .where((item) => item.date == iso)
        .toList();
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      children: [
        MonthCalendar(
          index: widget.index,
          initialMonth: selected,
          onDaySelected: (day) => setState(() => selected = day),
          onOpenDay: widget.onOpenDay,
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.edit_note),
          title: Text('Open journal $iso'),
          onTap: () => widget.onOpenDay(selected),
        ),
        if (items.isEmpty)
          const ListTile(title: Text('Nothing on this day yet')),
        for (final item in items)
          ListTile(
            leading: Icon(switch (item.kind) {
              CalendarItemKind.daily => Icons.book_outlined,
              CalendarItemKind.task => Icons.task_alt,
              _ => Icons.event,
            }),
            title: Text(item.title),
            subtitle: Text(item.notePath),
            onTap: () => widget.onOpenPath(item.notePath),
          ),
      ],
    );
  }
}

class _Editor extends StatefulWidget {
  const _Editor({
    required this.controller,
    required this.onChanged,
    this.monospace = false,
  });

  final TextEditingController controller;
  final VoidCallback onChanged;
  final bool monospace;

  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  final focusNode = FocusNode();

  @override
  void dispose() {
    focusNode.dispose();
    super.dispose();
  }

  void _replace(String before, String after) {
    final controller = widget.controller;
    final selection = controller.selection;
    final start = selection.isValid ? selection.start : controller.text.length;
    final end = selection.isValid ? selection.end : controller.text.length;
    final selected = controller.text.substring(start, end);
    controller.value = controller.value.copyWith(
      text: controller.text.replaceRange(start, end, '$before$selected$after'),
      selection: TextSelection.collapsed(
        offset: start + before.length + selected.length,
      ),
      composing: TextRange.empty,
    );
    widget.onChanged();
    focusNode.requestFocus();
  }

  void _linePrefix(String prefix) {
    final controller = widget.controller;
    final selection = controller.selection;
    final cursor = selection.isValid ? selection.start : controller.text.length;
    final lineStart = cursor == 0
        ? 0
        : controller.text.lastIndexOf('\n', cursor - 1) + 1;
    controller.value = controller.value.copyWith(
      text: controller.text.replaceRange(lineStart, lineStart, prefix),
      selection: TextSelection.collapsed(offset: cursor + prefix.length),
      composing: TextRange.empty,
    );
    widget.onChanged();
    focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: TextField(
          controller: widget.controller,
          focusNode: focusNode,
          expands: true,
          maxLines: null,
          minLines: null,
          textAlignVertical: TextAlignVertical.top,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            height: 1.45,
            fontFamily: widget.monospace ? 'monospace' : null,
          ),
          decoration: const InputDecoration(contentPadding: EdgeInsets.all(18)),
          onChanged: (_) => widget.onChanged(),
        ),
      ),
      ListenableBuilder(
        listenable: focusNode,
        builder: (context, _) => focusNode.hasFocus
            ? SafeArea(
                top: false,
                child: SizedBox(
                  height: 48,
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    scrollDirection: Axis.horizontal,
                    children: [
                      _DockButton('=', 'Heading', () => _linePrefix('= ')),
                      _DockButton('*', 'Bold', () => _replace('*', '*')),
                      _DockButton('_', 'Emphasis', () => _replace('_', '_')),
                      _DockButton(r'$', 'Math', () => _replace(r'$', r'$')),
                      _DockButton(
                        '#',
                        'Function or tag',
                        () => _replace('#', ''),
                      ),
                      _DockButton('+', 'New block', () => _replace('\n- ', '')),
                    ],
                  ),
                ),
              )
            : const SizedBox.shrink(),
      ),
    ],
  );
}

class _DockButton extends StatelessWidget {
  const _DockButton(this.label, this.tooltip, this.onPressed);

  final String label;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 2),
    child: IconButton.outlined(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Text(label),
    ),
  );
}

List<String> _csvValues(String value) =>
    value
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

String _isoDay(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

const _weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// "Mon, July 6"; the year is appended only when it is not the current year.
// ponytail: English-only names, add intl if localization is ever needed.
String humanDate(DateTime day, {DateTime? now}) {
  final label =
      '${_weekdayNames[day.weekday - 1]}, ${_monthNames[day.month - 1]} ${day.day}';
  return day.year == (now ?? DateTime.now()).year
      ? label
      : '$label, ${day.year}';
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: Theme.of(context).textTheme.labelLarge);
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(text, style: Theme.of(context).textTheme.bodySmall),
  );
}
