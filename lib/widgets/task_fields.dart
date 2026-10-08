import 'package:flutter/material.dart';
import 'package:tylog_core/scanner.dart';
import '../models.dart';
import 'package:tylog_core/tylog_core.dart' show parseDateWords;
import '../controlled_editor.dart' show localTime;
import 'date_format.dart';

TaskRef taskFromSource(String source, {String notePath = ''}) {
  final id = taskField(source, 'id')!;
  return TaskRef(
    id: id,
    notePath: notePath,
    text: taskField(source, 'text')!,
    status: taskField(source, 'status') ?? 'todo',
    priority: taskField(source, 'priority') ?? 'normal',
    due: taskField(source, 'due'),
    scheduled: taskField(source, 'scheduled'),
    recurrence: taskField(source, 'recurrence'),
    clocked: taskClocked(source, id),
  );
}

const taskPriorities = ['urgent', 'high', 'normal', 'low'];
const taskPriorityCommands = ['urgent', 'a', 'b', 'c'];
const taskStatuses = ['todo', 'doing', 'done', 'cancelled'];
const taskRepeats = ['daily', 'weekly', 'monthly', 'weekdays'];
String taskRepeatRule(String repeat) => switch (repeat) {
  'daily' => 'RRULE:FREQ=DAILY',
  'weekly' => 'RRULE:FREQ=WEEKLY',
  'monthly' => 'RRULE:FREQ=MONTHLY',
  _ => 'RRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR',
};

class TaskFieldList extends StatelessWidget {
  const TaskFieldList({
    super.key,
    required this.field,
    required this.input,
    required this.focus,
    required this.dates,
    required this.highlighted,
    required this.onChanged,
    required this.onSubmitted,
    required this.onCalendar,
    required this.onRepeat,
    required this.onPriority,
    required this.onDate,
  });
  final String field;
  final TextEditingController input;
  final FocusNode focus;
  final List<DateTime> dates;
  final int highlighted;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onCalendar;
  final ValueChanged<String> onRepeat;
  final ValueChanged<String> onPriority;
  final ValueChanged<DateTime> onDate;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (field != 'repeat' && field != 'priority')
        TextField(
          key: const Key('task-date-input'),
          autofocus: true,
          controller: input,
          focusNode: focus,
          decoration: InputDecoration(
            hintText: 'today / завтра / +3d',
            suffixIcon: IconButton(
              tooltip: 'Calendar',
              onPressed: onCalendar,
              icon: const Icon(Icons.calendar_month),
            ),
          ),
          onChanged: onChanged,
          onSubmitted: onSubmitted,
        ),
      Flexible(
        child: ListView(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          children: [
            if (field == 'priority')
              for (final (i, priority) in taskPriorities.indexed)
                ListTile(
                  key: Key('autocomplete-task-${taskPriorityCommands[i]}'),
                  minTileHeight: 48,
                  dense: true,
                  title: Text(priority),
                  selected: highlighted == i,
                  onTap: () => onPriority(priority),
                )
            else if (field == 'repeat')
              for (final (i, repeat) in taskRepeats.indexed)
                ListTile(
                  minTileHeight: 48,
                  dense: true,
                  title: Text(repeat),
                  selected: highlighted == i,
                  onTap: () => onRepeat(repeat),
                )
            else
              for (final (i, date) in dates.indexed)
                ListTile(
                  minTileHeight: 48,
                  dense: true,
                  title: Text(isoDay(date)),
                  subtitle: date.hour != 0 || date.minute != 0
                      ? Text(localTime(date))
                      : null,
                  selected: highlighted == i,
                  onTap: () => onDate(date),
                ),
          ],
        ),
      ),
    ],
  );
}

class TaskStatusMenu extends StatelessWidget {
  const TaskStatusMenu({
    super.key,
    required this.anchors,
    required this.onStatus,
  });
  final TextSelectionToolbarAnchors anchors;
  final ValueChanged<String> onStatus;
  @override
  Widget build(BuildContext context) =>
      AdaptiveTextSelectionToolbar.buttonItems(
        anchors: anchors,
        buttonItems: [
          for (final status in taskStatuses)
            ContextMenuButtonItem(
              label: status,
              onPressed: () => onStatus(status),
            ),
        ],
      );
}

class TaskFieldPopup extends StatefulWidget {
  const TaskFieldPopup({super.key, required this.field});
  final String field;
  @override
  State<TaskFieldPopup> createState() => _TaskFieldPopupState();
}

class _TaskFieldPopupState extends State<TaskFieldPopup> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _now = DateTime.now();
  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _pick(DateTime date) => Navigator.pop(
    context,
    date.hour == 0 && date.minute == 0
        ? isoDay(date)
        : '${isoDay(date)}T${localTime(date)}',
  );
  @override
  Widget build(BuildContext context) {
    final dates = parseDateWords(_input.text, _now);
    return TaskFieldList(
      field: widget.field,
      input: _input,
      focus: _focus,
      dates: dates,
      highlighted: 0,
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) {
        if (dates.isNotEmpty) _pick(dates.first);
      },
      onPriority: (priority) => Navigator.pop(context, priority),
      onRepeat: (repeat) => Navigator.pop(context, taskRepeatRule(repeat)),
      onDate: _pick,
      onCalendar: () async {
        final date = await showDatePicker(
          context: context,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
          initialDate: dates.firstOrNull ?? _now,
        );
        if (mounted && date != null) _pick(date);
      },
    );
  }
}
