import 'dart:async';
import 'dart:math' show max;
import 'dart:typed_data';
import 'screenshot_strip.dart';

import 'package:flutter/material.dart';

import '../models.dart';
import '../controlled_editor.dart' show localTime;
import '../article_jobs.dart';
import 'calendar_tab.dart';
import 'constants.dart';
import 'date_format.dart';
import 'loading.dart';
import 'property_select_chip.dart';
import 'task_checkbox.dart';
import 'task_agenda.dart';
export 'task_agenda.dart' show isTaskInTodayAgenda, isTaskOverdue;

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

/// Continue-reading is for articles only: entities are often stored with
/// kind 'note' (created before their kind is rewritten), so allowing any
/// non-article kind lets them leak in.
bool continueReadingEligible(NoteRef note) => note.kind == 'article';

class TodayPage extends StatelessWidget {
  const TodayPage({
    super.key,
    this.events = const [],
    required this.tasks,
    required this.recent,
    required this.editor,
    required this.onOpenPath,
    required this.onSetStatus,
    this.onReadPath,
    this.onAllTasks,
    this.notes = const {},
  });

  final VoidCallback? onAllTasks;
  final Map<String, NoteRef> notes;
  final List<CalendarItem> events;
  final List<TaskRef> tasks;
  final List<(NoteRef note, double progress)> recent;
  final Widget editor;
  final ValueChanged<String> onOpenPath;
  final Future<void> Function(TaskRef task, String status) onSetStatus;
  final ValueChanged<String>? onReadPath;

