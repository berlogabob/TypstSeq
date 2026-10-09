import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:tylog_core/scanner.dart';
import '../models.dart';
import 'package:tylog_core/tylog_core.dart' show parseDateWords;
import '../controlled_editor.dart' show localTime;
import 'date_format.dart';
import 'constants.dart';

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
const taskRepeats = ['daily', 'weekly', 'monthly', 'weekdays', 'none'];
String taskRepeatRule(String repeat) => switch (repeat) {
  'none' => 'none',
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
    required this.onClear,
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
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (field != 'repeat' && field != 'priority' && field != 'status')
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: kSpace16),
          child: TextField(
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
        ),
      Flexible(
        child: ListView(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          children: [
            if (field == 'status')
              for (final status in taskStatuses)
                ListTile(
                  minTileHeight: 48,
                  dense: true,
                  title: Text(status),
                  onTap: () => onPriority(status),
                )
            else if (field == 'priority')
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
            if (field == 'due' || field == 'scheduled')
              ListTile(
                title: const Text('none'),
                selected: highlighted == dates.length,
                onTap: onClear,
              ),
          ],
        ),
      ),
    ],
  );
}

class TaskFieldPopup extends StatefulWidget {
  const TaskFieldPopup({
    super.key,
    required this.field,
    this.anchor,
    this.bounds,
    this.onPicked,
  });
  final String field;
  final Rect? anchor;
  final Rect? bounds;
  final ValueChanged<String>? onPicked;
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

  void _complete(String value) {
    if (widget.onPicked != null) {
      widget.onPicked!(value);
    } else {
      Navigator.pop(context, value);
    }
  }

  void _pick(DateTime date) => _complete(
    date.hour == 0 && date.minute == 0
        ? isoDay(date)
        : '${isoDay(date)}T${localTime(date)}',
  );
  @override
  Widget build(BuildContext context) {
    final dates = parseDateWords(_input.text, _now);
    final list = TaskFieldList(
      field: widget.field,
      input: _input,
      focus: _focus,
      dates: dates,
      highlighted: 0,
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) {
        if (dates.isNotEmpty) _pick(dates.first);
      },
      onPriority: _complete,
      onRepeat: (repeat) => _complete(taskRepeatRule(repeat)),
      onDate: _pick,
      onClear: () => _complete('none'),
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
    if (widget.anchor == null) return list;
    return LayoutBuilder(
      builder: (context, constraints) {
        final media = MediaQuery.of(context);
        final bounds = widget.bounds!.intersect(
          Rect.fromLTRB(
            media.padding.left,
            media.padding.top,
            constraints.maxWidth - media.padding.right,
            constraints.maxHeight -
                math.max(media.viewInsets.bottom, media.padding.bottom),
          ),
        );
        final height = switch (widget.field) {
          'priority' => taskPriorities.length * 48.0,
          'status' => taskStatuses.length * 48.0,
          'repeat' => taskRepeats.length * 48.0,
          _ => math.min(
            260.0,
            104.0 +
                dates.fold<double>(
                  0,
                  (sum, date) =>
                      sum + (date.hour != 0 || date.minute != 0 ? 72 : 48),
                ),
          ),
        };
        final rect = autocompletePopupRect(
          widget.anchor!.shift(-bounds.topLeft),
          bounds.size,
          Size(280, height),
        ).shift(bounds.topLeft);
        return Stack(
          children: [
            Positioned(
              left: rect.left,
              width: rect.width,
              top: rect.bottom > widget.anchor!.top ? rect.top : null,
              bottom: rect.bottom <= widget.anchor!.top
                  ? constraints.maxHeight - rect.bottom
                  : null,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: rect.height),
                child: TextFieldTapRegion(
                  child: Material(
                    key: const Key('task-field-popup'),
                    elevation: 6,
                    borderRadius: BorderRadius.circular(kRadiusMedium),
                    clipBehavior: Clip.antiAlias,
                    child: list,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Sets only [field]; every other task field keeps its bytes.
String setOneTaskField(String source, String id, String field, String value) =>
    switch (field) {
      'priority' => setTaskFields(source, id, priority: value),
      'due' => setTaskFields(source, id, due: value == 'none' ? null : value),
      'scheduled' => setTaskFields(
        source,
        id,
        scheduled: value == 'none' ? null : value,
      ),
      'repeat' => setTaskFields(
        source,
        id,
        recurrence: value == 'none' ? null : value,
      ),
      _ => throw ArgumentError.value(field, 'field'),
    };

/// Keeps the popup clear of the caret line, including the on-screen keyboard.
Rect autocompletePopupRect(Rect caret, Size viewport, Size desired) {
  const gap = 4.0;
  final top = caret.top.clamp(0.0, viewport.height);
  final bottom = caret.bottom.clamp(0.0, viewport.height);
  final below = math.max(0.0, viewport.height - bottom - gap);
  final above = math.max(0.0, top - gap);
  final useBelow = below >= desired.height || below >= above;
  final height = math.min(desired.height, useBelow ? below : above);
  final width = math.min(desired.width, viewport.width);
  return Rect.fromLTWH(
    caret.left.clamp(0.0, math.max(0.0, viewport.width - width)),
    useBelow ? bottom + gap : top - gap - height,
    width,
    height,
  );
}
