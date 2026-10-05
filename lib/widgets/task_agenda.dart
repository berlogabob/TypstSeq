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

/// Identity-keyed cache: indexing must publish a new task list or note map.
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
    if (identical(tasks, _tasks) && identical(notes, _notes) && today == _day) {
      return _groups;
    }
    _tasks = tasks;
    _notes = notes;
    _day = today;
    projects = tasks.map((t) => t.project).whereType<String>().toSet().toList()
      ..sort();
    final date = DateTime.parse(today);
    final horizon = isoDay(DateTime(date.year, date.month, date.day + 14));
    final cutoff = isoDay(DateTime(date.year, date.month, date.day - 6));
    final buckets = <String, List<TaskRef>>{};
    final titles = <String, String>{};
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
          key = task.project != null
              ? 'project:${task.project}'
              : 'note:${task.notePath}';
          titles[key] =
              task.project ?? notes[task.notePath]?.title ?? task.notePath;
        } else {
          key = day.compareTo(horizon) <= 0 ? 'upcoming:$day' : 'later';
        }
      }
      buckets.putIfAbsent(key, () => []).add(task);
    }
    final keys = [
      'overdue',
      'today',
      ...(buckets.keys.where((k) => k.startsWith('upcoming:')).toList()
        ..sort()),
      'later',
      ...(titles.keys.toList()
        ..sort((a, b) => titles[a]!.compareTo(titles[b]!))),
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
              _ => titles[key] ?? key.substring(9),
            },
            List.unmodifiable(buckets[key]!),
            collapsed: key == 'done' || titles.containsKey(key),
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
