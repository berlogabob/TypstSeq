import 'dart:async';

import 'package:flutter/material.dart';

import '../models.dart';
import 'calendar_tab.dart';
import 'constants.dart';
import 'date_format.dart';
import 'property_select_chip.dart';

class WorkSurface extends StatelessWidget {
  const WorkSurface({super.key, required this.child});

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

/// Whether [task] belongs on the Today agenda given [today] (an ISO
/// `yyyy-MM-dd` day string): not done/cancelled, and due on-or-before today
/// or scheduled on-or-before today. `due`/`scheduled` may carry a time
/// component (`yyyy-MM-ddTHH:mm:ss`); only the date part is compared.
bool isTaskInTodayAgenda(TaskRef task, String today) {
  if (task.status == 'done' || task.status == 'cancelled') return false;
  final due = task.due?.split('T').first;
  final scheduled = task.scheduled?.split('T').first;
  return (due != null && due.compareTo(today) <= 0) ||
      (scheduled != null && scheduled.compareTo(today) <= 0);
}

class TodayPage extends StatelessWidget {
  const TodayPage({
    super.key,
    required this.tasks,
    required this.recent,
    required this.editor,
    required this.onOpenPath,
    required this.onSetStatus,
    this.onReadPath,
  });

  final List<TaskRef> tasks;
  final List<(NoteRef note, double progress)> recent;
  final Widget editor;
  final ValueChanged<String> onOpenPath;
  final Future<void> Function(TaskRef task, String status) onSetStatus;
  final ValueChanged<String>? onReadPath;

  @override
  Widget build(BuildContext context) {
    final today = isoDay(DateTime.now());
    final agenda =
        tasks.where((task) => isTaskInTodayAgenda(task, today)).toList()..sort(
          (a, b) => (a.due ?? a.scheduled ?? '9999').compareTo(
            b.due ?? b.scheduled ?? '9999',
          ),
        );
    return Column(
      children: [
        ExpansionTile(
          key: const PageStorageKey('today-agenda'),
          initiallyExpanded: agenda.isNotEmpty,
          leading: const Icon(Icons.event_note),
          title: Text('Agenda${agenda.isEmpty ? '' : ' · ${agenda.length}'}'),
          subtitle: agenda.isEmpty
              ? const Text('Nothing actionable today')
              : null,
          children: [
            for (final task in agenda)
              CheckboxListTile(
                value: false,
                title: Text(task.text),
                subtitle: Text(
                  task.due == null ? 'Scheduled today' : 'Due ${task.due}',
                ),
                onChanged: (done) {
                  if (done == true) unawaited(onSetStatus(task, 'done'));
                },
                secondary: IconButton(
                  tooltip: 'Open source note',
                  onPressed: () => onOpenPath(task.notePath),
                  icon: const Icon(Icons.open_in_new),
                ),
              ),
          ],
        ),
        if (recent.isNotEmpty)
          ExpansionTile(
            key: const PageStorageKey('today-continue-reading'),
            initiallyExpanded: true,
            leading: const Icon(Icons.history),
            title: const Text('Continue reading'),
            children: [
              for (final (note, progress) in recent)
                ListTile(
                  title: Text(note.title),
                  subtitle: progress > 0
                      ? LinearProgressIndicator(value: progress)
                      : Text(note.path),
                  onTap: () => (onReadPath ?? onOpenPath)(note.path),
                ),
            ],
          ),
        const Divider(height: 1),
        Expanded(child: editor),
      ],
    );
  }
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
    final itemCount = 1 + (sorted.isEmpty ? 1 : sorted.length);
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: itemCount,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Text(
            'Tasks',
            style: Theme.of(context).textTheme.headlineMedium,
          );
        }
        if (sorted.isEmpty) {
          return const ListTile(title: Text('No indexed tasks'));
        }
        final task = sorted[i - 1];
        return CheckboxListTile(
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
        );
      },
    );
  }
}

class LibraryView extends StatelessWidget {
  const LibraryView({
    super.key,
    required this.index,
    required this.progressByPath,
    required this.onOpenPath,
    required this.onOpenDay,
    required this.onSetTaskStatus,
    required this.onSetReadStatus,
    required this.onCreateEntity,
    required this.onImportMarkdownArticles,
    required this.onReadPath,
    required this.onDeleteArticle,
  });

