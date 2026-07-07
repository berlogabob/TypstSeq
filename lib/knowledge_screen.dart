import 'package:flutter/material.dart';

import 'models.dart';
import 'search_index.dart';

enum KnowledgeView { search, tasks, problems }

class KnowledgeScreen extends StatefulWidget {
  const KnowledgeScreen({
    super.key,
    this.initialView = KnowledgeView.search,
    required this.index,
    required this.search,
    required this.problems,
    required this.onOpenNote,
    required this.onSetTaskStatus,
  });

  final KnowledgeView initialView;
  final VaultIndex index;
  final PkmsSearchIndex search;
  final List<PkmsProblem> problems;
  final ValueChanged<String> onOpenNote;
  final Future<void> Function(TaskRef, String) onSetTaskStatus;

  @override
  State<KnowledgeScreen> createState() => _KnowledgeScreenState();
}

class _KnowledgeScreenState extends State<KnowledgeScreen> {
  late KnowledgeView view = widget.initialView;
  String query = '';
  String? selectedTag;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(switch (view) {
        KnowledgeView.search => 'Search',
        KnowledgeView.tasks => 'Tasks',
        KnowledgeView.problems => 'Problems',
      }),
      actions: [
        PopupMenuButton<KnowledgeView>(
          tooltip: 'Knowledge sections',
          initialValue: view,
          onSelected: (next) => setState(() => view = next),
          itemBuilder: (_) => const [
            PopupMenuItem(value: KnowledgeView.search, child: Text('Search')),
            PopupMenuItem(value: KnowledgeView.tasks, child: Text('Tasks')),
            PopupMenuItem(
              value: KnowledgeView.problems,
              child: Text('Problems'),
            ),
          ],
        ),
      ],
    ),
    body: switch (view) {
      KnowledgeView.search => _search(),
      KnowledgeView.tasks => _tasks(),
      KnowledgeView.problems => _problems(),
    },
  );

  Widget _search() {
    final tags = <String>{
      for (final note in widget.index.notes) ...note.tags,
    }.toList()..sort();
    final results = widget.search.search(query, tag: selectedTag);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          autofocus: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.search),
            hintText: 'Search notes, tasks, and attachments',
          ),
          onChanged: (value) => setState(() => query = value),
        ),
        if (tags.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
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
        const SizedBox(height: 8),
        for (final result in results)
          ListTile(
            leading: Icon(switch (result.kind) {
              'task' => Icons.task_alt,
              'file' => Icons.attach_file,
              'project' => Icons.work_outline,
              'article' => Icons.article_outlined,
              _ => Icons.description_outlined,
            }),
            title: Text(result.title),
            subtitle: Text(
              [
                result.kind,
                result.path,
                if (result.snippet != null) result.snippet!,
              ].join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: result.kind == 'file'
                ? null
                : () => widget.onOpenNote(result.path),
          ),
      ],
    );
  }

  Widget _tasks() {
    final tasks = widget.index.tasks.toList()
      ..sort((a, b) => (a.due ?? '9999').compareTo(b.due ?? '9999'));
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (tasks.isEmpty)
          const ListTile(
            leading: Icon(Icons.task_alt),
            title: Text('No indexed tasks'),
            subtitle: Text('Add a #tylog.task(...) call to a note.'),
          ),
        for (final task in tasks)
          ListTile(
            leading: Icon(
              task.status == 'done'
                  ? Icons.check_circle
                  : Icons.radio_button_unchecked,
            ),
            title: Text(task.text),
            subtitle: Text(
              [
                task.status,
                if (task.project != null) task.project!,
                if (task.due != null) 'due ${task.due}',
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

  Widget _problems() => ListView(
    padding: const EdgeInsets.all(12),
    children: [
      if (widget.problems.isEmpty)
        const ListTile(
          leading: Icon(Icons.check_circle_outline),
          title: Text('No vault problems'),
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
          onTap: null,
        ),
    ],
  );
}
