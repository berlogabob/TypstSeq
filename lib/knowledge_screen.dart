import 'package:flutter/material.dart';

import 'models.dart';
import 'search_index.dart';

enum KnowledgeView { search, problems }

class KnowledgeScreen extends StatefulWidget {
  const KnowledgeScreen({
    super.key,
    this.initialView = KnowledgeView.search,
    required this.index,
    required this.search,
    required this.problems,
    required this.onOpenNote,
  });

  final KnowledgeView initialView;
  final VaultIndex index;
  final PkmsSearchIndex search;
  final List<PkmsProblem> problems;
  final ValueChanged<String> onOpenNote;

  @override
  State<KnowledgeScreen> createState() => _KnowledgeScreenState();
}

class _KnowledgeScreenState extends State<KnowledgeScreen> {
  late KnowledgeView view = widget.initialView;
  String query = '';
  String? selectedTag;
  final _searchController = TextEditingController();
  // Codes with more than 5 problems collapse to one summary tile (a single
  // failing inspector can dead-mark itself for the rest of a scan and flood
  // this list with one unactionable row per article otherwise).
  final Set<String> _expandedCodes = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(switch (view) {
        KnowledgeView.search => 'Search',
        KnowledgeView.problems => 'Problems',
      }),
      actions: [
        PopupMenuButton<KnowledgeView>(
          tooltip: 'Knowledge sections',
          initialValue: view,
          onSelected: (next) => setState(() => view = next),
          itemBuilder: (_) => const [
            PopupMenuItem(value: KnowledgeView.search, child: Text('Search')),
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
      KnowledgeView.problems => _problems(),
    },
  );

  Widget _search() {
    final tags = <String>{
      for (final note in widget.index.notes) ...note.tags,
    }.toList()..sort();
    final results = widget.search.search(query, tag: selectedTag);
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 1 + results.length,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _searchController,
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
            ],
          );
        }
        final result = results[i - 1];
        return ListTile(
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
        );
      },
    );
  }

  Widget _problems() {
    final problems = widget.problems;
    if (problems.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(12),
        children: const [
          ListTile(
            leading: Icon(Icons.check_circle_outline),
            title: Text('No vault problems'),
          ),
        ],
      );
    }
    final byCode = <String, List<PkmsProblem>>{};
    for (final problem in problems) {
      byCode.putIfAbsent(problem.code, () => []).add(problem);
    }
    final items = <Object>[];
    for (final group in byCode.values) {
      if (group.length > 5) {
        items.add(group);
        if (_expandedCodes.contains(group.first.code)) {
          items.addAll(group);
        }
      } else {
        items.addAll(group);
      }
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        return item is List<PkmsProblem>
            ? _problemGroupTile(item)
            : _problemTile(item as PkmsProblem);
      },
    );
  }

  Widget _problemTile(PkmsProblem problem) => ListTile(
    leading: Icon(_problemIcon(problem.severity)),
    title: Text(problem.message),
    subtitle: Text(
      '${problem.subject}${problem.fix == null ? '' : '\n${problem.fix}'}',
    ),
    isThreeLine: problem.fix != null,
    onTap: null,
  );

  Widget _problemGroupTile(List<PkmsProblem> group) {
    final code = group.first.code;
    final expanded = _expandedCodes.contains(code);
    return ListTile(
      leading: Icon(_problemIcon(group.first.severity)),
      title: Text(group.first.message),
      subtitle: Text('· ${group.length} notes'),
      trailing: Icon(expanded ? Icons.expand_less : Icons.expand_more),
      onTap: () => setState(() {
        if (expanded) {
          _expandedCodes.remove(code);
        } else {
          _expandedCodes.add(code);
        }
      }),
    );
  }

  IconData _problemIcon(PkmsSeverity severity) => switch (severity) {
    PkmsSeverity.error => Icons.error_outline,
    PkmsSeverity.warning => Icons.warning_amber,
    PkmsSeverity.info => Icons.info_outline,
  };
}