  final VaultIndex? index;
  final Map<String, double> progressByPath;
  final ValueChanged<String> onOpenPath;
  final ValueChanged<DateTime> onOpenDay;
  final Future<void> Function(TaskRef task, String status) onSetTaskStatus;
  final Future<void> Function(NoteRef note, String status) onSetReadStatus;
  final VoidCallback onCreateEntity;
  final Future<void> Function() onImportMarkdownArticles;
  final ValueChanged<String> onReadPath;
  final Future<void> Function(NoteRef note) onDeleteArticle;

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 6,
    child: Column(
      children: [
        const TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(text: 'Notes'),
            Tab(text: 'Projects'),
            Tab(text: 'Articles'),
            Tab(text: 'Tasks'),
            Tab(text: 'Entities'),
            Tab(text: 'Calendar'),
          ],
        ),
        Expanded(
          child: TabBarView(
            children: [
              _notes('note'),
              _notes('project'),
              _ArticlesShelf(
                index: index,
                progressByPath: progressByPath,
                onReadPath: onReadPath,
                onSetReadStatus: onSetReadStatus,
                onDeleteArticle: onDeleteArticle,
                onImportMarkdownArticles: onImportMarkdownArticles,
              ),
              _PrimaryTasksView(
                tasks: index?.tasks ?? const <TaskRef>[],
                onSetStatus: onSetTaskStatus,
                onOpenPath: onOpenPath,
              ),
              _entities(),
              CalendarTab(
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

  Widget _notes(String kind) {
    final notes = (index?.notes ?? const <NoteRef>[])
        .where((note) => note.kind == kind)
        .toList();
    return ListView.builder(
      itemCount: notes.length,
      itemBuilder: (context, i) {
        final note = notes[i];
        return ListTile(
          leading: Icon(switch (kind) {
            'project' => Icons.work_outline,
            _ => Icons.notes,
          }),
          title: Text(note.title),
          subtitle: Text(note.path),
          onTap: () => onOpenPath(note.path),
        );
      },
    );
  }

  Widget _entities() {
    final entities =
        (index?.notes ?? const <NoteRef>[])
            .where((note) => !structuralNoteKinds.contains(note.kind))
            .toList()
          ..sort((a, b) => a.title.compareTo(b.title));
    final itemCount = 1 + (entities.isEmpty ? 1 : entities.length);
    return ListView.builder(
      itemCount: itemCount,
      itemBuilder: (context, i) {
        if (i == 0) {
          return ListTile(
            leading: const Icon(Icons.add),
            title: const Text('New entity'),
            onTap: onCreateEntity,
          );
        }
        if (entities.isEmpty) {
          return const ListTile(
            title: Text('No people, places, or other entities yet'),
          );
        }
        final note = entities[i - 1];
        return ListTile(
          leading: const Icon(Icons.alternate_email),
          title: Text(note.title),
          subtitle: Text(
            [
              note.kind,
              if (note.aliases.isNotEmpty) note.aliases.join(', '),
            ].join(' · '),
          ),
          onTap: () => onOpenPath(note.path),
        );
      },
    );
  }
}

/// The Articles tab as a reading shelf: status filter (Inbox/Reading/Read),
/// search, sort, and metadata-based grouping over the indexed articles.
/// All state is derived in-memory from [VaultIndex]; only the status property
/// write goes back to disk (via [onSetReadStatus]).
class _ArticlesShelf extends StatefulWidget {
  const _ArticlesShelf({
    required this.index,
    required this.progressByPath,
    required this.onReadPath,
    required this.onSetReadStatus,
    required this.onDeleteArticle,
    required this.onImportMarkdownArticles,
  });

  final VaultIndex? index;
  final Map<String, double> progressByPath;
  final ValueChanged<String> onReadPath;
  final Future<void> Function(NoteRef note, String status) onSetReadStatus;
  final Future<void> Function(NoteRef note) onDeleteArticle;
  final Future<void> Function() onImportMarkdownArticles;

  @override
  State<_ArticlesShelf> createState() => _ArticlesShelfState();
}

class _ArticlesShelfState extends State<_ArticlesShelf> {
  // ponytail: last-choice memory is per app run only; persist to vaults.json
  // if users ask for it to survive restarts.
  static String? _lastStatusFilter;
  static String _lastSort = 'recent';
  static String _lastGroupBy = 'none';

  final _query = TextEditingController();
  String? statusFilter = _lastStatusFilter;
  String sort = _lastSort;
  String groupBy = _lastGroupBy;

  static const _sortLabels = {
    'recent': 'Recently updated',
    'progress': 'Reading progress',
    'title': 'Title',
  };
  static const _groupLabels = {
    'none': 'No grouping',
    'tag': 'Group by tag',
    'year': 'Group by year',
    'source': 'Group by source',
  };

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  /// Collapses the free-form status property into the three shelf buckets;
  /// custom values like `summarized` count as read.
  static String _bucket(NoteRef note) =>
      switch (note.properties['status'] as String? ?? 'unread') {
        'unread' => 'unread',
        'reading' => 'reading',
        _ => 'read',
      };

  String? _source(NoteRef note) {
    final url = note.properties['url'] as String?;
    final host = url == null ? null : Uri.tryParse(url)?.host;
    if (host != null && host.isNotEmpty) return host;
    final name = note.properties['import_source_name'] as String?;
    return name == null || name.isEmpty ? null : name;
  }

  String _groupKey(NoteRef note) => switch (groupBy) {
    'tag' => note.tags.isEmpty ? 'Untagged' : note.tags.first,
    'year' => _year(note),
    _ => _source(note) ?? 'Unknown source',
  };

  String _year(NoteRef note) {
    final fromDate = note.date?.split('-').first;
    if (fromDate != null && fromDate.length == 4) return fromDate;
    final millis = note.modifiedMillis;
    if (millis != null) {
      return '${DateTime.fromMillisecondsSinceEpoch(millis).year}';
    }
    return 'Undated';
  }

  @override
  Widget build(BuildContext context) {
    final all = (widget.index?.notes ?? const <NoteRef>[])
        .where((note) => note.kind == 'article')
        .toList();
    final q = _query.text.trim().toLowerCase();
    final searched = q.isEmpty
        ? all
        : all
              .where(
                (note) =>
                    note.title.toLowerCase().contains(q) ||
                    note.tags.any((tag) => tag.toLowerCase().contains(q)),
              )
              .toList();
    final counts = {'unread': 0, 'reading': 0, 'read': 0};
    for (final note in searched) {
      counts[_bucket(note)] = counts[_bucket(note)]! + 1;
    }
    final filtered = statusFilter == null
        ? searched
        : searched.where((note) => _bucket(note) == statusFilter).toList();
    filtered.sort(switch (sort) {
      'progress' => (a, b) => (widget.progressByPath[b.path] ?? 0).compareTo(
        widget.progressByPath[a.path] ?? 0,
      ),
      'title' => (a, b) => a.title.toLowerCase().compareTo(
        b.title.toLowerCase(),
      ),
      _ => (a, b) => (b.modifiedMillis ?? 0).compareTo(a.modifiedMillis ?? 0),
    });
    final groups = <(String, List<NoteRef>)>[];
    if (groupBy == 'none') {
      groups.add(('', filtered));
    } else {
      final byKey = <String, List<NoteRef>>{};
      for (final note in filtered) {
        byKey.putIfAbsent(_groupKey(note), () => []).add(note);
      }
      final entries = byKey.entries.toList()
        ..sort((a, b) => b.value.length.compareTo(a.value.length));
      groups.addAll([for (final e in entries) (e.key, e.value)]);
    }

    // Most recently opened unfinished article, for the resume card. The
    // progress map preserves recents order (most recently opened first).
    NoteRef? continueNote;
    var continueProgress = 0.0;
    for (final entry in widget.progressByPath.entries) {
      if (entry.value <= 0 || entry.value >= 0.98) continue;
      final note = widget.index?.notesByPath[entry.key];
      if (note == null || note.kind != 'article') continue;
      continueNote = note;
      continueProgress = entry.value;
      break;
    }

    const statusChips = <(String?, String)>[
      (null, 'All'),
      ('unread', 'Inbox'),
      ('reading', 'Reading'),
      ('read', 'Read'),
    ];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('articles-search'),
                  controller: _query,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Search articles',
                    border: const OutlineInputBorder(),
                    suffixIcon: _query.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _query.clear();
                              setState(() {});
                            },
                          ),
                  ),
                ),
              ),
              PopupMenuButton<String>(
                key: const Key('articles-sort'),
                tooltip: 'Sort: ${_sortLabels[sort]}',
                icon: const Icon(Icons.sort),
                initialValue: sort,
                onSelected: (value) => setState(() => sort = _lastSort = value),
                itemBuilder: (_) => [
                  for (final entry in _sortLabels.entries)
                    PopupMenuItem(value: entry.key, child: Text(entry.value)),
                ],
              ),
              PopupMenuButton<String>(
                key: const Key('articles-group'),
                tooltip: 'Grouping: ${_groupLabels[groupBy]}',
                icon: const Icon(Icons.workspaces_outline),
                initialValue: groupBy,
                onSelected: (value) =>
                    setState(() => groupBy = _lastGroupBy = value),
                itemBuilder: (_) => [
                  for (final entry in _groupLabels.entries)
                    PopupMenuItem(value: entry.key, child: Text(entry.value)),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              children: [
                for (final (value, label) in statusChips)
                  ChoiceChip(
                    label: Text(
                      '$label · ${value == null ? searched.length : counts[value]}',
                    ),
                    selected: statusFilter == value,
                    onSelected: (_) => setState(
                      () => statusFilter = _lastStatusFilter = value,
                    ),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              ListTile(
                key: const ValueKey('import-markdown-articles'),
                leading: const Icon(Icons.file_upload_outlined),
                title: const Text('Import Markdown articles'),
                subtitle: const Text(
                  'Select one or more .md or .markdown files',
                ),
                onTap: () => unawaited(widget.onImportMarkdownArticles()),
              ),
              if (continueNote != null)
                Card(
                  key: const Key('articles-continue-reading'),
                  child: ListTile(
                    leading: const Icon(Icons.auto_stories),
                    title: Text('Continue reading · ${continueNote.title}'),
                    subtitle: LinearProgressIndicator(value: continueProgress),
                    trailing: Text('${(continueProgress * 100).round()}%'),
                    onTap: () => widget.onReadPath(continueNote!.path),
                  ),
                ),
              if (filtered.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      q.isNotEmpty || statusFilter != null
                          ? 'Nothing matches'
                          : 'No articles yet — import one above',
                    ),
                  ),
                ),
              for (final (header, notes) in groups) ...[
                if (header.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(
                      '$header · ${notes.length}',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                for (final note in notes) _row(note),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(NoteRef note) {
    final subtitle = [
      ?_source(note),
      if (note.tags.isNotEmpty) note.tags.map((tag) => '#$tag').join(' '),
    ].join(' · ');
    return ListTile(
      leading: const Icon(Icons.article_outlined),
      title: Text(note.title),
      subtitle: subtitle.isEmpty
          ? null
          : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: _trailing(note),
      onTap: () => widget.onReadPath(note.path),
      onLongPress: () => unawaited(widget.onDeleteArticle(note)),
    );
  }

  Widget _trailing(NoteRef note) {
    final status = note.properties['status'] as String? ?? 'unread';
    final progress = widget.progressByPath[note.path] ?? 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (progress > 0 && progress < 1) ...[
          Text(
            '${(progress * 100).round()}%',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(width: 4),
          SizedBox(width: 40, child: LinearProgressIndicator(value: progress)),
          const SizedBox(width: 8),
        ],
        PropertySelectChip(
          value: status,
          options: articleStatusOptions,
          labels: articleStatusLabels,
          tooltip: 'Change status',
          onChanged: (next) => unawaited(widget.onSetReadStatus(note, next)),
        ),
      ],
    );
  }
}
