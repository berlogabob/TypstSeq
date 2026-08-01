import 'dart:async';

import 'package:flutter/material.dart';

import 'models.dart';
import 'search_index.dart';
import 'widgets/snack.dart';

enum KnowledgeView { search, problems }

class KnowledgeScreen extends StatefulWidget {
  const KnowledgeScreen({
    super.key,
    this.initialView = KnowledgeView.search,
    required this.index,
    required this.search,
    required this.problems,
    required this.onOpenNote,
    this.onFixProblems,
  });

  final KnowledgeView initialView;
  final VaultIndex index;

  /// Runs a full-text query. A callback rather than a [PkmsSearchIndex] because
  /// the index itself lives in the worker isolate — shipping it to the UI cost
  /// ~71 ms of root-isolate time per rebuild on a P30.
  final Future<List<PkmsSearchResult>> Function(String query, String? tag)
  search;

  final List<PkmsProblem> problems;
  final ValueChanged<String> onOpenNote;

  /// Resolves the given problems (a single tile or a whole group). Returns the
  /// refreshed problem list to redraw when the fix changes the vault, or null
  /// when the fix only navigates (e.g. opening duplicate owners to merge).
  final Future<List<PkmsProblem>?> Function(List<PkmsProblem> problems)?
  onFixProblems;

  /// Codes this screen offers a one-tap "Fix" for.
  static const fixableCodes = {
    'metadata-fallback',
    'metadata-query-failed',
    'duplicate-note-id',
    'duplicate-alias',
  };

  @override
  State<KnowledgeScreen> createState() => _KnowledgeScreenState();
}

class _KnowledgeScreenState extends State<KnowledgeScreen> {
  late KnowledgeView view = widget.initialView;
  String query = '';
  String? selectedTag;
  final _searchController = TextEditingController();

  /// Results now arrive asynchronously, so they need somewhere to live.
  List<PkmsSearchResult> _results = const [];
  Timer? _searchDebounce;

  /// Guards against a slow reply overwriting a newer one. The query has *two*
  /// inputs (text and tag) reachable from three places, so comparing the reply
  /// against the current text alone would not be enough.
  int _searchGeneration = 0;
  // Codes with more than 5 problems collapse to one summary tile (a single
  // failing inspector can dead-mark itself for the rest of a scan and flood
  // this list with one unactionable row per article otherwise).
  final Set<String> _expandedCodes = {};
  // Local copy so a fix can redraw the list without popping the screen.
  late List<PkmsProblem> _problemList = widget.problems;
  bool _fixing = false;

  bool _canFix(String code) =>
      widget.onFixProblems != null &&
      KnowledgeScreen.fixableCodes.contains(code);

  String _fixLabel(String code) => switch (code) {
    'metadata-fallback' => 'Convert',
    'metadata-query-failed' => 'Repair',
    _ => 'Open files',
  };

  Future<void> _runFix(List<PkmsProblem> toFix) async {
    if (_fixing || widget.onFixProblems == null) return;
    setState(() => _fixing = true);
    try {
      final updated = await widget.onFixProblems!(toFix);
      if (!mounted) return;
      if (updated != null) {
        setState(() {
          _problemList = updated;
          _expandedCodes.removeWhere(
            (code) => !updated.any((p) => p.code == code),
          );
        });
      }
    } catch (error) {
      // A failed SAF write used to vanish into a discarded future — the
      // button then "did nothing" with no explanation.
      if (mounted) showSnack(context, 'Fix failed: $error');
    } finally {
      if (mounted) setState(() => _fixing = false);
    }
  }

