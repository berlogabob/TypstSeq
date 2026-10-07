import 'package:flutter/foundation.dart';

import '../models.dart';
import 'date_format.dart';

bool isTaskInTodayAgenda(TaskRef task, String today) {
  if (task.status == 'done' || task.status == 'cancelled') return false;
  final due = task.due?.split('T').first;
  final scheduled = task.scheduled?.split('T').first;
  return (due != null && due.compareTo(today) <= 0) ||
      (scheduled != null && scheduled.compareTo(today) <= 0);
}

bool isTaskOverdue(TaskRef task, String today) {
  if (task.status == 'done' || task.status == 'cancelled') return false;
  final due = task.due?.split('T').first;
  return due != null && due.compareTo(today) < 0;
}

final _journalPath = RegExp(r'^daily/\d{4}/\d{2}/(\d{4}-\d{2}-\d{2})\.typ$');

bool isJournalTask(TaskRef task, Map<String, NoteRef> notes) =>
    notes[task.notePath]?.kind == 'daily' ||
    _journalPath.hasMatch(task.notePath);

DateTime? journalTaskDay(TaskRef task, Map<String, NoteRef> notes) {
  final note = notes[task.notePath];
  final day =
      (note == null ? null : dailyDayOf(note)) ??
      _journalPath.firstMatch(task.notePath)?.group(1);
  return day == null ? null : DateTime.tryParse(day);
}

enum TaskAgendaFilter { open, done, all }

class TaskAgendaGroup {
  const TaskAgendaGroup(
    this.key,
    this.title,
    this.tasks, {
    this.collapsed = false,
  });
  final String key;
  final String title;
  final List<TaskRef> tasks;
  final bool collapsed;
}

/// Snapshot the collections: the workspace updates its index in place.
/// Day is also a key so an agenda never retains yesterday's buckets.
class TaskAgendaCache {
  List<TaskRef>? _tasks;
  Map<String, NoteRef>? _notes;
  String? _day;
  List<TaskAgendaGroup> _groups = const [];
  List<String> projects = const [];

  List<TaskAgendaGroup> resolve(
    List<TaskRef> tasks,
    Map<String, NoteRef> notes,
    String today,
  ) {
    if (listEquals(tasks, _tasks) &&
        mapEquals(notes, _notes) &&
        today == _day) {
      return _groups;
    }
    _tasks = List.of(tasks);
    _notes = Map.of(notes);
    _day = today;
    projects = tasks.map((t) => t.project).whereType<String>().toSet().toList()
      ..sort();
    final date = DateTime.parse(today);
    final horizon = isoDay(DateTime(date.year, date.month, date.day + 14));
    final cutoff = isoDay(DateTime(date.year, date.month, date.day - 6));
    final buckets = <String, List<TaskRef>>{};
    final titles = <String, String>{};
    final journalTitles = <String, String>{};
    final sorted = tasks.toList()
      ..sort((a, b) {
        final order = (a.due ?? a.scheduled ?? '9999').compareTo(
          b.due ?? b.scheduled ?? '9999',
        );
        return order != 0 ? order : a.id.compareTo(b.id);
      });
    for (final task in sorted) {
      String key;
      if (task.status == 'cancelled') continue;
      if (task.status == 'done') {
        final completed =
            task.completed
                .map((s) => s.split('T').first)
                .where((s) => DateTime.tryParse(s) != null)
                .toList()
              ..sort();
        if (completed.isEmpty ||
            completed.last.compareTo(cutoff) < 0 ||
            completed.last.compareTo(today) > 0) {
          continue;
        }
        key = 'done';
      } else if (isTaskOverdue(task, today)) {
        key = 'overdue';
      } else if (isTaskInTodayAgenda(task, today) ||
          (notes[task.notePath] != null &&
              notes[task.notePath]!.kind == 'daily' &&
              dailyDayOf(notes[task.notePath]!) == today)) {
        key = 'today';
      } else {
        final day = (task.due ?? task.scheduled)?.split('T').first;
        if (day == null) {
          if (isJournalTask(task, notes)) {
            final day = journalTaskDay(task, notes);
            key = day == null
                ? 'journal:unknown'
                : 'journal:${isoDay(day).substring(0, 7)}';
            journalTitles[key] = day == null ? 'Unknown date' : monthYear(day);
          } else {
            key = task.project != null
                ? 'project:${task.project}'
                : 'note:${task.notePath}';
            titles[key] =
                task.project ?? notes[task.notePath]?.title ?? task.notePath;
          }
        } else {
          key = day.compareTo(horizon) <= 0 ? 'upcoming:$day' : 'later';
        }
      }
      buckets.putIfAbsent(key, () => []).add(task);
    }
    for (final key in journalTitles.keys) {
      buckets[key]!.sort((a, b) {
        final order = (journalTaskDay(b, notes)?.toIso8601String() ?? '')
            .compareTo(journalTaskDay(a, notes)?.toIso8601String() ?? '');
        return order != 0 ? order : a.id.compareTo(b.id);
      });
    }
    final keys = [
      'overdue',
      'today',
      ...(buckets.keys.where((k) => k.startsWith('upcoming:')).toList()
        ..sort()),
      'later',
      ...(titles.keys.toList()..sort((a, b) {
        final count = buckets[b]!.length.compareTo(buckets[a]!.length);
        return count != 0 ? count : titles[a]!.compareTo(titles[b]!);
      })),
      ...(journalTitles.keys.where((k) => k != 'journal:unknown').toList()
        ..sort((a, b) => b.compareTo(a))),
      'journal:unknown',
      'done',
    ];
    _groups = [
      for (final key in keys)
        if (buckets.containsKey(key))
          TaskAgendaGroup(
            key,
            switch (key) {
              'overdue' => 'Overdue',
              'today' => 'Today',
              'later' => 'Later',
              'done' => 'Done',
              _ => titles[key] ?? journalTitles[key] ?? key.substring(9),
            },
            List.unmodifiable(buckets[key]!),
            collapsed:
                key == 'done' ||
                titles.containsKey(key) ||
                journalTitles.containsKey(key),
          ),
    ];
    return _groups;
  }
}

List<TaskAgendaGroup> filterTaskAgenda(
  List<TaskAgendaGroup> groups,
  TaskAgendaFilter filter,
  String? project,
  String query,
) {
  final search = query.trim().toLowerCase();
  final result = <TaskAgendaGroup>[];
  for (final group in groups) {
    if (filter == TaskAgendaFilter.open && group.key == 'done' ||
        filter == TaskAgendaFilter.done && group.key != 'done') {
      continue;
    }
    final tasks = group.tasks
        .where(
          (task) =>
              (project == null || task.project == project) &&
              (search.isEmpty || task.text.toLowerCase().contains(search)),
        )
        .toList();
    if (tasks.isNotEmpty) {
      result.add(
        TaskAgendaGroup(
          group.key,
          group.title,
          tasks,
          collapsed: group.collapsed,
        ),
      );
    }
  }
  return result;
}
