import 'package:flutter/material.dart';

import 'models.dart';
import 'pkms_registry.dart';
import 'search_index.dart';

class KnowledgeScreen extends StatefulWidget {
  const KnowledgeScreen({
    super.key,
    this.initialTab = 0,
    required this.index,
    required this.search,
    required this.tags,
    required this.files,
    required this.collections,
    required this.problems,
    required this.onOpenNote,
    required this.onOpenFile,
    required this.onSaveTag,
    required this.onDeleteTag,
    required this.onMergeTag,
    required this.onImportFile,
    required this.onSaveFile,
    required this.onDeleteFile,
    required this.onSaveCollection,
    required this.onExportCollection,
    required this.onMigrateLegacy,
    required this.onResolveConflict,
    required this.onCleanSyncCaches,
  });

  final VaultIndex index;
  final int initialTab;
  final PkmsSearchIndex search;
  final PkmsTagRegistry tags;
  final PkmsFileRegistry files;
  final PkmsCollectionRegistry collections;
  final List<PkmsProblem> problems;
  final ValueChanged<String> onOpenNote;
  final ValueChanged<PkmsFileEntry> onOpenFile;
  final Future<void> Function(PkmsTagEntry) onSaveTag;
  final Future<void> Function(String) onDeleteTag;
  final Future<void> Function(String from, String to) onMergeTag;
  final Future<void> Function() onImportFile;
  final Future<void> Function(PkmsFileEntry) onSaveFile;
  final Future<void> Function(String) onDeleteFile;
  final Future<void> Function(PkmsCollectionEntry) onSaveCollection;
  final Future<void> Function(PkmsCollectionEntry) onExportCollection;
  final Future<void> Function() onMigrateLegacy;
  final Future<void> Function(PkmsProblem) onResolveConflict;
  final Future<void> Function() onCleanSyncCaches;

  @override
  State<KnowledgeScreen> createState() => _KnowledgeScreenState();
}

