import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_file/open_file.dart';
import 'package:typst_flutter/typst_flutter.dart';

import 'graph.dart';
import 'knowledge_screen.dart';
import 'models.dart';
import 'nextcloud_sync.dart';
import 'pkms_publisher.dart';
import 'pkms_registry.dart';
import 'scanner.dart';
import 'search_index.dart';
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
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3F6F68)),
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
  final controller = TextEditingController();
  final sourceController = TextEditingController();
  Timer? autosave;
  Timer? cloudAutosave;
  Timer? cloudPoll;
  String status = 'Opening vault...';
  bool dirty = false;
  String mode = 'journal';
  String previewSource = '';
  String hiddenSystemPrefix = '';
  String helperSource = tylogHelperSource;
  NextcloudConfig? cloud;
  PkmsTagRegistry tags = PkmsTagRegistry.empty;
  PkmsFileRegistry files = PkmsFileRegistry.empty;
  PkmsCollectionRegistry collections = PkmsCollectionRegistry.empty;
  PkmsSearchIndex searchIndex = PkmsSearchIndex.empty();
  PkmsValidationReport? validation;
  SyncResult? lastSync;
  DateTime? lastSyncAt;
  String? syncError;
  String? selectedTag;
  bool syncing = false;
  bool rebuilding = false;
  bool cancelRebuild = false;
  double? rebuildProgress;
  bool leftPanelOpen = true;
  bool rightPanelOpen = true;
  VaultRegistry? vaultRegistry;

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
    controller.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    try {
      final registry = await VaultRegistry.load();
      vaultRegistry = registry;
      await _openVault(registry.active, trigger: 'startup');
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
        tags = pkms.data.tags;
        files = pkms.data.files;
        collections = pkms.data.collections;
        validation = _retainValidation(pkms.report);
        searchIndex = pkms.search;
        helperSource = loadedHelper;
        cloud = entry.cloud;
        selectedTag = null;
        lastSync = null;
        lastSyncAt = null;
        syncError = null;
        status = '$openStatus · ${pkms.report.summary()}';
      });
      if (entry.cloud != null && entry.cloud!.isReady) {
        if (trigger != null) unawaited(_syncNow(trigger: trigger));
        _startCloudPolling();
      }
    } catch (e) {
      setState(() => status = 'Open failed: $e');
    }
  }

  Future<({PkmsData data, PkmsValidationReport report, PkmsSearchIndex search})>
  _readPkms(Vault v, VaultIndex ix) async {
    final data = await loadPkmsData(v.root);
    final report = await validatePkms(v.root, ix, data: data);
    final cached = await PkmsSearchIndex.load(v.searchIndexFile);
    final search = await PkmsSearchIndex.build(
      v.root,
      ix,
      data.files,
      previous: cached,
    );
    await search.save(v.searchIndexFile);
    return (data: data, report: report, search: search);
  }

  Future<void> _switchVault(VaultEntry entry) async {
    final registry = vaultRegistry;
    if (registry == null || registry.activeId == entry.id) return;
    if (dirty) await _save(syncAfter: false);
    await registry.select(entry);
    await _openVault(entry);
  }

  Future<void> _pickVault() async {
    Navigator.pop(context);
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose vault folder',
    );
    if (path == null) return;
    try {
      final probe = File('$path/.tylog-access-test.tmp');
      await probe.writeAsString('ok', flush: true);
      await probe.delete();
    } catch (e) {
      if (mounted) {
        setState(() => status = 'Selected folder is not writable: $e');
      }
      return;
    }
    final registry = vaultRegistry!;
    final entry = await registry.add(path);
    await _switchVault(entry);
    if (registry.activeId != entry.id) {
      await registry.select(entry);
      await _openVault(entry);
    }
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

  Future<void> _save({bool syncAfter = true}) async {
    autosave?.cancel();
    final v = vault;
    final n = note;
    if (v == null || n == null) return;
    try {
      await v.saveNote(n, _currentSource());
      final ix = await v.rebuildIndex();
      final pkms = await _readPkms(v, ix);
      setState(() {
        index = _retainIndex(ix);
        tags.tags
          ..clear()
          ..addAll(pkms.data.tags.tags);
        files.files
          ..clear()
          ..addAll(pkms.data.files.files);
        collections.collections
          ..clear()
          ..addAll(pkms.data.collections.collections);
        validation = _retainValidation(pkms.report);
        searchIndex.replaceWith(pkms.search);
        dirty = false;
        status = 'Saved ${v.relativePath(n)} · ${pkms.report.summary()}';
      });
      if (syncAfter) _queueCloudSync();
    } catch (e) {
      setState(() => status = 'Save failed: $e');
    }
  }

  void _queueCloudSync() {
    final cfg = cloud;
    if (cfg == null || !cfg.isReady || syncing) return;
    cloudAutosave?.cancel();
    cloudAutosave = Timer(const Duration(seconds: 2), () {
      if (!syncing && !dirty) unawaited(_syncNow(trigger: 'autosave'));
    });
  }

  void _startCloudPolling() {
    cloudPoll?.cancel();
    final cfg = cloud;
    if (cfg == null || !cfg.isReady) return;
    cloudPoll = Timer.periodic(const Duration(seconds: 25), (_) {
      if (!syncing && !dirty && mounted) unawaited(_syncNow(trigger: 'poll'));
    });
  }

  void _queueAutosave() {
    setState(() {
      dirty = true;
      status = 'Autosave pending...';
    });
    autosave?.cancel();
    autosave = Timer(const Duration(milliseconds: 700), _save);
  }

  String _currentSource() => mode == 'source'
      ? sourceController.text
      : '$hiddenSystemPrefix${controller.text}';

  void _loadSource(String source) {
    final clean = _splitCleanSource(source);
    hiddenSystemPrefix = clean.hiddenPrefix;
    controller.text = clean.body;
    sourceController.text = source;
  }

  Future<void> _openNote(File file) async {
    final v = vault;
    if (v == null) return;
    if (dirty) await _save();
    _loadSource(await file.readAsString());
    setState(() {
      note = file;
      dirty = false;
      mode = 'journal';
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
    final links = TextEditingController(text: current.outgoingLinks.join(', '));
    final fileRefs = TextEditingController(text: current.fileRefs.join(', '));
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
                controller: links,
                decoration: const InputDecoration(
                  labelText: 'Linked note IDs, comma-separated',
                ),
              ),
              TextField(
                controller: fileRefs,
                decoration: const InputDecoration(
                  labelText: 'File IDs, comma-separated',
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
          date: current.date,
          tags: _csvValues(tagsText.text),
          aliases: _csvValues(aliases.text),
          links: _csvValues(links.text),
          files: _csvValues(fileRefs.text),
        ),
      );
      _loadSource(updated);
      dirty = true;
      await _save();
    }
    for (final value in [title, tagsText, aliases, links, fileRefs]) {
      value.dispose();
    }
  }

  Future<void> _showKnowledge() async {
    final v = vault;
    final ix = index;
    if (v == null || ix == null) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => KnowledgeScreen(
          index: ix,
          search: searchIndex,
          tags: tags,
          files: files,
          collections: collections,
          problems: validation?.problems ?? ix.problems,
          onOpenNote: _openPath,
          onOpenFile: _openRegisteredFile,
          onSaveTag: _saveTag,
          onDeleteTag: _deleteTag,
          onMergeTag: _mergeTag,
          onImportFile: _importFile,
          onSaveFile: _saveFile,
          onDeleteFile: _deleteFile,
          onSaveCollection: _saveCollection,
          onExportCollection: _exportCollection,
          onMigrateLegacy: _migrateLegacyNotes,
          onResolveConflict: _resolveConflict,
          onCleanSyncCaches: _cleanSyncCaches,
        ),
      ),
    );
  }

  Future<void> _saveTag(PkmsTagEntry entry) async {
    final v = vault;
    if (v == null) return;
    if (_registryBlocked('tags-registry-invalid')) return;
    tags.tags[entry.slug] = entry;
    await saveTagRegistry(v.root, tags);
    await _refreshPkms('Tag saved');
  }

  Future<void> _deleteTag(String slug) async {
    if (_registryBlocked('tags-registry-invalid')) return;
    final inUse =
        (index?.notes.any((note) => note.tags.contains(slug)) ?? false) ||
        files.files.values.any((file) => file.tags.contains(slug));
    if (inUse) {
      setState(() => status = 'Cannot delete #$slug while it is in use');
      return;
    }
    final v = vault;
    if (v == null) return;
    tags.tags.remove(slug);
    await saveTagRegistry(v.root, tags);
    await _refreshPkms('Tag deleted');
  }

  Future<void> _mergeTag(String from, String to) async {
    final v = vault;
    final ix = index;
    if (_registryBlocked('tags-registry-invalid') ||
        _registryBlocked('files-registry-invalid')) {
      return;
    }
    if (v == null || ix == null || from == to || !tags.tags.containsKey(to)) {
      return;
    }
    final affected = ix.notes
        .where((note) => note.tags.contains(from))
        .toList();
    final backup = Directory(
      '${v.meta.path}/backups/${DateTime.now().millisecondsSinceEpoch}',
    );
    for (final noteRef in affected) {
      final file = File('${v.root.path}/${noteRef.path}');
      final original = await file.readAsString();
      final backupFile = File('${backup.path}/${noteRef.path}');
      await backupFile.parent.create(recursive: true);
      await file.copy(backupFile.path);
      var source = original;
      final inline = locateTypstCalls(source, names: const {'tag'})
          .where(
            (call) => RegExp(
              '#tag\\(\\s*"${RegExp.escape(from)}"',
            ).hasMatch(call.source),
          )
          .toList()
          .reversed;
      for (final call in inline) {
        source = source.replaceRange(call.start, call.end, '#tag("$to")');
      }
      final nextTags =
          noteRef.tags.map((tag) => tag == from ? to : tag).toSet().toList()
            ..sort();
      await v.saveNote(
        file,
        replaceNoteHeader(
          source,
          NoteMetadataDraft(
            id: noteRef.id,
            title: noteRef.title,
            date: noteRef.date,
            tags: nextTags,
            aliases: noteRef.aliases,
            links: noteRef.outgoingLinks,
            files: noteRef.fileRefs,
          ),
        ),
      );
    }
    for (final entry in files.files.entries.toList()) {
      if (!entry.value.tags.contains(from)) continue;
      final nextTags =
          entry.value.tags.map((tag) => tag == from ? to : tag).toSet().toList()
            ..sort();
      files.files[entry.key] = entry.value.copyWith(tags: nextTags);
    }
    tags.tags.remove(from);
    await saveTagRegistry(v.root, tags);
    await saveFileRegistry(v.root, files);
    await _rebuildIndex();
    if (mounted) {
      setState(
        () => status = 'Merged #$from into #$to; backup: ${backup.path}',
      );
    }
  }

  Future<void> _importFile() async {
    final v = vault;
    if (v == null) return;
    if (_registryBlocked('files-registry-invalid')) return;
    final picked = await FilePicker.platform.pickFiles();
    final sourcePath = picked?.files.single.path;
    if (sourcePath == null) return;
    final source = File(sourcePath);
    final original = source.path.split(Platform.pathSeparator).last;
    var targetName = original;
    var suffix = 2;
    while (await File('${v.assets.path}/$targetName').exists()) {
      final dot = original.lastIndexOf('.');
      targetName = dot < 0
          ? '$original-${suffix++}'
          : '${original.substring(0, dot)}-${suffix++}${original.substring(dot)}';
    }
    await v.assets.create(recursive: true);
    await source.copy('${v.assets.path}/$targetName');
    var id = _slugValue(targetName.replaceFirst(RegExp(r'\.[^.]+$'), ''));
    if (id.isEmpty) id = DateTime.now().millisecondsSinceEpoch.toString();
    final base = id;
    suffix = 2;
    while (files.files.containsKey(id)) {
      id = '$base-${suffix++}';
    }
    files.files[id] = PkmsFileEntry(
      id: id,
      path: 'assets/$targetName',
      title: original,
      kind: original.contains('.')
          ? original.split('.').last.toLowerCase()
          : 'file',
      status: 'reference',
    );
    await saveFileRegistry(v.root, files);
    await _refreshPkms('File imported');
  }

  Future<void> _saveFile(PkmsFileEntry entry) async {
    final v = vault;
    if (v == null || !isSafeVaultPath(entry.path)) return;
    if (_registryBlocked('files-registry-invalid')) return;
    files.files[entry.id] = entry;
    await saveFileRegistry(v.root, files);
    await _refreshPkms('File metadata saved');
  }

  Future<void> _deleteFile(String id) async {
    final v = vault;
    if (v == null) return;
    if (_registryBlocked('files-registry-invalid')) return;
    files.files.remove(id);
    await saveFileRegistry(v.root, files);
    await _refreshPkms('File registry entry removed; asset kept');
  }

  Future<void> _openRegisteredFile(PkmsFileEntry entry) async {
    final v = vault;
    if (v == null || !isSafeVaultPath(entry.path)) return;
    final result = await OpenFile.open('${v.root.path}/${entry.path}');
    if (result.type != ResultType.done && mounted) {
      setState(() => status = 'Could not open file: ${result.message}');
    }
  }

  Future<void> _saveCollection(PkmsCollectionEntry entry) async {
    final v = vault;
    if (v == null) return;
    if (_registryBlocked('collections-registry-invalid')) return;
    collections.collections[entry.id] = entry;
    await saveCollectionRegistry(v.root, collections);
    await _refreshPkms('Collection saved');
  }

  Future<void> _exportCollection(PkmsCollectionEntry entry) async {
    final v = vault;
    final ix = index;
    if (v == null || ix == null) return;
    final output = await FilePicker.platform.saveFile(
      dialogTitle: 'Export collection PDF',
      fileName: '${_slugValue(entry.title)}.pdf',
    );
    if (output == null) return;
    setState(() => status = 'Exporting ${entry.title}...');
    try {
      await exportPkmsCollection(
        root: v.root,
        index: ix,
        files: files,
        collection: entry,
        output: File(output),
      );
      if (mounted) setState(() => status = 'Exported $output');
    } catch (error) {
      if (mounted) setState(() => status = 'Export failed: $error');
    }
  }

  Future<void> _migrateLegacyNotes() async {
    final v = vault;
    final ix = index;
    if (v == null || ix == null) return;
    final candidates = <(NoteRef, File, String)>[];
    for (final noteRef in ix.notes) {
      final file = File('${v.root.path}/${noteRef.path}');
      final source = await file.readAsString();
      final header = locateTypstCalls(
        source,
        names: const {'note'},
      ).firstOrNull?.source;
      if (header == null || !RegExp(r'\bid\s*:').hasMatch(header)) {
        candidates.add((noteRef, file, source));
      }
    }
    if (candidates.isEmpty || !mounted) {
      setState(() => status = 'No legacy note IDs need migration');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Migrate legacy notes?'),
        content: Text(
          'Add stable IDs to ${candidates.length} notes. Original files will be copied to a timestamped backup first.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Back up and migrate'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final backup = Directory(
      '${v.meta.path}/backups/${DateTime.now().millisecondsSinceEpoch}',
    );
    final usedIds = ix.notes.map((note) => note.id).toSet();
    for (final (noteRef, file, source) in candidates) {
      final backupFile = File('${backup.path}/${noteRef.path}');
      await backupFile.parent.create(recursive: true);
      await file.copy(backupFile.path);
      final generated = await v.nextNoteId(
        noteRef.title,
        now: await file.lastModified(),
      );
      var id = generated;
      var suffix = 2;
      while (usedIds.contains(id)) {
        id = '$generated-${suffix++}';
      }
      usedIds.add(id);
      await v.saveNote(
        file,
        replaceNoteHeader(
          source,
          NoteMetadataDraft(
            id: id,
            title: noteRef.title,
            date: noteRef.date,
            tags: noteRef.tags,
            aliases: noteRef.aliases,
            links: noteRef.outgoingLinks,
            files: noteRef.fileRefs,
          ),
        ),
      );
    }
    await _rebuildIndex();
    if (mounted) {
      setState(
        () => status =
            'Migrated ${candidates.length} notes; backup: ${backup.path}',
      );
    }
  }

  Future<void> _refreshPkms(String message) async {
    final v = vault;
    final ix = index;
    if (v == null || ix == null) return;
    final pkms = await _readPkms(v, ix);
    if (!mounted) return;
    setState(() {
      tags.tags
        ..clear()
        ..addAll(pkms.data.tags.tags);
      files.files
        ..clear()
        ..addAll(pkms.data.files.files);
      collections.collections
        ..clear()
        ..addAll(pkms.data.collections.collections);
      validation = _retainValidation(pkms.report);
      searchIndex.replaceWith(pkms.search);
      status = '$message · ${pkms.report.summary()}';
    });
  }

  bool _registryBlocked(String code) {
    if (!(validation?.problems.any((problem) => problem.code == code) ??
        false)) {
      return false;
    }
    setState(
      () =>
          status = 'Registry is malformed; repair its JSON before editing it.',
    );
    return true;
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
    current.fileBacklinksById
      ..clear()
      ..addAll(next.fileBacklinksById);
    current.problems
      ..clear()
      ..addAll(next.problems);
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
        tags.tags
          ..clear()
          ..addAll(pkms.data.tags.tags);
        files.files
          ..clear()
          ..addAll(pkms.data.files.files);
        collections.collections
          ..clear()
          ..addAll(pkms.data.collections.collections);
        validation = _retainValidation(pkms.report);
        searchIndex.replaceWith(pkms.search);
        status = 'Index rebuilt · ${pkms.report.summary()}';
      });
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
    setState(() {
      syncing = true;
      syncError = null;
      status = 'Syncing Nextcloud...';
    });
    try {
      cloudAutosave?.cancel();
      if (dirty) await _save(syncAfter: false);
      final result = await NextcloudSync(cfg).sync(v, trigger: trigger);
      if (note != null && await note!.exists()) {
        _loadSource(await note!.readAsString());
      }
      final ix = await v.rebuildIndex();
      final pkms = await _readPkms(v, ix);
      setState(() {
        index = _retainIndex(ix);
        tags.tags
          ..clear()
          ..addAll(pkms.data.tags.tags);
        files.files
          ..clear()
          ..addAll(pkms.data.files.files);
        collections.collections
          ..clear()
          ..addAll(pkms.data.collections.collections);
        validation = _retainValidation(pkms.report);
        searchIndex.replaceWith(pkms.search);
        lastSync = result;
        lastSyncAt = DateTime.now();
        status = '$result · ${pkms.report.summary()}';
      });
    } catch (e) {
      setState(() {
        syncError = _friendlySyncError(e);
        status = 'Sync failed: $e';
      });
    } finally {
      setState(() => syncing = false);
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
    final localModified = await original.exists()
        ? await original.lastModified()
        : null;
    final remoteModified = await conflict.lastModified();
    if (!mounted) return;
    final merged = TextEditingController(text: localText);
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
              LayoutBuilder(
                builder: (context, constraints) {
                  final cards = [
                    _ConflictVersionCard(
                      title: 'This device',
                      text: localText,
                      otherText: remoteText,
                      modified: localModified,
                      color: Theme.of(context).colorScheme.primaryContainer,
                      onUse: () => merged.text = localText,
                    ),
                    _ConflictVersionCard(
                      title: 'Nextcloud copy',
                      text: remoteText,
                      otherText: localText,
                      modified: remoteModified,
                      color: Theme.of(context).colorScheme.tertiaryContainer,
                      onUse: () => merged.text = remoteText,
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
    }
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
      if (original == '.tylog/index.json' ||
          original == '.tylog/search-index.json.gz') {
        await entity.delete();
      }
    }
    await _refreshPkms('Old sync caches removed');
  }

  Future<void> _showSyncSettings() async {
    final cfg = cloud;
    final url = TextEditingController(text: cfg?.serverUrl ?? '');
    final user = TextEditingController(text: cfg?.username ?? '');
    final pass = TextEditingController(text: cfg?.password ?? '');
    final saved = await showDialog<NextcloudConfig>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nextcloud'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: url,
              decoration: const InputDecoration(labelText: 'Server URL'),
            ),
            TextField(
              controller: user,
              decoration: const InputDecoration(labelText: 'Login'),
            ),
            TextField(
              controller: pass,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              NextcloudConfig(
                serverUrl: url.text,
                username: user.text,
                password: pass.text,
              ),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved == null) return;
    final registry = vaultRegistry!;
    await registry.setCloud(registry.active, saved);
    setState(() {
      cloud = saved;
      status = 'Nextcloud saved';
    });
    _startCloudPolling();
    unawaited(_syncNow(trigger: 'settings'));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
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
            onAddVault: _pickVault,
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
          ),
        ),
      ),
    );
  }

  void _showQuickActions() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.today),
              title: const Text('Today'),
              onTap: () {
                Navigator.pop(context);
                _openToday();
              },
            ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('New page'),
              onTap: () {
                Navigator.pop(context);
                _newPage();
              },
            ),
            ListTile(
              leading: const Icon(Icons.hub),
              title: const Text('Knowledge'),
              onTap: () {
                Navigator.pop(context);
                _showKnowledge();
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Settings'),
              onTap: () {
                Navigator.pop(context);
                _showSettings();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openPath(String path) async {
    final v = vault;
    if (v == null) return;
    await _openNote(File('${v.root.path}/$path'));
  }

  void _showPreview() {
    setState(() {
      previewSource = _currentSource();
      mode = 'preview';
    });
  }

  void _showJournal() {
    if (mode == 'source') _loadSource(sourceController.text);
    setState(() => mode = 'journal');
  }

  void _showSource() {
    sourceController.text = _currentSource();
    setState(() => mode = 'source');
  }

  void _toggleSourcePreview() =>
      mode == 'source' ? _showPreview() : _showSource();

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
    final pagesPanel = _PagesPanel(
      activity: _panelActivity(status),
      current: current,
      index: index,
      selectedTag: selectedTag,
      onOpenToday: _openToday,
      onNewPage: _newPage,
      onRebuildIndex: _rebuildIndex,
      rebuilding: rebuilding,
      rebuildProgress: rebuildProgress,
      onSync: syncing ? null : _syncNow,
      syncing: syncing,
      cloudConfigured: cloud?.isReady ?? false,
      desktopManaged: v != null && isNextcloudManagedVault(v.root),
      syncResult: lastSync,
      lastSyncAt: lastSyncAt,
      syncError: syncError,
      syncConflicts: syncConflicts,
      onSettings: _showSettings,
      onKnowledge: _showKnowledge,
      onSelectTag: (value) => setState(() => selectedTag = value),
      onOpenNote: (item) =>
          v == null ? null : _openNote(File('${v.root.path}/${item.path}')),
    );
    final linksPanel = _LinksPanel(
      current: current,
      outgoing: outgoing,
      backlinks: backlinks,
      fileRefs: current == null
          ? const <String>[]
          : index?.notesByPath[current]?.fileRefs ?? const <String>[],
      index: index,
      files: files,
      resolveLink: resolver?.resolve ?? _resolveLink,
      onOpenLink: _openLink,
      onOpenPath: _openPath,
      onOpenFile: _openRegisteredFile,
      onEditMetadata: _editCurrentMetadata,
    );
    final workArea = _WorkSurface(
      title: currentTitle,
      subtitle: current ?? 'daily journal',
      child: switch (mode) {
        'graph' => GraphView(
          graph: graph ?? const NoteGraph(nodes: [], edges: []),
          currentPath: current,
          onOpenPath: _openPath,
        ),
        'preview' => TypstDocumentViewer(
          source: previewSource.isEmpty ? _currentSource() : previewSource,
          files: FileSource.bytes({
            '.tylog/tylog.typ': Uint8List.fromList(utf8.encode(helperSource)),
            '/.tylog/tylog.typ': Uint8List.fromList(utf8.encode(helperSource)),
          }),
          loadingBuilder: (_) =>
              const Center(child: CircularProgressIndicator()),
          errorBuilder: (_, error) => Padding(
            padding: const EdgeInsets.all(16),
            child: SelectableText('Typst error:\n$error'),
          ),
        ),
        'source' => _Editor(
          controller: sourceController,
          onChanged: _queueAutosave,
          monospace: true,
        ),
        _ => _Editor(controller: controller, onChanged: _queueAutosave),
      },
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 800;
        return Scaffold(
          drawer: compact ? Drawer(child: SafeArea(child: pagesPanel)) : null,
          endDrawer: compact
              ? Drawer(child: SafeArea(child: linksPanel))
              : null,
          appBar: AppBar(
            centerTitle: false,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(dirty ? 'TyLog *' : 'TyLog'),
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
                icon: const Icon(Icons.hub),
                tooltip: 'Knowledge',
              ),
              if (!compact) ...[
                IconButton(
                  onPressed: () =>
                      setState(() => leftPanelOpen = !leftPanelOpen),
                  icon: const Icon(Icons.view_sidebar),
                  tooltip: 'Pages',
                ),
                IconButton(
                  onPressed: () =>
                      setState(() => rightPanelOpen = !rightPanelOpen),
                  icon: const Icon(Icons.notes),
                  tooltip: 'Backlinks',
                ),
                _ModeButton(
                  mode: mode,
                  value: 'journal',
                  icon: Icons.edit_note,
                  tooltip: 'Journal',
                  onPressed: _showJournal,
                ),
                _ModeButton(
                  mode: mode,
                  value: mode == 'preview' ? 'preview' : 'source',
                  icon: Icons.code,
                  tooltip: mode == 'source' ? 'Preview' : 'Source',
                  onPressed: _toggleSourcePreview,
                ),
                _ModeButton(
                  mode: mode,
                  value: 'graph',
                  icon: Icons.account_tree,
                  tooltip: 'Graph',
                  onPressed: () => setState(() => mode = 'graph'),
                ),
                IconButton(
                  onPressed: syncing ? null : _syncNow,
                  icon: const Icon(Icons.sync),
                  tooltip: 'Sync',
                ),
              ],
              if (compact)
                IconButton(
                  onPressed: _toggleSourcePreview,
                  icon: const Icon(Icons.code),
                  tooltip: mode == 'source' ? 'Preview' : 'Source',
                ),
              if (compact)
                Builder(
                  builder: (context) => IconButton(
                    onPressed: () => Scaffold.of(context).openEndDrawer(),
                    icon: const Icon(Icons.link),
                    tooltip: 'Backlinks',
                  ),
                ),
            ],
          ),
          body: compact
              ? workArea
              : Row(
                  children: [
                    if (leftPanelOpen) SizedBox(width: 280, child: pagesPanel),
                    Expanded(child: workArea),
                    if (rightPanelOpen) SizedBox(width: 300, child: linksPanel),
                  ],
                ),
          bottomNavigationBar: compact
              ? NavigationBar(
                  selectedIndex: _modeIndex(mode),
                  onDestinationSelected: (value) {
                    if (value == 1) {
                      _showPreview();
                    } else if (value == 0) {
                      _showJournal();
                    } else {
                      setState(() => mode = 'graph');
                    }
                  },
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.today),
                      label: 'Journal',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.preview),
                      label: 'Preview',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.account_tree),
                      label: 'Graph',
                    ),
                  ],
                )
              : null,
          floatingActionButton: FloatingActionButton(
            onPressed: _showQuickActions,
            tooltip: 'Quick actions',
            child: const Icon(Icons.add),
          ),
        );
      },
    );
  }

  String _currentTitle(String? current) => current == null
      ? 'Today'
      : index?.notesByPath[current]?.title ??
            current.split('/').last.replaceFirst('.typ', '');

  int _modeIndex(String value) => switch (value) {
    'preview' => 1,
    'graph' => 2,
    _ => 0,
  };
}