  @override
  Widget build(BuildContext context) {
    final today = isoDay(DateTime.now());
    final groups = TaskAgendaCache().resolve(tasks, notes, today);
    final agenda = groups
        .where((g) => g.key == 'today')
        .expand((g) => g.tasks)
        .toList();
    final overdue = groups
        .where((g) => g.key == 'overdue')
        .expand((g) => g.tasks)
        .toList();
    final todayEvents = events.where((e) => e.date == today).toList()
      ..sort((a, b) => (a.start ?? '9999').compareTo(b.start ?? '9999'));
    final hasTopContent =
        todayEvents.isNotEmpty ||
        agenda.isNotEmpty ||
        overdue.isNotEmpty ||
        onAllTasks != null ||
        recent.isNotEmpty;
    Widget taskRow(TaskRef task) => ListTile(
      leading: TaskCheckbox(
        value: false,
        onChanged: (done) {
          if (done == true) unawaited(onSetStatus(task, 'done'));
        },
      ),
      title: Text(task.text),
      subtitle: Text(
        task.due == null ? 'Scheduled today' : 'Due ${task.due}',
        style: isTaskOverdue(task, today)
            ? TextStyle(color: Theme.of(context).colorScheme.error)
            : null,
      ),
      onTap: () => onOpenPath(task.notePath),
      trailing: IconButton(
        tooltip: 'Open source note',
        onPressed: () => onOpenPath(task.notePath),
        icon: const Icon(Icons.open_in_new),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        children: [
          // Today is capture-first: quick capture is the editor's job, so it
          // must keep the majority of the viewport even when the agenda and
          // reading shelf both have content. Agenda + Continue reading share
          // a bounded, scroll-if-tall region capped at 45% of the page —
          // that leaves the editor >=55%, and a long recent list still can't
          // starve it or overflow.
          if (hasTopContent) ...[
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: constraints.maxHeight * 0.45,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (agenda.isNotEmpty ||
                        overdue.isNotEmpty ||
                        todayEvents.isNotEmpty ||
                        onAllTasks != null)
                      ExpansionTile(
                        key: const PageStorageKey('today-agenda'),
                        leading: const Icon(Icons.event_note),
                        title: Text(
                          'Agenda · ${agenda.length + overdue.length + todayEvents.length}',
                        ),
                        children: [
                          for (final event in todayEvents)
                            ListTile(
                              leading: const Icon(Icons.event),
                              title: Text(event.title),
                              onTap: () => onOpenPath(event.notePath),
                            ),
                          for (final task in agenda) taskRow(task),
                          if (overdue.isNotEmpty)
                            ExpansionTile(
                              key: const PageStorageKey('today-overdue'),
                              title: Text('Overdue · ${overdue.length}'),
                              children: [
                                for (final task in overdue) taskRow(task),
                              ],
                            ),
                          if (onAllTasks != null)
                            ListTile(
                              title: const Text('All tasks →'),
                              onTap: onAllTasks,
                            ),
                        ],
                      ),
                    if (recent.isNotEmpty)
                      ExpansionTile(
                        key: const PageStorageKey('today-continue-reading'),
                        leading: const Icon(Icons.history),
                        title: const Text('Continue reading'),
                        children: [
                          for (final (note, progress) in recent)
                            Card(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: ListTile(
                                leading: const Icon(
                                  Icons.auto_stories_outlined,
                                ),
                                title: Text(
                                  note.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: LinearProgressIndicator(
                                  value: progress,
                                ),
                                trailing: Text('${(progress * 100).round()}%'),
                                onTap: () =>
                                    (onReadPath ?? onOpenPath)(note.path),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
          ],
          Expanded(child: editor),
        ],
      ),
    );
  }
}

class _PrimaryTasksView extends StatefulWidget {
  const _PrimaryTasksView({
    required this.tasks,
    required this.notes,
    required this.indexing,
    required this.onOpenPath,
    required this.onSetStatus,
  });

  final List<TaskRef> tasks;
  final Map<String, NoteRef> notes;
  final bool indexing;
  final ValueChanged<String> onOpenPath;
  final Future<void> Function(TaskRef task, String status) onSetStatus;

  @override
  State<_PrimaryTasksView> createState() => _PrimaryTasksViewState();
}

class _PrimaryTasksViewState extends State<_PrimaryTasksView> {
  final _cache = TaskAgendaCache();
  final _expanded = <String>{};
  TaskAgendaFilter _filter = TaskAgendaFilter.open;
  String? _project;
  String _search = '';
  List<TaskAgendaGroup> _groups = const [];
  Timer? _dayTimer;
  late String _today;

  @override
  void initState() {
    super.initState();
    _refresh();
    _scheduleDay();
  }

  void _scheduleDay() {
    final now = DateTime.now();
    _dayTimer = Timer(
      DateTime(now.year, now.month, now.day + 1).difference(now),
      () {
        if (!mounted) return;
        setState(_refresh);
        _scheduleDay();
      },
    );
  }

  @override
  void didUpdateWidget(covariant _PrimaryTasksView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _refresh();
  }

  void _refresh() {
    _today = isoDay(DateTime.now());
    final groups = _cache.resolve(widget.tasks, widget.notes, _today);
    if (!_cache.projects.contains(_project)) _project = null;
    _groups = filterTaskAgenda(groups, _filter, _project, _search);
  }

  @override
  void dispose() {
    _dayTimer?.cancel();
    super.dispose();
  }

  Widget _row(TaskRef task, {bool journal = false}) {
    final day = journal ? journalTaskDay(task, widget.notes) : null;
    final overdue = isTaskOverdue(task, _today);
    return ListTile(
      leading: TaskCheckbox(
        value: task.status == 'done',
        onChanged: (done) =>
            widget.onSetStatus(task, done == true ? 'done' : 'todo'),
      ),
      title: Text(task.text),
      subtitle: Text(
        [
          if (day != null) monthDay(day),
          if (task.project != null) task.project!,
          if (task.due != null) 'due ${task.due}${overdue ? ' · overdue' : ''}',
        ].join(' · '),
        style: overdue
            ? TextStyle(color: Theme.of(context).colorScheme.error)
            : null,
      ),
      onTap: () => widget.onOpenPath(task.notePath),
      trailing: IconButton(
        tooltip: 'Open source note',
        icon: const Icon(Icons.open_in_new),
        onPressed: () => widget.onOpenPath(task.notePath),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final filter in TaskAgendaFilter.values)
                  ChoiceChip(
                    label: Text(switch (filter) {
                      TaskAgendaFilter.open => 'Open',
                      TaskAgendaFilter.done => 'Done',
                      TaskAgendaFilter.all => 'All',
                    }),
                    selected: _filter == filter,
                    onSelected: (_) => setState(() {
                      _filter = filter;
                      _refresh();
                    }),
                  ),
                DropdownButton<String>(
                  value: _project,
                  hint: const Text('All projects'),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('All projects'),
                    ),
                    for (final project in _cache.projects)
                      DropdownMenuItem(value: project, child: Text(project)),
                  ],
                  onChanged: (value) => setState(() {
                    _project = value;
                    _refresh();
                  }),
                ),
              ],
            ),
            TextField(
              decoration: const InputDecoration(
                hintText: 'Search task text',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => setState(() {
                _search = value;
                _refresh();
              }),
            ),
          ],
        ),
      ),
      Expanded(
        child: CustomScrollView(
          slivers: [
            if (_groups.isEmpty)
              SliverToBoxAdapter(
                child: ListTile(
                  leading: widget.indexing
                      ? const LoadingIndicator(size: 20, strokeWidth: 2)
                      : null,
                  title: Text(
                    widget.indexing ? 'Indexing…' : 'No matching tasks',
                  ),
                ),
              ),
            for (final group in _groups) ...[
              if (group.key.startsWith('upcoming:') &&
                  group ==
                      _groups.firstWhere((g) => g.key.startsWith('upcoming:')))
                const SliverToBoxAdapter(
                  child: ListTile(title: Text('Upcoming')),
                ),
              if ((group.key.startsWith('project:') ||
                      group.key.startsWith('note:')) &&
                  group ==
                      _groups.firstWhere(
                        (g) =>
                            g.key.startsWith('project:') ||
                            g.key.startsWith('note:'),
                      ))
                const SliverToBoxAdapter(
                  child: ListTile(title: Text('No date')),
                ),
              if (group.key.startsWith('journal:') &&
                  group ==
                      _groups.firstWhere((g) => g.key.startsWith('journal:')))
                const SliverToBoxAdapter(
                  child: ListTile(title: Text('From journal')),
                ),
              SliverToBoxAdapter(
                child: ListTile(
                  title: Text('${group.title} · ${group.tasks.length}'),
                  trailing: group.collapsed
                      ? Icon(
                          _expanded.contains(group.key)
                              ? Icons.expand_less
                              : Icons.expand_more,
                        )
                      : null,
                  onTap: group.collapsed
                      ? () => setState(() {
                          if (!_expanded.add(group.key)) {
                            _expanded.remove(group.key);
                          }
                        })
                      : null,
                ),
              ),
              if (!group.collapsed || _expanded.contains(group.key))
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => _row(
                      group.tasks[i],
                      journal: group.key.startsWith('journal:'),
                    ),
                    childCount: group.tasks.length,
                  ),
                ),
            ],
          ],
        ),
      ),
    ],
  );
}

