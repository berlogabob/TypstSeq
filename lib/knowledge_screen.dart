import 'package:flutter/material.dart';

import 'models.dart';
import 'pkms_registry.dart';
import 'search_index.dart';

enum KnowledgeView { search, tasks, tags, files, problems, collections }

class KnowledgeScreen extends StatefulWidget {
  const KnowledgeScreen({
    super.key,
    this.initialView = KnowledgeView.search,
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
    required this.onSetTaskStatus,
  });

  final VaultIndex index;
  final KnowledgeView initialView;
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
  final Future<void> Function(TaskRef task, String status) onSetTaskStatus;

  @override
  State<KnowledgeScreen> createState() => _KnowledgeScreenState();
}

class _KnowledgeScreenState extends State<KnowledgeScreen> {
  late KnowledgeView view = widget.initialView;
  String query = '';
  String? selectedTag;
  String? selectedFileKind;
  String? selectedStatus;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(switch (view) {
        KnowledgeView.search => 'Knowledge',
        KnowledgeView.tasks => 'Tasks',
        KnowledgeView.tags => 'Tags',
        KnowledgeView.files => 'Files',
        KnowledgeView.problems => 'Problems',
        KnowledgeView.collections => 'Collections',
      }),
      actions: [
        PopupMenuButton<KnowledgeView>(
          tooltip: 'Knowledge sections',
          initialValue: view,
          onSelected: (value) => setState(() => view = value),
          itemBuilder: (_) => const [
            PopupMenuItem(value: KnowledgeView.search, child: Text('Search')),
            PopupMenuItem(value: KnowledgeView.tasks, child: Text('Tasks')),
            PopupMenuItem(value: KnowledgeView.tags, child: Text('Tags')),
            PopupMenuItem(value: KnowledgeView.files, child: Text('Files')),
            PopupMenuItem(
              value: KnowledgeView.problems,
              child: Text('Problems'),
            ),
            PopupMenuItem(
              value: KnowledgeView.collections,
              child: Text('Collections'),
            ),
          ],
        ),
      ],
    ),
    body: switch (view) {
      KnowledgeView.search => _searchTab(),
      KnowledgeView.tasks => _tasksTab(),
      KnowledgeView.tags => _tagsTab(),
      KnowledgeView.files => _filesTab(),
      KnowledgeView.problems => _problemsTab(),
      KnowledgeView.collections => _collectionsTab(),
    },
  );

  Widget _tasksTab() {
    final byId = {for (final task in widget.index.tasks) task.id: task};
    final tasks = widget.index.tasks.toList()
      ..sort((a, b) => (a.due ?? '9999').compareTo(b.due ?? '9999'));
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (tasks.isEmpty)
          const ListTile(
            leading: Icon(Icons.task_alt),
            title: Text('No indexed tasks'),
            subtitle: Text('Add a #pkm.task(...) call to a note.'),
          ),
        for (final task in tasks)
          ListTile(
            leading: Icon(
              task.status == 'done'
                  ? Icons.check_circle
                  : task.dependencies.any((id) => byId[id]?.status != 'done')
                  ? Icons.block
                  : Icons.radio_button_unchecked,
            ),
            title: Text(task.text),
            subtitle: Text(
              [
                task.status,
                task.priority,
                if (task.project != null) task.project!,
                if (task.due != null) 'due ${task.due}',
                if (task.recurrence != null) task.recurrence!,
              ].join(' · '),
            ),
            onTap: () => widget.onOpenNote(task.notePath),
            trailing: PopupMenuButton<String>(
              tooltip: 'Task status',
              onSelected: (status) => widget.onSetTaskStatus(task, status),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'todo', child: Text('To do')),
                PopupMenuItem(value: 'doing', child: Text('Doing')),
                PopupMenuItem(value: 'done', child: Text('Done')),
                PopupMenuItem(value: 'cancelled', child: Text('Cancelled')),
              ],
            ),
          ),
      ],
    );
  }

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
        const SizedBox(height: 12),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              if (widget.problems.any((p) => p.code == 'sync-conflict')) ...[
                ActionChip(
                  avatar: const Icon(Icons.warning_amber, size: 18),
                  label: Text(
                    'Conflicts: ${widget.problems.where((p) => p.code == 'sync-conflict').length}',
                  ),
                  onPressed: () =>
                      setState(() => view = KnowledgeView.problems),
                ),
                const SizedBox(width: 6),
              ],
              ChoiceChip(
                label: const Text('All'),
                selected: selectedTag == null,
                onSelected: (_) => setState(() => selectedTag = null),
              ),
              for (final tag in tags)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: ChoiceChip(
                    label: Text('#$tag'),
                    selected: selectedTag == tag,
                    onSelected: (_) => setState(() => selectedTag = tag),
                  ),
                ),
            ],
          ),
        ),
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
              result.kind == 'note'
                  ? Icons.description
                  : result.kind == 'task'
                  ? Icons.task_alt
                  : Icons.attach_file,
            ),
            title: Text(result.title),
            subtitle: Text(
              result.snippet == null
                  ? result.path
                  : '${result.path}\n${result.snippet}',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            isThreeLine: result.snippet != null,
            onTap: () {
              if (result.kind == 'note' || result.kind == 'task') {
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
      FilledButton.icon(
        onPressed: () async {
          await widget.onMigrateLegacy();
          if (mounted) setState(() {});
        },
        icon: const Icon(Icons.upgrade),
        label: const Text('Migrate vault to PKMS v4'),
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