  @override
  void initState() {
    super.initState();
    // The screen can open straight onto Search with a tag or empty query, and
    // an empty query is a real query here (it lists everything).
    _runSearch(immediate: true);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  /// Re-queries for the current [query]/[selectedTag].
  ///
  /// Debounced because it now crosses an isolate boundary and the field fires on
  /// every keystroke. [immediate] skips the wait for the paths where the user did
  /// not type — first open, and picking or clearing a tag chip — so those feel
  /// instant.
  void _runSearch({bool immediate = false}) {
    _searchDebounce?.cancel();
    final generation = ++_searchGeneration;
    Future<void> run() async {
      final results = await widget.search(query, selectedTag);
      // A newer query was issued while this one was in flight; its own reply owns
      // the results now.
      if (!mounted || generation != _searchGeneration) return;
      setState(() => _results = results);
    }

    if (immediate) {
      unawaited(run());
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 120), () {
      unawaited(run());
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      centerTitle: false,
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
    final tagCounts = <String, int>{};
    for (final note in widget.index.notes) {
      for (final tag in note.tags) {
        tagCounts[tag] = (tagCounts[tag] ?? 0) + 1;
      }
    }
    final tagSuggestions = query.isEmpty
        ? const <String>[]
        : (tagCounts.keys.where((tag) => tag.contains(query)).toList()
                ..sort((a, b) => tagCounts[b]!.compareTo(tagCounts[a]!)))
              .take(8)
              .toList();
    final results = _results;
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
                onChanged: (value) {
                  setState(() => query = value);
                  _runSearch();
                },
              ),
              if (tagSuggestions.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final tag in tagSuggestions)
                      ChoiceChip(
                        label: Text('#$tag'),
                        selected: false,
                        onSelected: (_) {
                          setState(() {
                            selectedTag = tag;
                            query = '';
                            _searchController.clear();
                          });
                          _runSearch(immediate: true);
                        },
                      ),
                  ],
                ),
              ],
              if (selectedTag != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: InputChip(
                    label: Text('#$selectedTag'),
                    onDeleted: () {
                      setState(() => selectedTag = null);
                      _runSearch(immediate: true);
                    },
                  ),
                ),
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
            result.kind,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: result.kind == 'file'
              ? null
              : () {
                  widget.onOpenNote(result.path);
                  Navigator.pop(context);
                },
        );
      },
    );
  }

  Widget _problems() {
    final problems = _problemList;
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

  Widget _problemTile(PkmsProblem problem) => Column(
    children: [
      ListTile(
        leading: Icon(
          _problemIcon(problem.severity),
          color: _problemColor(problem.severity),
        ),
        title: Text(problem.message),
        subtitle: Text(
          '${problem.subject}${problem.fix == null ? '' : '\n${problem.fix}'}',
        ),
        isThreeLine: problem.fix != null,
        trailing: _canFix(problem.code)
            ? TextButton(
                onPressed: _fixing ? null : () => _runFix([problem]),
                child: Text(_fixLabel(problem.code)),
              )
            : null,
        onTap: () {
          // Duplicate problems carry an id/date as subject, not an openable
          // path — route them to the owners sheet instead of a dead open.
          if (problem.code.startsWith('duplicate-')) {
            unawaited(_runFix([problem]));
            return;
          }
          widget.onOpenNote(problem.subject);
          Navigator.pop(context);
        },
      ),
      if (problem.detail != null)
        ExpansionTile(
          title: const Text('Technical details'),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [SelectableText(problem.detail!)],
        ),
    ],
  );

  Widget _problemGroupTile(List<PkmsProblem> group) {
    final code = group.first.code;
    final expanded = _expandedCodes.contains(code);
    return ListTile(
      leading: Icon(
        _problemIcon(group.first.severity),
        color: _problemColor(group.first.severity),
      ),
      title: Text(group.first.message),
      subtitle: Text(
        expanded
            ? group.map((problem) => problem.subject).join('\n')
            : '${group.length} notes · ${group.take(2).map((problem) => problem.subject).join(', ')}…',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_canFix(code))
            TextButton(
              onPressed: _fixing ? null : () => _runFix(group),
              // Duplicates aren't auto-fixable — the group action opens the
              // owners sheet for a manual merge, so don't promise "Fix all".
              child: Text(
                code.startsWith('duplicate-')
                    ? 'Open files'
                    : 'Fix all ${group.length}',
              ),
            ),
          Icon(expanded ? Icons.expand_less : Icons.expand_more),
        ],
      ),
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

  Color _problemColor(PkmsSeverity severity) => switch (severity) {
    PkmsSeverity.error => Theme.of(context).colorScheme.error,
    PkmsSeverity.warning => Colors.amber,
    PkmsSeverity.info => Theme.of(context).colorScheme.onSurfaceVariant,
  };
}
