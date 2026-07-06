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
import 'nextcloud_sync.dart';
import 'pkms_registry.dart';
import 'report.dart';
import 'scanner.dart';
import 'search_index.dart';
import 'task_scheduler.dart';
import 'vault.dart';
import 'vault_registry.dart';

Future<String> appVersion() async =>
    RegExp(r'^version:\s*(.+)$', multiLine: true)
        .firstMatch(await rootBundle.loadString('pubspec.yaml'))
        ?.group(1)
        ?.trim() ??
    'unknown';

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
  File? note;
  final sourceController = TextEditingController();
  Timer? autosave;
  Timer? cloudAutosave;
  Timer? cloudPoll;
  String status = 'Opening vault...';
  bool dirty = false;
  int editRevision = 0;
  String mode = 'today';
  String helperSource = tylogHelperSource;
  NextcloudConfig? cloud;
  PkmsSearchIndex searchIndex = PkmsSearchIndex.empty();
  PkmsValidationReport? validation;
  SyncResult? lastSync;
  DateTime? lastSyncAt;
  String? syncError;
  String? selectedTag;
  bool syncing = false;
  bool autosaveDeferred = false;
  Completer<void>? syncCompletion;
  bool rebuilding = false;
  bool cancelRebuild = false;
  double? rebuildProgress;
  VaultRegistry? vaultRegistry;
  final taskScheduler = TaskScheduler();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _open();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    autosave?.cancel();
    cloudAutosave?.cancel();
    cloudPoll?.cancel();
    sourceController.dispose();
    super.dispose();
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
      var active = registry.active;
      try {
        await Vault(Directory(active.path)).ensureCreated();
      } on StateError {
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
      if (Platform.isAndroid && !registry.onboardingComplete && mounted) {
        await _showAndroidOnboarding(registry);
      }
    } catch (e) {
      setState(() => status = 'Open failed: $e');
    }
  }

  Future<void> _openVault(VaultEntry entry, {String? trigger}) async {
    try {
      autosave?.cancel();
      cloudAutosave?.cancel();
      cloudPoll?.cancel();
      final v = Vault(Directory(entry.path));
      await v.ensureCreated();
      // ponytail: offline-first — render local vault immediately, sync in background
      final openStatus = 'Vault: ${v.root.path}';
      final today = await v.todayNote();
      final ix = await v.rebuildIndex();
      final pkms = await _readPkms(v, ix);
      final loadedHelper = await v.helperFile.readAsString();
      _loadSource(await today.readAsString());
      setState(() {
        vault = v;
        note = today;
        index = _retainIndex(ix);
        validation = _retainValidation(pkms.report);
        searchIndex = pkms.search;
        helperSource = loadedHelper;
        cloud = entry.cloud;
        selectedTag = null;
        lastSync = null;
        lastSyncAt = null;
        syncError = null;
        if (trigger != 'startup') mode = 'today';
        status = '$openStatus · ${pkms.report.summary()}';
      });
      unawaited(taskScheduler.reconcile(ix.tasks));
      if (entry.cloud != null && entry.cloud!.isReady) {
        if (trigger != null) unawaited(_syncNow(trigger: trigger));
        _startCloudPolling();
      }
    } catch (e) {
      setState(() => status = 'Open failed: $e');
    }
  }

  Future<({PkmsValidationReport report, PkmsSearchIndex search})> _readPkms(
    Vault v,
    VaultIndex ix,
  ) async {
    final report = await validatePkms(v.root, ix);
    final cached = await PkmsSearchIndex.load(v.searchIndexFile);
    final search = await PkmsSearchIndex.build(v.root, ix, previous: cached);
    await search.save(v.searchIndexFile);
    return (report: report, search: search);
  }

  Future<void> _switchVault(VaultEntry entry) async {
    final registry = vaultRegistry;
    if (registry == null || registry.activeId == entry.id) return;
    if (dirty) await _save(syncAfter: false);
    await registry.select(entry);
    await _openVault(entry);
  }

  Future<bool> _pickVault({bool closeCurrent = true}) async {
    if (closeCurrent) Navigator.pop(context);
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

  Future<void> _showAndroidOnboarding(VaultRegistry registry) async {
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: SimpleDialog(
          title: const Text('Where should TyLog store your vault?'),
          children: [
            ListTile(
              leading: const Icon(Icons.phone_android),
              title: const Text('Private app storage'),
              subtitle: const Text('Keep the vault only inside TyLog.'),
              onTap: () => Navigator.pop(context, 'app'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: const Text('Choose a device folder'),
              subtitle: const Text('Select an existing or empty folder.'),
              onTap: () => Navigator.pop(context, 'folder'),
            ),
            ListTile(
              leading: const Icon(Icons.cloud_outlined),
              title: const Text('Connect Nextcloud'),
              subtitle: const Text(
                'Keep a local copy and sync it to a remote folder.',
              ),
              onTap: () => Navigator.pop(context, 'nextcloud'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    final complete = switch (choice) {
      'app' => true,
      'folder' => await _pickVault(closeCurrent: false),
      'nextcloud' => await _showSyncSettings(),
      _ => false,
    };
    if (complete) await registry.completeOnboarding();
  }

  Future<void> _forgetVault(VaultEntry entry) async {
    final registry = vaultRegistry!;
    if (registry.entries.length == 1) {
      setState(() => status = 'Cannot forget the only vault');
      return;
    }
    if (entry.id == registry.activeId) {
      await _switchVault(
        registry.entries.firstWhere((item) => item.id != entry.id),
      );
    }
    await registry.forget(entry);
    if (mounted) setState(() => status = 'Forgot ${entry.name}; files kept');
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
      if (registry.entries.isEmpty) {
        final replacement = await Vault.openDefault();
        final replacementEntry = await registry.add(replacement.root.path);
        await registry.select(replacementEntry);
      }
      if (wasActive) {
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

  Future<void> _save({
    bool syncAfter = true,
    bool allowWhileSyncing = false,
  }) async {
    autosave?.cancel();
    if (syncing && !allowWhileSyncing) {
      autosaveDeferred = true;
      await syncCompletion?.future;
      if (!autosaveDeferred) return;
      autosaveDeferred = false;
    }
    final v = vault;
    final n = note;
    if (v == null || n == null) return;
    final revision = editRevision;
    final source = _currentSource();
    try {
      await v.saveNote(n, source);
      final ix = await v.rebuildIndex();
      final pkms = await _readPkms(v, ix);
      final editorUnchanged = revision == editRevision && identical(n, note);
      setState(() {
        index = _retainIndex(ix);
        validation = _retainValidation(pkms.report);
        searchIndex.replaceWith(pkms.search);
        if (editorUnchanged) {
          dirty = false;
          status = 'Saved ${v.relativePath(n)} · ${pkms.report.summary()}';
        }
      });
      if (syncAfter && editorUnchanged) _queueCloudSync();
    } catch (e) {
      if (revision == editRevision && identical(n, note)) {
        setState(() => status = 'Save failed: $e');
      }
    }
  }

  void _queueCloudSync() {
    final cfg = cloud;
    if (cfg == null || !cfg.isReady || syncing || _hasSyncConflicts) return;
    cloudAutosave?.cancel();
    cloudAutosave = Timer(const Duration(seconds: 2), () {
      if (!syncing && !dirty && !_hasSyncConflicts) {
        unawaited(_syncNow(trigger: 'autosave'));
      }
    });
  }

  void _startCloudPolling() {
    cloudPoll?.cancel();
    final cfg = cloud;
    if (cfg == null || !cfg.isReady) return;
    cloudPoll = Timer.periodic(const Duration(seconds: 25), (_) {
      if (!syncing && !dirty && !_hasSyncConflicts && mounted) {
        unawaited(_syncNow(trigger: 'poll'));
      }
    });
  }

  bool get _hasSyncConflicts => (validation?.count('sync-conflict') ?? 0) > 0;

  void _queueAutosave() {
    setState(() {
      editRevision++;
      dirty = true;
      status = 'Autosave pending...';
    });
    autosave?.cancel();
    autosave = Timer(const Duration(milliseconds: 700), _save);
  }

  String _currentSource() => sourceController.text;

  FileSource _typstFiles() => FileSource.bytes({
    '_system/tylog.typ': Uint8List.fromList(utf8.encode(helperSource)),
    '/_system/tylog.typ': Uint8List.fromList(utf8.encode(helperSource)),
    '_system/theme.typ': Uint8List.fromList(utf8.encode(tylogThemeSource)),
    '/_system/theme.typ': Uint8List.fromList(utf8.encode(tylogThemeSource)),
  });

  void _loadSource(String source) => sourceController.text = source;

  Future<void> _openNote(File file) async {
    final v = vault;
    if (v == null) return;
    if (dirty) await _save();
    final source = await file.readAsString();
    _loadSource(source);
    setState(() {
      note = file;
      dirty = false;
      mode = 'normal';
      status = 'Opened ${v.relativePath(file)}';
    });
  }

  Future<void> _openToday() async {
    final v = vault;
    if (v == null) return;
    await _openNote(await v.todayNote());
  }

  Future<void> _openLink(String title) async {
    final v = vault;
    if (v == null) return;
    final existing = _pathForLink(title);
    if (existing != null) {
      await _openNote(File('${v.root.path}/$existing'));
      return;
    }
    final file = await v.page(title);
    await _openNote(file);
    setState(() => status = 'Created ${v.relativePath(file)}');
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

  Future<File?> _chooseTemplate(Vault v) async {
    final templates = await v.templates
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.typ'))
        .cast<File>()
        .toList();
    templates.sort((a, b) => a.path.compareTo(b.path));
    if (templates.isEmpty) return null;
    if (!mounted) return null;
    return showDialog<File?>(
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
              child: Text(file.path.split(Platform.pathSeparator).last),
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
      dirty = true;
      await _save();
    }
    for (final value in [title, tagsText, aliases]) {
      value.dispose();
    }
  }

  Future<void> _showKnowledge({
    KnowledgeView initialView = KnowledgeView.search,
  }) async {
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
          problems: validation?.problems ?? ix.problems,
          onOpenNote: _openPath,
          onResolveConflict: _resolveConflict,
          onCleanSyncCaches: _cleanSyncCaches,
          onSetTaskStatus: _setTaskStatus,
        ),
      ),
    );
  }

  Future<void> _setTaskStatus(TaskRef task, String nextStatus) async {
    final v = vault;
    if (v == null) return;
    final file = File('${v.root.path}/${task.notePath}');
    final source = await file.readAsString();
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

  Future<void> _refreshPkms(String message) async {
    final v = vault;
    final ix = index;
    if (v == null || ix == null) return;
    final pkms = await _readPkms(v, ix);
    if (!mounted) return;
    setState(() {
      validation = _retainValidation(pkms.report);
      searchIndex.replaceWith(pkms.search);
      status = '$message · ${pkms.report.summary()}';
    });
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
    if (isNextcloudManagedVault(v.root)) {
      setState(() => status = 'Sync handled by Nextcloud Desktop');
      return;
    }
    syncCompletion = Completer<void>();
    setState(() {
      syncing = true;
      syncError = null;
      status = 'Syncing…';
    });
    try {
      cloudAutosave?.cancel();
      if (dirty) {
        await _save(syncAfter: false, allowWhileSyncing: true);
        if (dirty) return;
      }
      final syncedNote = note;
      final sourceBeforeSync = syncedNote == null ? null : _currentSource();
      final revisionBeforeSync = editRevision;
      final result = await NextcloudSync(cfg).sync(v, trigger: trigger);
      var concurrentConflict = false;
      if (syncedNote != null &&
          identical(syncedNote, note) &&
          await syncedNote.exists()) {
        final diskSource = await syncedNote.readAsString();
        if (diskSource != sourceBeforeSync) {
          if (revisionBeforeSync == editRevision && !dirty) {
            _loadSource(diskSource);
          } else {
            final conflict = File(
              '${syncedNote.path}.remote-conflict-${DateTime.now().millisecondsSinceEpoch}',
            );
            await conflict.writeAsString(diskSource, flush: true);
            concurrentConflict = true;
          }
        }
      }
      final ix = await v.rebuildIndex();
      final pkms = await _readPkms(v, ix);
      setState(() {
        index = _retainIndex(ix);
        validation = _retainValidation(pkms.report);
        searchIndex.replaceWith(pkms.search);
        lastSync = result;
        lastSyncAt = DateTime.now();
        final changed = result.uploaded + result.downloaded + result.repaired;
        status = result.conflicts > 0 || concurrentConflict
            ? 'Needs attention'
            : changed == 0
            ? 'Up to date'
            : 'Synced';
      });
    } catch (e) {
      setState(() {
        syncError = _friendlySyncError(e);
        status = syncError!;
      });
    } finally {
      setState(() => syncing = false);
      syncCompletion?.complete();
      syncCompletion = null;
    }
  }

  Future<void> _resolveConflict(PkmsProblem problem) async {
    final v = vault;
    if (v == null) return;
    final marker = problem.subject.indexOf('.remote-conflict-');
    if (marker < 0) return;
    final conflict = File('${v.root.path}/${problem.subject}');
    final original = File(
      '${v.root.path}/${problem.subject.substring(0, marker)}',
    );
    if (!await conflict.exists()) return;
    final localText = await original.exists()
        ? await original.readAsString()
        : '';
    final remoteText = await conflict.readAsString();
    if (localText == remoteText ||
        (localText.trim().isNotEmpty && remoteText.trim().isEmpty)) {
      await conflict.delete();
      await _refreshPkms(
        localText == remoteText
            ? 'Identical conflict copy removed'
            : 'Empty conflict copy removed; local note kept',
      );
      _queueCloudSync();
      return;
    }
    final localModified = await original.exists()
        ? await original.lastModified()
        : null;
    final remoteModified = await conflict.lastModified();
    if (!mounted) return;
    final merged = TextEditingController(text: localText);
    final selectedVersion = ValueNotifier<String?>('local');
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
                v.relativePath(original),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              const Text(
                'Both copies changed. Compare the highlighted sections, choose a version, or edit the final result.',
              ),
              const SizedBox(height: 16),
              ValueListenableBuilder<String?>(
                valueListenable: selectedVersion,
                builder: (context, selected, _) => LayoutBuilder(
                  builder: (context, constraints) {
                    final cards = [
                      _ConflictVersionCard(
                        title: 'This device',
                        text: localText,
                        otherText: remoteText,
                        modified: localModified,
                        newer:
                            localModified != null &&
                            localModified.isAfter(remoteModified),
                        selected: selected == 'local',
                        color: Theme.of(context).colorScheme.primaryContainer,
                        onUse: () {
                          selectedVersion.value = 'local';
                          merged.text = localText;
                        },
                      ),
                      _ConflictVersionCard(
                        title: 'Nextcloud copy',
                        text: remoteText,
                        otherText: localText,
                        modified: remoteModified,
                        newer:
                            localModified == null ||
                            remoteModified.isAfter(localModified),
                        selected: selected == 'remote',
                        color: Theme.of(context).colorScheme.tertiaryContainer,
                        onUse: () {
                          selectedVersion.value = 'remote';
                          merged.text = remoteText;
                        },
                      ),
                    ];
                    if (constraints.maxWidth < 700) {
                      return Column(
                        children: [
                          cards.first,
                          const SizedBox(height: 12),
                          cards.last,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: cards.first),
                        const SizedBox(width: 12),
                        Expanded(child: cards.last),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Final version',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              const Text(
                'This is what will be saved and synced to your other devices.',
              ),
              const SizedBox(height: 8),
              TextField(
                controller: merged,
                minLines: 12,
                maxLines: null,
                style: const TextStyle(fontFamily: 'monospace'),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                  labelText: 'Edit final version',
                ),
              ),
            ],
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => Navigator.pop(context, true),
                    icon: const Icon(Icons.check),
                    label: const Text('Save resolution'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (save == true) {
      await v.saveNote(original, merged.text);
      await conflict.delete();
      await _refreshPkms('Conflict resolved');
      _queueCloudSync();
    }
    selectedVersion.dispose();
    merged.dispose();
  }

  Future<void> _cleanSyncCaches() async {
    final v = vault;
    if (v == null) return;
    await for (final entity in v.root.list(recursive: true)) {
      if (entity is! File) continue;
      final path = v.relativePath(entity);
      final marker = path.indexOf('.remote-conflict-');
      if (marker < 0) continue;
      final original = path.substring(0, marker);
      if (original == '_index/index.json' ||
          original == '_index/search-index.json.gz') {
        await entity.delete();
      }
    }
    await _refreshPkms('Old sync caches removed');
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
    if (state == AppLifecycleState.resumed && (cloud?.isReady ?? false)) {
      unawaited(_syncNow(trigger: 'resume'));
    }
  }

  void _showSettings() {
    final v = vault;
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: _SettingsSheet(
            vaultPath: v?.root.path ?? 'Opening vault...',
            cloud: cloud,
            syncing: syncing,
            vaults: vaultRegistry?.entries ?? const [],
            activeVaultId: vaultRegistry?.activeId,
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
              unawaited(_showSyncSettings());
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
    final result = await OpenFile.open('${v.root.path}/$path');
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
    await _openNote(File('${v.root.path}/$path'));
  }

  void _showPreview() {
    setState(() => mode = 'preview');
  }

  void _showJournal() => setState(() => mode = 'normal');

  void _updateControlledSource(String source) {
    sourceController.text = source;
    _queueAutosave();
  }

  void _showToday() => setState(() => mode = 'today');

  void _showSource() => setState(() => mode = 'source');

  void _toggleSourcePreview() =>
      mode == 'source' ? _showPreview() : _showSource();

  void _showSyncDetails(int conflicts) {
    final v = vault;
    final desktopManaged = v != null && isNextcloudManagedVault(v.root);
    void closeThen(VoidCallback action) {
      Navigator.pop(context);
      action();
    }

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Nextcloud sync',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              _SyncStatusCard(
                syncing: syncing,
                cloudConfigured: cloud?.isReady ?? false,
                desktopManaged: desktopManaged,
                result: lastSync,
                lastSyncAt: lastSyncAt,
                error: syncError,
                conflicts: conflicts,
                onSync: syncing
                    ? null
                    : () => closeThen(() => unawaited(_syncNow())),
                onReview: () => closeThen(
                  () => unawaited(
                    _showKnowledge(initialView: KnowledgeView.problems),
                  ),
                ),
                onSetup: () => closeThen(() => unawaited(_showSyncSettings())),
              ),
              if (lastSync != null) ...[
                const SizedBox(height: 16),
                _SyncDistribution(result: lastSync!),
              ],
            ],
          ),
        ),
      ),
    );
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
    final editor = sourceController;
    final selection = editor.selection;
    if (!selection.isValid || selection.isCollapsed) return '';
    return editor.text.substring(selection.start, selection.end);
  }

  void _applyMagic(MagicRequest request) {
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
    final file = vault?.bibliographyFile;
    if (file == null || !await file.exists()) return null;
    final entries = parseHayagrivaBibliography(await file.readAsString());
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
    var target = File('${v.assets.path}/$base');
    var suffix = 2;
    while (await target.exists()) {
      final dot = base.lastIndexOf('.');
      final stem = dot < 0 ? base : base.substring(0, dot);
      final extension = dot < 0 ? '' : base.substring(dot);
      target = File('${v.assets.path}/$stem-${suffix++}$extension');
    }
    await source.copy(target.path);
    final relative = v.relativePath(target);
    const imageExtensions = {'.png', '.jpg', '.jpeg', '.gif', '.svg', '.webp'};
    final lower = target.path.toLowerCase();
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
    final report = await writeReport(
      v.root,
      title,
      ix,
      ReportFilter(
        project: project?.id,
        from: range == null ? null : _isoDay(range.start),
        to: range == null ? null : _isoDay(range.end),
      ),
    );
    final pdf = await exportReportPdf(v.root, report);
    if (mounted) {
      setState(
        () => status =
            'Created ${v.relativePath(report)} and ${v.relativePath(pdf)}',
      );
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

  Future<void> _quickCapture(String text) async {
    final v = vault;
    if (v == null || text.trim().isEmpty) return;
    final today = await v.todayNote();
    final source = await today.readAsString();
    await v.saveNote(today, '${source.trimRight()}\n\n${text.trim()}\n');
    final rebuilt = await v.rebuildIndex();
    final pkms = await _readPkms(v, rebuilt);
    setState(() {
      index = _retainIndex(rebuilt);
      validation = _retainValidation(pkms.report);
      searchIndex.replaceWith(pkms.search);
      status = 'Captured in today\'s journal';
    });
    _queueCloudSync();
  }

  int get _destination => switch (mode) {
    'today' => 0,
    'tasks' => 2,
    'library' => 3,
    _ => 1,
  };

  void _selectDestination(int destination) {
    switch (destination) {
      case 0:
        _showToday();
        return;
      case 1:
        _showJournal();
        return;
      case 2:
        setState(() => mode = 'tasks');
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
    final syncConflicts =
        validation?.count('sync-conflict') ??
        index?.problems.where((p) => p.code == 'sync-conflict').length ??
        0;
    final desktopManaged = v != null && isNextcloudManagedVault(v.root);
    final linksPanel = _LinksPanel(
      current: current,
      outgoing: outgoing,
      backlinks: backlinks,
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
    final workArea = _WorkSurface(
      title: currentTitle,
      subtitle: current ?? 'daily journal',
      status: status,
      child: switch (mode) {
        'today' => _TodayView(
          index: index,
          onCapture: _quickCapture,
          onOpenToday: _openToday,
          onOpenPath: _openPath,
        ),
        'tasks' => _PrimaryTasksView(
          tasks: index?.tasks ?? const [],
          onOpenPath: _openPath,
          onSetStatus: _setTaskStatus,
        ),
        'library' => _LibraryView(index: index, onOpenPath: _openPath),
        'graph' => GraphView(
          graph: graph ?? const NoteGraph(nodes: [], edges: []),
          currentPath: current,
          onOpenPath: _openPath,
        ),
        'preview' => TypstDocumentViewer(
          source: sourceController.text,
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
                source: sourceController.text,
                files: _typstFiles(),
              ),
            ),
          ],
        ),
        'normal' => _ControlledEditorView(
          source: sourceController.text,
          onChanged: _updateControlledSource,
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(dirty ? 'TyLog •' : 'TyLog'),
            Text(
              currentTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _showKnowledge,
            icon: const Icon(Icons.search),
            tooltip: 'Search knowledge',
          ),
          IconButton(
            isSelected: mode == 'source',
            onPressed: _toggleSourcePreview,
            icon: const Icon(Icons.sync_alt),
            tooltip: mode == 'source' ? 'Preview' : 'Source',
          ),
          _SyncIconButton(
            syncing: syncing,
            configured: cloud?.isReady ?? false,
            desktopManaged: desktopManaged,
            error: syncError,
            conflicts: syncConflicts,
            result: lastSync,
            onPressed: () => _showSyncDetails(syncConflicts),
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
                case _ShellAction.sync:
                  unawaited(_syncNow());
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
              PopupMenuItem(
                value: _ShellAction.sync,
                enabled: !syncing,
                child: const Text('Sync'),
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
      floatingActionButton: _destination == 1 && mode != 'graph'
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
  sync,
  typstHelp,
  settings,
}

// ignore: unused_element
String? _panelActivity(String status) {
  if (status.startsWith('Sync') || status.startsWith('Vault:')) return null;
  return status.split(' · validation ').first;
}

String _friendlySyncError(Object error) {
  if (error is SocketException || error is TimeoutException) {
    return 'Nextcloud is unreachable. Your changes are safe on this device.';
  }
  final text = error.toString();
  if (text.contains('401') || text.contains('403')) {
    return 'Nextcloud rejected the login. Check Sync settings.';
  }
  if (text.contains('507')) return 'Nextcloud is out of storage space.';
  return 'Sync stopped before completion. Your local files were not removed.';
}

class _ConflictVersionCard extends StatelessWidget {
  const _ConflictVersionCard({
    required this.title,
    required this.text,
    required this.otherText,
    required this.modified,
    required this.newer,
    required this.selected,
    required this.color,
    required this.onUse,
  });

  final String title;
  final String text;
  final String otherText;
  final DateTime? modified;
  final bool newer;
  final bool selected;
  final Color color;
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) => Card(
    color: color,
    shape: RoundedRectangleBorder(
      side: selected
          ? BorderSide(color: Theme.of(context).colorScheme.primary, width: 2)
          : BorderSide.none,
      borderRadius: BorderRadius.circular(12),
    ),
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onUse,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            Text(
              modified == null
                  ? 'Not present on this device'
                  : 'Modified ${_relativeTime(modified!)}${newer ? ' · Newer' : ''}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Text(
              'Changed section',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 4),
            Container(
              constraints: const BoxConstraints(minHeight: 80, maxHeight: 220),
              padding: const EdgeInsets.all(10),
              color: Theme.of(
                context,
              ).colorScheme.surface.withValues(alpha: 0.75),
              child: SingleChildScrollView(
                child: SelectableText(
                  _changedExcerpt(text, otherText),
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
            ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('View full version'),
              children: [
                Container(
                  constraints: const BoxConstraints(maxHeight: 300),
                  alignment: Alignment.topLeft,
                  child: SingleChildScrollView(
                    child: SelectableText(
                      text.isEmpty ? '(Empty file)' : text,
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

String _changedExcerpt(String text, String other) {
  if (text == other) return '(No text differences)';
  final lines = text.split('\n');
  final otherLines = other.split('\n');
  var start = 0;
  while (start < lines.length &&
      start < otherLines.length &&
      lines[start] == otherLines[start]) {
    start++;
  }
  var end = 0;
  while (end < lines.length - start &&
      end < otherLines.length - start &&
      lines[lines.length - 1 - end] ==
          otherLines[otherLines.length - 1 - end]) {
    end++;
  }
  final changed = lines.sublist(start, lines.length - end);
  if (changed.isEmpty || (changed.length == 1 && changed.first.isEmpty)) {
    return '(Nothing in this version)';
  }
  final excerpt = changed.take(40).join('\n');
  return changed.length > 40
      ? '$excerpt\n… ${changed.length - 40} more lines'
      : excerpt;
}

String _relativeTime(DateTime value) {
  final difference = DateTime.now().difference(value);
  if (difference.inMinutes < 1) return 'just now';
  if (difference.inHours < 1) return '${difference.inMinutes}m ago';
  if (difference.inDays < 1) return '${difference.inHours}h ago';
  return '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}

class _SyncIconButton extends StatelessWidget {
  const _SyncIconButton({
    required this.syncing,
    required this.configured,
    required this.desktopManaged,
    required this.error,
    required this.conflicts,
    required this.result,
    required this.onPressed,
  });

  final bool syncing;
  final bool configured;
  final bool desktopManaged;
  final String? error;
  final int conflicts;
  final SyncResult? result;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final (label, icon) = desktopManaged
        ? ('Nextcloud Desktop', Icons.cloud_done_outlined)
        : !configured
        ? ('Sync not connected', Icons.cloud_off_outlined)
        : syncing
        ? ('Syncing…', Icons.sync)
        : error != null
        ? ('Sync paused', Icons.cloud_off_outlined)
        : conflicts > 0
        ? ('Needs attention', Icons.warning_amber_rounded)
        : result == null
        ? ('Ready to sync', Icons.cloud_outlined)
        : ('Up to date', Icons.cloud_done_outlined);
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
    late final IconData icon;
    late final String title;
    late final String subtitle;
    late final Color color;
    String? action;
    VoidCallback? onAction;

    if (desktopManaged) {
      icon = Icons.cloud_done_outlined;
      title = 'Nextcloud Desktop';
      subtitle = 'This folder syncs through the system.';
      color = colors.surfaceContainerHighest;
    } else if (!cloudConfigured) {
      icon = Icons.cloud_off_outlined;
      title = 'Sync not connected';
      subtitle = 'Connect Nextcloud to sync this vault.';
      color = colors.surfaceContainerHighest;
      action = 'Set up';
      onAction = onSetup;
    } else if (syncing) {
      icon = Icons.sync;
      title = 'Syncing…';
      subtitle = 'Checking this device and Nextcloud.';
      color = colors.secondaryContainer;
    } else if (error != null) {
      icon = Icons.cloud_off_outlined;
      title = 'Sync paused';
      subtitle = error!;
      color = colors.errorContainer;
      action = 'Retry';
      onAction = onSync;
    } else if (conflicts > 0) {
      icon = Icons.warning_amber_rounded;
      title =
          '$conflicts ${conflicts == 1 ? 'conflict needs' : 'conflicts need'} review';
      subtitle = 'Your files are safe. Choose which changes to keep.';
      color = colors.tertiaryContainer;
      action = 'Review';
      onAction = onReview;
    } else {
      icon = Icons.cloud_done_outlined;
      final changed = (result?.uploaded ?? 0) + (result?.downloaded ?? 0);
      title = result == null
          ? 'Ready to sync'
          : (changed == 0 ? 'Up to date' : 'Synced');
      subtitle = result == null
          ? 'No sync has completed in this session.'
          : changed == 0
          ? _lastChecked(lastSyncAt)
          : '${result!.uploaded} uploaded · ${result!.downloaded} downloaded · ${_lastChecked(lastSyncAt).toLowerCase()}';
      color = colors.primaryContainer;
      action = 'Sync now';
      onAction = onSync;
    }

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

// Kept as the settings summary content; the unified shell no longer mounts it.
// ignore: unused_element
class _PagesPanel extends StatelessWidget {
  const _PagesPanel({
    required this.activity,
    required this.current,
    required this.index,
    required this.selectedTag,
    required this.onOpenToday,
    required this.onNewPage,
    required this.onRebuildIndex,
    required this.rebuilding,
    required this.rebuildProgress,
    required this.onSync,
    required this.syncing,
    required this.cloudConfigured,
    required this.desktopManaged,
    required this.syncResult,
    required this.lastSyncAt,
    required this.syncError,
    required this.syncConflicts,
    required this.onSettings,
    required this.onKnowledge,
    required this.onReviewSync,
    required this.onSelectTag,
    required this.onOpenNote,
  });

  final String? activity;
  final String? current;
  final VaultIndex? index;
  final String? selectedTag;
  final VoidCallback onOpenToday;
  final VoidCallback onNewPage;
  final VoidCallback onRebuildIndex;
  final bool rebuilding;
  final double? rebuildProgress;
  final VoidCallback? onSync;
  final bool syncing;
  final bool cloudConfigured;
  final bool desktopManaged;
  final SyncResult? syncResult;
  final DateTime? lastSyncAt;
  final String? syncError;
  final int syncConflicts;
  final VoidCallback onSettings;
  final VoidCallback onKnowledge;
  final VoidCallback onReviewSync;
  final ValueChanged<String?> onSelectTag;
  final ValueChanged<NoteRef> onOpenNote;

  @override
  Widget build(BuildContext context) {
    final tags = <String>{
      for (final note in index?.notes ?? const <NoteRef>[]) ...note.tags,
    }.toList()..sort();
    final notes = (index?.notes ?? const <NoteRef>[])
        .where(
          (note) =>
              selectedTag == null ||
              selectedTag!.isEmpty ||
              note.tags.contains(selectedTag),
        )
        .toList();
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text('Journal', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _SyncStatusCard(
            syncing: syncing,
            cloudConfigured: cloudConfigured,
            desktopManaged: desktopManaged,
            result: syncResult,
            lastSyncAt: lastSyncAt,
            error: syncError,
            conflicts: syncConflicts,
            onSync: onSync,
            onReview: onReviewSync,
            onSetup: onSettings,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onOpenToday,
            icon: const Icon(Icons.today),
            label: const Text('Today'),
          ),
          FilledButton.tonalIcon(
            onPressed: onNewPage,
            icon: const Icon(Icons.add),
            label: const Text('New page'),
          ),
          if (activity != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                activity!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          TextButton.icon(
            onPressed: onRebuildIndex,
            icon: Icon(rebuilding ? Icons.close : Icons.refresh),
            label: Text(rebuilding ? 'Cancel rebuild' : 'Rebuild index'),
          ),
          if (rebuildProgress != null)
            LinearProgressIndicator(value: rebuildProgress),
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('Settings'),
            onTap: onSettings,
          ),
          ListTile(
            leading: const Icon(Icons.hub),
            title: const Text('Knowledge'),
            onTap: onKnowledge,
          ),
          const Divider(height: 28),
          Text('Pages', style: Theme.of(context).textTheme.labelLarge),
          if (tags.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ChoiceChip(
                  label: const Text('All'),
                  selected: selectedTag == null,
                  onSelected: (_) => onSelectTag(null),
                ),
                for (final tag in tags)
                  ChoiceChip(
                    label: Text('#$tag'),
                    selected: selectedTag == tag,
                    onSelected: (_) => onSelectTag(tag),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 4),
          for (final item in notes)
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              leading: Icon(
                item.path.startsWith('daily/') ? Icons.today : Icons.notes,
              ),
              title: Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                item.path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              selected: item.path == current,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              onTap: () => onOpenNote(item),
            ),
        ],
      ),
    );
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
  });

  final String? current;
  final List<String> outgoing;
  final List<String> backlinks;
  final List<String> fileRefs;
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
                icon: Icons.cloud,
                title: 'Nextcloud settings',
                subtitle: ready ? cloud!.serverUrl : 'Local folder only',
                onTap: onNextcloud,
              ),
              _SettingsTile(
                icon: Icons.sync,
                title: 'Sync server status',
                subtitle: syncing
                    ? 'Syncing...'
                    : (ready ? 'Ready' : 'Not configured'),
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
              entry.path,
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
  const _WorkSurface({
    required this.title,
    required this.subtitle,
    required this.status,
    required this.child,
  });

  final String title;
  final String subtitle;
  final String status;
  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          Row(
            children: [
              Expanded(
                child: Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  status,
                  style: Theme.of(context).textTheme.labelSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(child: child),
        ],
      ),
    ),
  );
}

class _TodayView extends StatefulWidget {
  const _TodayView({
    required this.index,
    required this.onCapture,
    required this.onOpenToday,
    required this.onOpenPath,
  });

  final VaultIndex? index;
  final Future<void> Function(String text) onCapture;
  final Future<void> Function() onOpenToday;
  final ValueChanged<String> onOpenPath;

  @override
  State<_TodayView> createState() => _TodayViewState();
}

class _TodayViewState extends State<_TodayView> {
  final quick = TextEditingController();

  @override
  void dispose() {
    quick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final today = _isoDay(DateTime.now());
    final notes = widget.index?.notes ?? const <NoteRef>[];
    final daily = notes
        .where((note) => note.kind == 'daily' && note.date == today)
        .firstOrNull;
    final due = (widget.index?.tasks ?? const <TaskRef>[])
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
        : widget.index?.backlinksByTarget[daily.path] ?? const <String>[];
    final calendar =
        widget.index?.calendar
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
        TextField(
          key: const Key('quick-capture'),
          controller: quick,
          minLines: 2,
          maxLines: 5,
          decoration: InputDecoration(
            hintText: 'Quick note…',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              tooltip: 'Capture',
              icon: const Icon(Icons.send),
              onPressed: () async {
                await widget.onCapture(quick.text);
                quick.clear();
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: widget.onOpenToday,
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
                onTap: () => widget.onOpenPath(task.notePath),
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
                onTap: () => widget.onOpenPath(item.notePath),
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
                onTap: () => widget.onOpenPath(item.path),
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
                title: Text(widget.index?.notesByPath[path]?.title ?? path),
                onTap: () => widget.onOpenPath(path),
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
                onTap: () => widget.onOpenPath(item.path),
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
  const _LibraryView({required this.index, required this.onOpenPath});

  final VaultIndex? index;
  final ValueChanged<String> onOpenPath;

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
              ListView(
                children: [
                  for (final item in index?.calendar ?? const <CalendarItem>[])
                    ListTile(
                      leading: const Icon(Icons.event),
                      title: Text(item.title),
                      subtitle: Text(item.date),
                      onTap: () => onOpenPath(item.notePath),
                    ),
                ],
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

class _ControlledEditorView extends StatefulWidget {
  const _ControlledEditorView({required this.source, required this.onChanged});

  final String source;
  final ValueChanged<String> onChanged;

  @override
  State<_ControlledEditorView> createState() => _ControlledEditorViewState();
}

class _ControlledEditorViewState extends State<_ControlledEditorView> {
  final controller = TextEditingController();
  final focusNode = FocusNode();
  int? editingIndex;
  String baseSource = '';
  TextRange editRange = TextRange.empty;

  @override
  void dispose() {
    controller.dispose();
    focusNode.dispose();
    super.dispose();
  }

  void _edit(int index, ControlledBlock block) {
    baseSource = widget.source;
    editRange = TextRange(start: block.start, end: block.end);
    controller.value = TextEditingValue(
      text: block.source,
      selection: TextSelection.collapsed(offset: block.source.length),
    );
    setState(() => editingIndex = index);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => focusNode.requestFocus(),
    );
  }

  void _change(String value) => widget.onChanged(
    baseSource.replaceRange(editRange.start, editRange.end, value),
  );

  void _done() {
    focusNode.unfocus();
    setState(() => editingIndex = null);
  }

  Widget _editor() => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            key: const Key('controlled-block-editor'),
            controller: controller,
            focusNode: focusNode,
            minLines: 1,
            maxLines: null,
            style: const TextStyle(fontFamily: 'monospace'),
            onChanged: _change,
          ),
        ),
        IconButton(
          tooltip: 'Done editing block',
          onPressed: _done,
          icon: const Icon(Icons.check),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final blocks = parseControlledTypst(widget.source).blocks;
    if (blocks.isEmpty) {
      if (editingIndex != null) {
        return ListView(
          padding: const EdgeInsets.all(18),
          children: [_editor()],
        );
      }
      return Center(
        child: FilledButton.tonalIcon(
          onPressed: () => _edit(
            0,
            ControlledBlock(
              start: widget.source.length,
              end: widget.source.length,
              source: '',
              kind: ControlledBlockKind.paragraph,
              supported: true,
            ),
          ),
          icon: const Icon(Icons.edit),
          label: const Text('Start writing'),
        ),
      );
    }
    final itemCount = editingIndex != null && editingIndex! >= blocks.length
        ? editingIndex! + 1
        : blocks.length;
    return ListView.builder(
      padding: const EdgeInsets.all(18),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (editingIndex == index) return _editor();
        final block = blocks[index];
        final raw = block.kind == ControlledBlockKind.raw;
        final preview = controlledBlockPreview(block);
        final style = block.kind == ControlledBlockKind.heading
            ? Theme.of(context).textTheme.headlineSmall
            : Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.45);
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Material(
            color: raw
                ? Theme.of(context).colorScheme.surfaceContainerLow
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              key: ValueKey('controlled-block-$index'),
              borderRadius: BorderRadius.circular(12),
              onTap: () => _edit(index, block),
              child: Padding(
                padding: raw
                    ? const EdgeInsets.all(12)
                    : const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (raw) ...[
                      const Icon(Icons.code, size: 20),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(
                        preview.isEmpty ? 'Empty block' : preview,
                        style: style,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
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

// ignore: unused_element
class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.mode,
    required this.value,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final String mode;
  final String value;
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton.filledTonal(
    isSelected: mode == value,
    onPressed: onPressed,
    icon: Icon(icon),
    tooltip: tooltip,
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