class _CleanSource {
  const _CleanSource(this.hiddenPrefix, this.body);

  final String hiddenPrefix;
  final String body;
}

_CleanSource _splitCleanSource(String source) {
  final lines = source.split('\n');
  var index = 0;
  while (index < lines.length) {
    final trimmed = lines[index].trimLeft();
    if (trimmed.isEmpty) {
      index++;
      continue;
    }
    if (!_isSystemLine(trimmed)) break;

    var depth =
        '('.allMatches(lines[index]).length -
        ')'.allMatches(lines[index]).length;
    index++;
    while (depth > 0 && index < lines.length) {
      depth +=
          '('.allMatches(lines[index]).length -
          ')'.allMatches(lines[index]).length;
      index++;
    }
  }
  while (index < lines.length && lines[index].trim().isEmpty) {
    index++;
  }
  final prefix = index == 0 ? '' : '${lines.take(index).join('\n')}\n';
  return _CleanSource(prefix, lines.skip(index).join('\n'));
}

bool _isSystemLine(String line) =>
    RegExp(r'^#(import|include|show|set|let|note)\b').hasMatch(line);

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
    required this.color,
    required this.onUse,
  });

  final String title;
  final String text;
  final String otherText;
  final DateTime? modified;
  final Color color;
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) => Card(
    color: color,
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          Text(
            '${text.length} characters${modified == null ? '' : ' · ${_shortTime(modified!)}'}',
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
          OutlinedButton(onPressed: onUse, child: Text('Use $title')),
        ],
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

String _shortTime(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')} '
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

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
            onReview: onKnowledge,
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
                item.path.startsWith('journal/') ? Icons.today : Icons.notes,
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
    required this.files,
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
  final PkmsFileRegistry files;
  final LinkResolution Function(String title) resolveLink;
  final ValueChanged<String> onOpenLink;
  final ValueChanged<String> onOpenPath;
  final ValueChanged<PkmsFileEntry> onOpenFile;
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
        for (final id in fileRefs)
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            leading: const Icon(Icons.attach_file),
            title: Text(files.files[id]?.displayTitle ?? id),
            subtitle: Text(files.files[id]?.path ?? 'Unknown file id'),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            onTap: files.files[id] == null
                ? null
                : () => onOpenFile(files.files[id]!),
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

  @override
  Widget build(BuildContext context) {
    final ready = cloud?.isReady ?? false;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Settings', style: Theme.of(context).textTheme.headlineSmall),
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
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surface,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          Expanded(
            child: Card(
              elevation: 0,
              clipBehavior: Clip.antiAlias,
              color: Theme.of(context).colorScheme.surfaceContainerLowest,
              child: child,
            ),
          ),
        ],
      ),
    ),
  );
}

class _Editor extends StatelessWidget {
  const _Editor({
    required this.controller,
    required this.onChanged,
    this.monospace = false,
  });

  final TextEditingController controller;
  final VoidCallback onChanged;
  final bool monospace;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    expands: true,
    maxLines: null,
    minLines: null,
    textAlignVertical: TextAlignVertical.top,
    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
      height: 1.45,
      fontFamily: monospace ? 'monospace' : null,
    ),
    decoration: const InputDecoration(contentPadding: EdgeInsets.all(18)),
    onChanged: (_) => onChanged(),
  );
}

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

String _slugValue(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-|-$'), '');

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