class LibraryView extends StatelessWidget {
  const LibraryView({
    super.key,
    required this.index,
    this.pagedNotes,
    this.initialTab = 0,
    this.articleJobs = const [],
    required this.calendar,
    required this.dayMarks,
    this.indexing = false,
    required this.progressByPath,
    required this.onOpenPath,
    required this.onOpenDay,
    required this.onSetTaskStatus,
    required this.onSetReadStatus,
    required this.onSetRelevance,
    required this.onCreateNote,
    required this.onCreateEntity,
    required this.onImportMarkdownArticles,
    required this.onReadPath,
    required this.onDeleteArticle,
    this.imageResolver,
    this.noteToCluster = const {},
    this.shelfPrefs = const {},
    this.onShelfPrefsChanged,
  });

  final Future<Uint8List?> Function(String)? imageResolver;
  final int initialTab;
  final VaultIndex? index;
  final List<NoteRef>? pagedNotes;
  final List<ArticleJob> articleJobs;

  /// Derived once per index by the controller, not per build.
  final List<CalendarItem> calendar;
  final ({Set<String> daily, Set<String> refs}) dayMarks;
  final bool indexing;
  final Map<String, double> progressByPath;
  final Map<String, String> noteToCluster;
  final Map<String, String> shelfPrefs;
  final ValueChanged<Map<String, String>>? onShelfPrefsChanged;
  final ValueChanged<String> onOpenPath;
  final ValueChanged<DateTime> onOpenDay;
  final Future<void> Function(TaskRef task, String status) onSetTaskStatus;
  final Future<void> Function(NoteRef note, String status) onSetReadStatus;
  final Future<void> Function(NoteRef note, String relevance) onSetRelevance;
  final ValueChanged<String> onCreateNote;
  final VoidCallback onCreateEntity;
  final Future<void> Function() onImportMarkdownArticles;
  final ValueChanged<String> onReadPath;
  final Future<void> Function(NoteRef note) onDeleteArticle;

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 5,
    initialIndex: initialTab,
    child: Column(
      children: [
        const TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(text: 'Notes'),
            Tab(text: 'Articles'),
            Tab(text: 'Screenshots'),
            Tab(text: 'Tasks'),
            Tab(text: 'Calendar'),
          ],
        ),
        Expanded(
          child: TabBarView(
            children: [
              _UnifiedNotesView(
                index: index,
                pagedNotes: pagedNotes,
                indexing: indexing,
                onOpenPath: onOpenPath,
                onCreateNote: onCreateNote,
                onCreateEntity: onCreateEntity,
              ),
              _ArticlesShelf(
                articleJobs: articleJobs,
                index: index,
                pagedNotes: pagedNotes,
                indexing: indexing,
                progressByPath: progressByPath,
                onReadPath: onReadPath,
                onSetReadStatus: onSetReadStatus,
                onSetRelevance: onSetRelevance,
                onDeleteArticle: onDeleteArticle,
                onImportMarkdownArticles: onImportMarkdownArticles,
                noteToCluster: noteToCluster,
                shelfPrefs: shelfPrefs,
                onShelfPrefsChanged: onShelfPrefsChanged,
              ),
              _ArticlesShelf(
                kind: 'screenshot',
                imageResolver: imageResolver,
                index: index,
                pagedNotes: pagedNotes,
                indexing: indexing,
                progressByPath: progressByPath,
                onReadPath: onReadPath,
                onSetReadStatus: onSetReadStatus,
                onSetRelevance: onSetRelevance,
                onDeleteArticle: onDeleteArticle,
                onImportMarkdownArticles: onImportMarkdownArticles,
                noteToCluster: noteToCluster,
                shelfPrefs: const {},
                onShelfPrefsChanged: null,
              ),
              _PrimaryTasksView(
                tasks: index?.tasks ?? const <TaskRef>[],
                notes: index?.notesByPath ?? const <String, NoteRef>{},
                indexing: indexing,
                onSetStatus: onSetTaskStatus,
                onOpenPath: onOpenPath,
              ),
              CalendarTab(
                imageResolver: imageResolver,
                index: index,
                calendar: calendar,
                dayMarks: dayMarks,
                indexing: indexing,
                onOpenPath: onOpenPath,
                onOpenDay: onOpenDay,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// The unified primary list: notes, projects, and entities together, sliced
/// by kind-tag filter chips instead of the old Notes/Projects/Entities silo
/// tabs. Articles keep their own shelf (a reading-triage view, not a filter)
/// and daily notes live in Journal/Calendar, so both stay out of "All" —
/// each remains reachable via its chip.
class _UnifiedNotesView extends StatefulWidget {
  const _UnifiedNotesView({
    required this.index,
    this.pagedNotes,
    required this.indexing,
    required this.onOpenPath,
    required this.onCreateNote,
    required this.onCreateEntity,
  });

  final VaultIndex? index;
  final List<NoteRef>? pagedNotes;
  final bool indexing;
  final ValueChanged<String> onOpenPath;
  final ValueChanged<String> onCreateNote;
  final VoidCallback onCreateEntity;

  @override
  State<_UnifiedNotesView> createState() => _UnifiedNotesViewState();
}

class _UnifiedNotesViewState extends State<_UnifiedNotesView> {
  String? _kind;

  @override
  Widget build(BuildContext context) {
    final all = (widget.pagedNotes ?? widget.index?.notes ?? const <NoteRef>[])
        .where((note) => note.kind != 'daily')
        .toList();
    final kinds = {for (final note in all) note.kind}..remove('note');
    final chips = kinds.toList()..sort();
    final selected = _kind;
    final notes = all.where((note) {
      if (selected != null) return note.kind == selected;
      return note.kind != 'article' && note.kind != 'screenshot';
    }).toList()..sort((a, b) => a.title.compareTo(b.title));
    return Column(
      children: [
        if (chips.isNotEmpty)
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final kind in chips)
                  Padding(
                    padding: const EdgeInsets.only(right: 8, top: 6),
                    child: FilterChip(
                      avatar: Icon(iconForKind(kind), size: 16),
                      label: Text(kind),
                      selected: selected == kind,
                      onSelected: (_) => setState(
                        () => _kind = selected == kind ? null : kind,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: 1 + (notes.isEmpty ? 1 : notes.length),
            itemBuilder: (context, i) {
              if (i == 0) {
                return Row(
                  children: [
                    Expanded(
                      child: ListTile(
                        leading: const Icon(Icons.add),
                        title: const Text('New note'),
                        onTap: () => widget.onCreateNote(_kind ?? 'note'),
                      ),
                    ),
                    Expanded(
                      child: ListTile(
                        leading: const Icon(Icons.person_add_alt),
                        title: const Text('New entity'),
                        onTap: widget.onCreateEntity,
                      ),
                    ),
                  ],
                );
              }
              if (notes.isEmpty) {
                return ListTile(
                  leading: widget.indexing
                      ? const LoadingIndicator(size: 20, strokeWidth: 2)
                      : null,
                  title: Text(widget.indexing ? 'Indexing…' : 'No notes yet'),
                );
              }
              final note = notes[i - 1];
              final isEntity = !structuralNoteKinds.contains(note.kind);
              return ListTile(
                // Shared kind→icon map so a person reads as a person here too.
                leading: Icon(iconForKind(note.kind)),
                title: Text(note.title),
                subtitle: isEntity || note.kind == 'project'
                    ? Text(
                        [
                          note.kind,
                          if (note.aliases.isNotEmpty) note.aliases.join(', '),
                        ].join(' · '),
                      )
                    : null,
                onTap: () => widget.onOpenPath(note.path),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// The Articles tab as a reading shelf: status filter (Inbox/Reading/Read),
/// search, sort, and metadata-based grouping over the indexed articles.
/// All state is derived in-memory from [VaultIndex]; only the status property
/// write goes back to disk (via [onSetReadStatus]).
class _ArticlesShelf extends StatefulWidget {
  const _ArticlesShelf({
    this.kind = 'article',
    this.imageResolver,
    required this.index,
    this.pagedNotes,
    this.articleJobs = const [],
    required this.indexing,
    required this.progressByPath,
    required this.onReadPath,
    required this.onSetReadStatus,
    required this.onSetRelevance,
    required this.onDeleteArticle,
    required this.onImportMarkdownArticles,
    this.noteToCluster = const {},
    required this.shelfPrefs,
    required this.onShelfPrefsChanged,
  });

  final String kind;
  final Future<Uint8List?> Function(String)? imageResolver;
  final VaultIndex? index;
  final List<NoteRef>? pagedNotes;
  final List<ArticleJob> articleJobs;
  final bool indexing;
  final Map<String, double> progressByPath;
  final Map<String, String> noteToCluster;
  final Map<String, String> shelfPrefs;
  final ValueChanged<Map<String, String>>? onShelfPrefsChanged;
  final ValueChanged<String> onReadPath;
  final Future<void> Function(NoteRef note, String status) onSetReadStatus;
  final Future<void> Function(NoteRef note, String relevance) onSetRelevance;
  final Future<void> Function(NoteRef note) onDeleteArticle;
  final Future<void> Function() onImportMarkdownArticles;

  @override
  State<_ArticlesShelf> createState() => _ArticlesShelfState();
}

class _ArticlesShelfState extends State<_ArticlesShelf> {
  final _query = TextEditingController();
  String? statusFilter;
  String? relevanceFilter;
  String sort = 'recent';
  String groupBy = 'none';

  @override
  void initState() {
    super.initState();
    final p = widget.shelfPrefs; // hydrate persisted choices
    statusFilter = p['status'];
    relevanceFilter = p['relevance'];
    sort = p['sort'] ?? 'recent';
    groupBy = p['group'] ?? (screenshots ? 'source' : 'none');
  }

  /// Persist the current filter/sort/group so they survive an app restart.
  void _persist() => widget.onShelfPrefsChanged?.call({
    'status': ?statusFilter,
    'relevance': ?relevanceFilter,
    'sort': sort,
    'group': groupBy,
  });

  static const _sortLabels = {
    'recent': 'Recently updated',
    'progress': 'Reading progress',
    'title': 'Title',
    'relevance': 'Relevance',
  };
  static const _groupLabels = {
    'none': 'No grouping',
    'tag': 'Group by tag',
    'year': 'Group by year',
    'source': 'Group by source',
    'cluster': 'Group by cluster',
  };

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  /// Maps a note onto one of the five reading-triage stages
  /// (unread → skimmed → read → extracted → cited).
  bool get screenshots => widget.kind == 'screenshot';
  List<String> get statuses =>
      screenshots ? screenshotStatusOptions : articleStatusOptions;
  Map<String, String> get labels =>
      screenshots ? screenshotStatusLabels : articleStatusLabels;
  String _bucket(NoteRef note) => screenshots
      ? screenshotStatusStage(note.properties['status'] as String?)
      : articleStatusStage(note.properties['status'] as String?);

  /// high > medium > low > unrated, for the relevance sort.
  static int _relevanceRank(NoteRef note) =>
      switch (note.properties['relevance']) {
        'high' => 3,
        'medium' => 2,
        'low' => 1,
        _ => 0,
      };

  String? _source(NoteRef note) {
    if (screenshots) return note.properties['source_app'] as String?;
    final url = note.properties['url'] as String?;
    final host = url == null ? null : Uri.tryParse(url)?.host;
    if (host != null && host.isNotEmpty) return host;
    final name = note.properties['import_source_name'] as String?;
    return name == null || name.isEmpty ? null : name;
  }

  String _groupKey(NoteRef note) => switch (groupBy) {
    'tag' => note.tags.isEmpty ? 'Untagged' : note.tags.first,
    'year' => _year(note),
    'month' =>
      note.date != null && note.date!.length >= 7
          ? note.date!.substring(0, 7)
          : 'Undated',
    'cluster' => widget.noteToCluster[note.path] ?? 'Uncategorized',
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
    final all = (widget.pagedNotes ?? widget.index?.notes ?? const <NoteRef>[])
        .where((note) => note.kind == widget.kind)
        .toList();
    final q = _query.text.trim().toLowerCase();
    final searched = q.isEmpty
        ? all
        : all
              .where(
                (note) =>
                    note.title.toLowerCase().contains(q) ||
                    note.tags.any((tag) => tag.toLowerCase().contains(q)) ||
                    (screenshots &&
                        '${note.properties['source_app']} ${note.properties['keywords']}'
                            .toLowerCase()
                            .contains(q)),
              )
              .toList();
    final counts = {for (final stage in statuses) stage: 0};
    for (final note in searched) {
      counts[_bucket(note)] = (counts[_bucket(note)] ?? 0) + 1;
    }
    final filtered = searched.where((note) {
      if (statusFilter != null && _bucket(note) != statusFilter) return false;
      if (relevanceFilter != null &&
          note.properties['relevance'] != relevanceFilter) {
        return false;
      }
      return true;
    }).toList();
    filtered.sort(switch (sort) {
      'progress' => (a, b) => (widget.progressByPath[b.path] ?? 0).compareTo(
        widget.progressByPath[a.path] ?? 0,
      ),
      'title' => (a, b) => a.title.toLowerCase().compareTo(
        b.title.toLowerCase(),
      ),
      'relevance' => (a, b) => _relevanceRank(b).compareTo(_relevanceRank(a)),
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

    final statusChips = <(String?, String)>[
      (null, 'All'),
      for (final stage in statuses) (stage, labels[stage]!),
    ];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: Key(
                    '${screenshots ? 'screenshots' : 'articles'}-search',
                  ),
                  controller: _query,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search),
                    hintText:
                        'Search ${screenshots ? 'screenshots' : 'articles'}',
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
                key: Key('${screenshots ? 'screenshots' : 'articles'}-sort'),
                tooltip: 'Sort: ${_sortLabels[sort]}',
                icon: const Icon(Icons.sort),
                initialValue: sort,
                onSelected: (value) {
                  setState(() => sort = value);
                  _persist();
                },
                itemBuilder: (_) => [
                  for (final entry in _sortLabels.entries)
                    PopupMenuItem(value: entry.key, child: Text(entry.value)),
                ],
              ),
              PopupMenuButton<String>(
                key: Key('${screenshots ? 'screenshots' : 'articles'}-group'),
                tooltip: 'Grouping: ${_groupLabels[groupBy]}',
                icon: const Icon(Icons.workspaces_outline),
                initialValue: groupBy,
                onSelected: (value) {
                  setState(() => groupBy = value);
                  _persist();
                },
                itemBuilder: (_) => [
                  for (final entry
                      in (screenshots
                              ? const {
                                  'none': 'No grouping',
                                  'source': 'Group by source app',
                                  'month': 'Group by month',
                                }
                              : _groupLabels)
                          .entries)
                    PopupMenuItem(value: entry.key, child: Text(entry.value)),
                ],
              ),
            ],
          ),
        ),
        if (screenshots)
          SingleChildScrollView(
            key: const Key('screenshots-filters'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              children: [
                for (final (value, label) in statusChips)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(
                        '$label · ${value == null ? searched.length : counts[value]}',
                      ),
                      selected: statusFilter == value,
                      onSelected: (_) => setState(() => statusFilter = value),
                    ),
                  ),
                for (final (value, label) in <(String?, String)>[
                  (null, 'Any relevance'),
                  for (final r in relevanceOptions) (r, relevanceLabels[r]!),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: relevanceFilter == value,
                      onSelected: (_) =>
                          setState(() => relevanceFilter = value),
                    ),
                  ),
              ],
            ),
          )
        else ...[
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
                      onSelected: (_) {
                        setState(() => statusFilter = value);
                        _persist();
                      },
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                children: [
                  for (final (value, label) in <(String?, String)>[
                    (null, 'Any relevance'),
                    for (final r in relevanceOptions) (r, relevanceLabels[r]!),
                  ])
                    ChoiceChip(
                      label: Text(label),
                      selected: relevanceFilter == value,
                      onSelected: (_) {
                        setState(() => relevanceFilter = value);
                        _persist();
                      },
                    ),
                ],
              ),
            ),
          ),
        ],
        Expanded(
          child: screenshots
              ? CustomScrollView(
                  slivers: [
                    if (filtered.isEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            widget.indexing && all.isEmpty
                                ? 'Indexing…'
                                : all.isEmpty
                                ? 'No screenshots yet'
                                : 'Nothing matches',
                          ),
                        ),
                      ),
                    for (final (header, notes) in groups) ...[
                      if (header.isNotEmpty)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
                            child: Text(
                              '$header · ${notes.length}',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                        ),
                      SliverPadding(
                        padding: const EdgeInsets.all(4),
                        sliver: SliverLayoutBuilder(
                          builder: (context, constraints) {
                            final columns = max(
                              1,
                              (constraints.crossAxisExtent / (180 + 8)).ceil(),
                            );
                            final width =
                                (constraints.crossAxisExtent -
                                    (columns - 1) * 8) /
                                columns;
                            final scaler = MediaQuery.textScalerOf(context);
                            return SliverGrid(
                              gridDelegate:
                                  SliverGridDelegateWithMaxCrossAxisExtent(
                                    maxCrossAxisExtent: 180,
                                    crossAxisSpacing: 8,
                                    mainAxisSpacing: 8,
                                    mainAxisExtent:
                                        width * 16 / 9 +
                                        scaler.scale(48) +
                                        scaler.scale(18) +
                                        24,
                                  ),
                              delegate: SliverChildBuilderDelegate(
                                (context, i) => _screenshotCard(notes[i]),
                                childCount: notes.length,
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                )
              : ListView(
                  children: [
                    if (!screenshots)
                      ListTile(
                        key: const ValueKey('import-markdown-articles'),
                        leading: const Icon(Icons.file_upload_outlined),
                        title: const Text('Import Markdown articles'),
                        subtitle: const Text(
                          'Select one or more .md or .markdown files',
                        ),
                        onTap: () =>
                            unawaited(widget.onImportMarkdownArticles()),
                      ),
                    if (!screenshots)
                      for (final job in widget.articleJobs.where(
                        (job) => '${job.title ?? ''} ${job.url}'
                            .toLowerCase()
                            .contains(q),
                      ))
                        ListTile(
                          key: ValueKey(job.path),
                          leading: Icon(
                            job.status == 'processing'
                                ? Icons.hourglass_top
                                : Icons.schedule,
                          ),
                          title: Text(job.title ?? job.url),
                          subtitle: Text(
                            '${job.status == 'processing' ? 'Processing' : 'Queued'} · ${job.url}',
                          ),
                        ),
                    if (!screenshots && continueNote != null)
                      Card(
                        key: Key(
                          '${screenshots ? 'screenshots' : 'articles'}-continue-reading',
                        ),
                        child: ListTile(
                          leading: const Icon(Icons.auto_stories),
                          title: Text(
                            'Continue reading · ${continueNote.title}',
                          ),
                          subtitle: LinearProgressIndicator(
                            value: continueProgress,
                          ),
                          trailing: Text(
                            '${(continueProgress * 100).round()}%',
                          ),
                          onTap: () => widget.onReadPath(continueNote!.path),
                        ),
                      ),
                    if (filtered.isEmpty &&
                        (screenshots || widget.articleJobs.isEmpty))
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (widget.indexing && all.isEmpty) ...[
                                const LoadingIndicator(
                                  size: 20,
                                  strokeWidth: 2,
                                ),
                                const SizedBox(width: 8),
                              ],
                              Text(
                                widget.indexing && all.isEmpty
                                    ? 'Indexing…'
                                    : q.isNotEmpty || statusFilter != null
                                    ? 'Nothing matches'
                                    : screenshots
                                    ? 'No screenshots yet'
                                    : 'No articles yet — import one above',
                              ),
                            ],
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

  String _screenshotMetadata(NoteRef note) => [
    if (screenshotCapturedAt(note) case final time?) localTime(time),
    _source(note)?.trim() ?? '',
  ].where((part) => part.isNotEmpty).join(' · ');

  String _screenshotTitle(NoteRef note) {
    final title = note.title.trim();
    if (title.isNotEmpty &&
        !title.startsWith('Screenshot_') &&
        !RegExp(
          r'\.(png|jpe?g|webp|gif|heic|heif|bmp|tiff?)$',
          caseSensitive: false,
        ).hasMatch(title)) {
      return title;
    }
    final description = note.screenshotDescription.trim();
    if (description.isNotEmpty) {
      final sentence = description
          .replaceAll(RegExp(r'\s+'), ' ')
          .split(RegExp(r'(?<=[.!?。！？])\s+'))
          .first;
      return sentence.characters.length <= 60
          ? sentence
          : '${sentence.characters.take(59)}…';
    }
    return 'Screenshot';
  }

  void _screenshotActions(NoteRef note) => unawaited(
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _screenshotTitle(note),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Wrap(
                  spacing: 12,
                  children: [
                    PropertySelectChip(
                      value: _bucket(note),
                      options: statuses,
                      labels: labels,
                      tooltip: 'Change status',
                      onChanged: (next) {
                        Navigator.pop(context);
                        unawaited(widget.onSetReadStatus(note, next));
                      },
                    ),
                    PropertySelectChip(
                      value: note.properties['relevance'] as String?,
                      options: relevanceOptions,
                      labels: relevanceLabels,
                      tooltip: 'Set relevance',
                      placeholder: '★',
                      onChanged: (next) {
                        Navigator.pop(context);
                        unawaited(widget.onSetRelevance(note, next));
                      },
                    ),
                  ],
                ),
                ListTile(
                  leading: const Icon(Icons.open_in_new),
                  title: const Text('Open screenshot'),
                  onTap: () {
                    Navigator.pop(context);
                    widget.onReadPath(note.path);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Delete screenshot…'),
                  onTap: () {
                    Navigator.pop(context);
                    unawaited(widget.onDeleteArticle(note));
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _screenshotCard(NoteRef note) => Align(
    alignment: Alignment.topCenter,
    child: Card(
      key: ValueKey(note.path),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => widget.onReadPath(note.path),
        onLongPress: () => _screenshotActions(note),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(kRadiusMedium),
                    child: ScreenshotThumbnail(
                      note: note,
                      imageResolver: widget.imageResolver,
                      width: null,
                      height: null,
                    ),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: IconButton.filledTonal(
                      tooltip: 'Screenshot actions',
                      icon: const Icon(Icons.more_vert),
                      onPressed: () => _screenshotActions(note),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Text(
                _screenshotTitle(note),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(height: 1.4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                _screenshotMetadata(note),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _row(NoteRef note) {
    final subtitle = [
      ?_source(note),
      if (note.tags.isNotEmpty) note.tags.map((tag) => '#$tag').join(' '),
    ].join(' · ');
    return ListTile(
      leading: screenshots
          ? ScreenshotThumbnail(note: note, imageResolver: widget.imageResolver)
          : const Icon(Icons.article_outlined),
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
    final status = _bucket(note);
    final progress = widget.progressByPath[note.path] ?? 0;
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground) = switch (status) {
      'reading' => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
      'read' => (scheme.secondaryContainer, scheme.onSecondaryContainer),
      _ => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
    };
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
          options: statuses,
          labels: labels,
          tooltip: 'Change status',
          backgroundColor: background,
          foregroundColor: foreground,
          onChanged: (next) => unawaited(widget.onSetReadStatus(note, next)),
        ),
        const SizedBox(width: 6),
        PropertySelectChip(
          value: note.properties['relevance'] as String?,
          options: relevanceOptions,
          labels: relevanceLabels,
          tooltip: 'Set relevance',
          placeholder: '★',
          onChanged: (next) => unawaited(widget.onSetRelevance(note, next)),
        ),
        // Long-press delete has no visible affordance; this menu makes it
        // discoverable without displacing the status/relevance chips.
        PopupMenuButton<String>(
          tooltip: 'More',
          icon: const Icon(Icons.more_vert),
          onSelected: (value) {
            if (value == 'delete') unawaited(widget.onDeleteArticle(note));
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'delete',
              child: Text(
                'Delete ${screenshots ? 'screenshot' : 'article'}…',
                style: TextStyle(color: scheme.error),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
