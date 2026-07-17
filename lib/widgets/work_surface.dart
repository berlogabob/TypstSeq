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
  });

  final List<TaskRef> tasks;
  final List<(NoteRef note, double progress)> recent;
  final Widget editor;
  final ValueChanged<String> onOpenPath;
  final Future<void> Function(TaskRef task, String status) onSetStatus;

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
                  onTap: () => onOpenPath(note.path),
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
  });

  final VaultIndex? index;
  final Map<String, double> progressByPath;
  final ValueChanged<String> onOpenPath;
  final ValueChanged<DateTime> onOpenDay;
  final Future<void> Function(TaskRef task, String status) onSetTaskStatus;
  final Future<void> Function(NoteRef note, String status) onSetReadStatus;
  final VoidCallback onCreateEntity;
  final Future<void> Function() onImportMarkdownArticles;

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
              _notes('article'),
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
    final showImport = kind == 'article';
    return ListView.builder(
      itemCount: (showImport ? 1 : 0) + notes.length,
      itemBuilder: (context, i) {
        if (showImport && i == 0) {
          return ListTile(
            key: const ValueKey('import-markdown-articles'),
            leading: const Icon(Icons.file_upload_outlined),
            title: const Text('Import Markdown articles'),
            subtitle: const Text('Select one or more .md or .markdown files'),
            onTap: () => unawaited(onImportMarkdownArticles()),
          );
        }
        final note = notes[showImport ? i - 1 : i];
        return ListTile(
          leading: Icon(switch (kind) {
            'project' => Icons.work_outline,
            'article' => Icons.article_outlined,
            _ => Icons.notes,
          }),
          title: Text(note.title),
          subtitle: Text(note.path),
          trailing: kind != 'article' ? null : _articleTrailing(note),
          onTap: () => onOpenPath(note.path),
        );
      },
    );
  }

  Widget _articleTrailing(NoteRef note) {
    final status = note.properties['status'] as String? ?? 'unread';
    final progress = progressByPath[note.path] ?? 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (progress > 0 && progress < 1) ...[
          SizedBox(width: 40, child: LinearProgressIndicator(value: progress)),
          const SizedBox(width: 8),
        ],
        PropertySelectChip(
          value: status,
          options: articleStatusOptions,
          labels: articleStatusLabels,
          tooltip: 'Change status',
          onChanged: (next) => unawaited(onSetReadStatus(note, next)),
        ),
      ],
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