class _KnowledgeScreenState extends State<KnowledgeScreen> {
  String query = '';
  String? selectedTag;
  String? selectedFileKind;
  String? selectedStatus;

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 5,
    initialIndex: widget.initialTab,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Knowledge'),
        bottom: const TabBar(
          isScrollable: true,
          tabs: [
            Tab(icon: Icon(Icons.search), text: 'Search'),
            Tab(icon: Icon(Icons.sell), text: 'Tags'),
            Tab(icon: Icon(Icons.attach_file), text: 'Files'),
            Tab(icon: Icon(Icons.rule), text: 'Problems'),
            Tab(icon: Icon(Icons.collections_bookmark), text: 'Collections'),
          ],
        ),
      ),
      body: TabBarView(
        children: [
          _searchTab(),
          _tagsTab(),
          _filesTab(),
          _problemsTab(),
          _collectionsTab(),
        ],
      ),
    ),
  );

  Widget _searchTab() {
    final results = widget.search.search(
      query,
      tag: selectedTag,
      fileKind: selectedFileKind,
      status: selectedStatus,
    );
    final tags = widget.tags.tags.keys.toList()..sort();
    final kinds =
        widget.files.files.values.map((file) => file.kind).toSet().toList()
          ..sort();
    final statuses =
        widget.files.files.values.map((file) => file.status).toSet().toList()
          ..sort();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          autofocus: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.search),
            hintText: 'Search notes and files',
          ),
          onChanged: (value) => setState(() => query = value),
        ),
        if (tags.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            children: [
              ChoiceChip(
                label: const Text('All'),
                selected: selectedTag == null,
                onSelected: (_) => setState(() => selectedTag = null),
              ),
              for (final tag in tags)
                ChoiceChip(
                  label: Text('#$tag'),
                  selected: selectedTag == tag,
                  onSelected: (_) => setState(() => selectedTag = tag),
                ),
            ],
          ),
        ],
        if (kinds.isNotEmpty || statuses.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: selectedFileKind,
                  decoration: const InputDecoration(labelText: 'File kind'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Any')),
                    for (final kind in kinds)
                      DropdownMenuItem(value: kind, child: Text(kind)),
                  ],
                  onChanged: (value) =>
                      setState(() => selectedFileKind = value),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: selectedStatus,
                  decoration: const InputDecoration(labelText: 'File status'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Any')),
                    for (final status in statuses)
                      DropdownMenuItem(value: status, child: Text(status)),
                  ],
                  onChanged: (value) => setState(() => selectedStatus = value),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        for (final result in results)
          ListTile(
            leading: Icon(
              result.kind == 'note' ? Icons.description : Icons.attach_file,
            ),
            title: Text(result.title),
            subtitle: Text(result.path),
            onTap: () {
              if (result.kind == 'note') {
                Navigator.pop(context);
                widget.onOpenNote(result.path);
              } else {
                final file = widget.files.files[result.id];
                if (file != null) widget.onOpenFile(file);
              }
            },
          ),
      ],
    );
  }

  Widget _tagsTab() {
    final tags = widget.tags.tags.values.toList()
      ..sort((a, b) => a.slug.compareTo(b.slug));
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        FilledButton.icon(
          onPressed: () => _editTag(),
          icon: const Icon(Icons.add),
          label: const Text('Create tag'),
        ),
        for (final tag in tags)
          ListTile(
            leading: const Icon(Icons.sell),
            title: Text(tag.title),
            subtitle: Text('${tag.slug} · ${tag.type}'),
            onTap: () => _editTag(tag),
            trailing: PopupMenuButton<String>(
              onSelected: (action) {
                if (action == 'edit') _editTag(tag);
                if (action == 'merge') _mergeTag(tag.slug);
                if (action == 'delete') {
                  _delete(
                    'Delete #${tag.slug}?',
                    () => widget.onDeleteTag(tag.slug),
                  );
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'merge', child: Text('Merge into…')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ),
      ],
    );
  }

  Widget _filesTab() {
    final files = widget.files.files.values.toList()
      ..sort((a, b) => a.displayTitle.compareTo(b.displayTitle));
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        FilledButton.icon(
          onPressed: () async {
            await widget.onImportFile();
            if (mounted) setState(() {});
          },
          icon: const Icon(Icons.file_upload),
          label: const Text('Import file'),
        ),
        for (final file in files)
          ListTile(
            leading: const Icon(Icons.attach_file),
            title: Text(file.displayTitle),
            subtitle: Text('${file.kind} · ${file.status}\n${file.path}'),
            isThreeLine: true,
            onTap: () => widget.onOpenFile(file),
            onLongPress: () => _editFile(file),
            trailing: PopupMenuButton<String>(
              onSelected: (action) {
                if (action == 'edit') _editFile(file);
                if (action == 'delete') {
                  _delete(
                    'Remove ${file.displayTitle} from the registry? The file will be kept.',
                    () => widget.onDeleteFile(file.id),
                  );
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit metadata')),
                PopupMenuItem(
                  value: 'delete',
                  child: Text('Remove registry entry'),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _problemsTab() => ListView(
    padding: const EdgeInsets.all(12),
    children: [
      if (widget.problems.any(
        (problem) => problem.code == 'legacy-note-metadata',
      ))
        FilledButton.icon(
          onPressed: () async {
            await widget.onMigrateLegacy();
            if (mounted) setState(() {});
          },
          icon: const Icon(Icons.upgrade),
          label: const Text('Migrate legacy note headers'),
        ),
      if (widget.problems.isEmpty)
        const ListTile(
          leading: Icon(Icons.check_circle_outline),
          title: Text('No PKMS problems'),
        ),
      for (final problem in widget.problems)
        ListTile(
          leading: Icon(switch (problem.severity) {
            PkmsSeverity.error => Icons.error_outline,
            PkmsSeverity.warning => Icons.warning_amber,
            PkmsSeverity.info => Icons.info_outline,
          }),
          title: Text(problem.message),
          subtitle: Text(
            '${problem.subject}${problem.fix == null ? '' : '\n${problem.fix}'}',
          ),
          isThreeLine: problem.fix != null,
          onTap: problem.code == 'sync-conflict'
              ? () async {
                  await widget.onResolveConflict(problem);
                  if (mounted) setState(() {});
                }
              : problem.code == 'sync-cache-conflicts'
              ? () async {
                  await widget.onCleanSyncCaches();
                  if (mounted) setState(() {});
                }
              : null,
        ),
    ],
  );

  Widget _collectionsTab() {
    final collections = widget.collections.collections.values.toList()
      ..sort((a, b) => a.title.compareTo(b.title));
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        FilledButton.icon(
          onPressed: _editCollection,
          icon: const Icon(Icons.add),
          label: const Text('Create collection'),
        ),
        for (final collection in collections)
          ListTile(
            leading: const Icon(Icons.collections_bookmark),
            title: Text(collection.title),
            subtitle: Text('${collection.noteIds.length} notes'),
            onTap: () => _editCollection(collection),
            trailing: IconButton(
              tooltip: 'Export PDF',
              icon: const Icon(Icons.picture_as_pdf),
              onPressed: () => widget.onExportCollection(collection),
            ),
          ),
      ],
    );
  }

  Future<void> _editTag([PkmsTagEntry? existing]) async {
    final slug = TextEditingController(text: existing?.slug ?? '');
    final title = TextEditingController(text: existing?.title ?? '');
    final type = TextEditingController(text: existing?.type ?? 'topic');
    final aliases = TextEditingController(
      text: existing?.aliases.join(', ') ?? '',
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existing == null ? 'Create tag' : 'Edit tag'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: slug,
              enabled: existing == null,
              decoration: const InputDecoration(labelText: 'Canonical slug'),
            ),
            TextField(
              controller: title,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            TextField(
              controller: type,
              decoration: const InputDecoration(labelText: 'Type'),
            ),
            TextField(
              controller: aliases,
              decoration: const InputDecoration(
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
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved == true && slug.text.trim().isNotEmpty) {
      await widget.onSaveTag(
        PkmsTagEntry(
          slug: slug.text.trim(),
          title: title.text.trim().isEmpty
              ? slug.text.trim()
              : title.text.trim(),
          type: type.text.trim().isEmpty ? 'topic' : type.text.trim(),
          aliases: _csv(aliases.text),
        ),
      );
      if (mounted) setState(() {});
    }
    for (final controller in [slug, title, type, aliases]) {
      controller.dispose();
    }
  }

  Future<void> _mergeTag(String from) async {
    final targets = widget.tags.tags.keys.where((slug) => slug != from).toList()
      ..sort();
    if (targets.isEmpty) return;
    final target = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('Merge #$from into'),
        children: [
          for (final slug in targets)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, slug),
              child: Text('#$slug'),
            ),
        ],
      ),
    );
    if (target != null) {
      await widget.onMergeTag(from, target);
      if (mounted) setState(() {});
    }
  }

  Future<void> _editFile(PkmsFileEntry existing) async {
    final title = TextEditingController(text: existing.title ?? '');
    final kind = TextEditingController(text: existing.kind);
    final status = TextEditingController(text: existing.status);
    final tags = TextEditingController(text: existing.tags.join(', '));
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existing.id),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: title,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            TextField(
              controller: kind,
              decoration: const InputDecoration(labelText: 'Kind'),
            ),
            TextField(
              controller: status,
              decoration: const InputDecoration(labelText: 'Status'),
            ),
            TextField(
              controller: tags,
              decoration: const InputDecoration(
                labelText: 'Tags, comma-separated',
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
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved == true) {
      await widget.onSaveFile(
        existing.copyWith(
          title: title.text.trim(),
          kind: kind.text.trim(),
          status: status.text.trim(),
          tags: _csv(tags.text),
        ),
      );
      if (mounted) setState(() {});
    }
    for (final controller in [title, kind, status, tags]) {
      controller.dispose();
    }
  }

  Future<void> _editCollection([PkmsCollectionEntry? existing]) async {
    final title = TextEditingController(text: existing?.title ?? '');
    final notes = TextEditingController(
      text: existing?.noteIds.join(', ') ?? '',
    );
    final bibliography = TextEditingController(
      text: existing?.bibliographyPath ?? '',
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existing == null ? 'Create collection' : 'Edit collection'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: title,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            TextField(
              controller: notes,
              decoration: const InputDecoration(
                labelText: 'Ordered note IDs, comma-separated',
              ),
            ),
            TextField(
              controller: bibliography,
              decoration: const InputDecoration(
                labelText: 'Bibliography path (optional)',
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
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved == true && title.text.trim().isNotEmpty) {
      final id = existing?.id ?? _slug(title.text);
      await widget.onSaveCollection(
        PkmsCollectionEntry(
          id: id,
          title: title.text.trim(),
          noteIds: _csvInOrder(notes.text),
          bibliographyPath: bibliography.text.trim().isEmpty
              ? null
              : bibliography.text.trim(),
        ),
      );
      if (mounted) setState(() {});
    }
    for (final controller in [title, notes, bibliography]) {
      controller.dispose();
    }
  }

  Future<void> _delete(String message, Future<void> Function() action) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await action();
      if (mounted) setState(() {});
    }
  }
}

List<String> _csv(String value) =>
    value
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

List<String> _csvInOrder(String value) {
  final seen = <String>{};
  return value
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty && seen.add(item))
      .toList();
}

String _slug(String value) {
  final slug = value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  return slug.isEmpty ? DateTime.now().millisecondsSinceEpoch.toString() : slug;
}
