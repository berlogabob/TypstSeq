import 'dart:async';
import 'package:flutter/material.dart';
import 'constants.dart';
import '../models.dart';
import 'task_clock.dart';

class TaskChipStrip extends StatefulWidget {
  const TaskChipStrip({
    super.key,
    required this.task,
    required this.onCommand,
    this.showEmpty = false,
  });
  final TaskRef task;
  final bool showEmpty;
  final ValueChanged<String> onCommand;
  @override
  State<TaskChipStrip> createState() => _TaskChipStripState();
}

class _TaskChipStripState extends State<TaskChipStrip> {
  Timer? _ticker;
  late TaskRef _task;

  void _updateTask() {
    _task = widget.task;
    _ticker?.cancel();
    if (_task.status == 'doing' && _task.runningClock != null) {
      _ticker = Timer.periodic(
        const Duration(seconds: 1),
        (_) => setState(() {}),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _updateTask();
  }

  @override
  void didUpdateWidget(TaskChipStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task != widget.task) _updateTask();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _date(String value, DateTime now) {
    final date = DateTime.tryParse(value);
    if (date == null) return value;
    final day = DateTime(date.year, date.month, date.day);
    final today = DateTime(now.year, now.month, now.day);
    if (day == today) return 'Today';
    if (day == DateTime(now.year, now.month, now.day + 1)) return 'Tomorrow';
    if (day.isAfter(today) &&
        day.isBefore(DateTime(now.year, now.month, now.day + 7))) {
      return const [
        'Mon',
        'Tue',
        'Wed',
        'Thu',
        'Fri',
        'Sat',
        'Sun',
      ][day.weekday - 1];
    }
    return '${day.day} ${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][day.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final scheme = Theme.of(context).colorScheme;
    Widget chip(
      String field,
      String label,
      String tooltip, {
      IconData? icon,
      bool overdue = false,
    }) => Tooltip(
      message: tooltip,
      child: TextFieldTapRegion(
        child: InkWell(
          key: Key('task-chip-${_task.id}-$field'),
          onTap: () => widget.onCommand(field),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: kMinTapTarget,
              minWidth: kMinTapTarget,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: kSpace4),
              child: Center(
                widthFactor: 1,
                heightFactor: 1,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null)
                      Icon(
                        icon,
                        size: 16,
                        color: overdue ? scheme.error : scheme.onSurfaceVariant,
                      ),
                    if (icon != null && label.isNotEmpty)
                      const SizedBox(width: kSpace4),
                    if (label.isNotEmpty)
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          // ponytail: narrow or scaled date labels shorten; the tooltip keeps the full value.
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: overdue
                                    ? scheme.error
                                    : scheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final start = DateTime.tryParse(_task.runningClock?.start ?? '');
    final elapsed = _task.status == 'doing' && start != null
        ? now.difference(start)
        : Duration.zero;
    final total =
        _task.clockedTotal + (elapsed.isNegative ? Duration.zero : elapsed);
    return Wrap(
      spacing: kSpace4,
      runSpacing: kSpace4,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          spacing: kSpace4,
          children: [
            if (widget.showEmpty || _task.priority != 'normal')
              chip(
                'priority',
                _task.priority == 'normal' ? '' : _task.priority,
                'Priority: ${_task.priority}',
                icon: _task.priority == 'normal' ? Icons.flag_outlined : null,
              ),
            for (final (field, date) in [
              ('due', _task.due),
              ('scheduled', _task.scheduled),
            ])
              if (widget.showEmpty || date != null)
                Flexible(
                  child: chip(
                    field,
                    date == null ? '' : _date(date, now),
                    '${field == 'due' ? 'Due' : 'Scheduled'}${date == null ? '' : ': $date'}',
                    icon: field == 'due' ? Icons.event : Icons.schedule,
                    overdue:
                        field == 'due' &&
                        date != null &&
                        (DateTime.tryParse(date)?.isBefore(
                              DateTime(now.year, now.month, now.day),
                            ) ??
                            false),
                  ),
                ),
            if (widget.showEmpty || _task.recurrence != null)
              chip(
                'repeat',
                '↻',
                'Repeat${_task.recurrence == null ? '' : ': ${_task.recurrence}'}',
              ),
          ],
        ),
        if (total > Duration.zero || _task.status == 'doing' && start != null)
          SizedBox(
            key: Key('task-chip-${_task.id}-time'),
            width: 88,
            child: Text(
              timerTime(total),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
      ],
    );
  }
}
