import 'package:flutter/material.dart';

import 'models.dart';

/// Logseq-style month grid: days carrying journal entries or references are
/// marked, tapping any day opens (or creates) that day's journal file.
class MonthCalendar extends StatefulWidget {
  const MonthCalendar({
    super.key,
    required this.index,
    required this.onOpenDay,
    this.initialMonth,
    this.onDaySelected,
  });

  final VaultIndex? index;
  final ValueChanged<DateTime> onOpenDay;
  final DateTime? initialMonth;

  /// When set, tapping a day selects it (calls this) instead of opening it;
  /// the header keeps a direct "open" affordance per day via double tap.
  final ValueChanged<DateTime>? onDaySelected;

  @override
  State<MonthCalendar> createState() => _MonthCalendarState();
}

class _MonthCalendarState extends State<MonthCalendar> {
  late DateTime month;
  DateTime? selected;

  static const _weekdays = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];
  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  @override
  void initState() {
    super.initState();
    final base = widget.initialMonth ?? DateTime.now();
    month = DateTime(base.year, base.month);
  }

  void _page(int delta) =>
      setState(() => month = DateTime(month.year, month.month + delta));

  String _iso(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final marks =
        widget.index?.calendarDayMarks ??
        (daily: const <String>{}, refs: const <String>{});
    final scheme = Theme.of(context).colorScheme;
    final today = DateTime.now();
    final leading = DateTime(month.year, month.month, 1).weekday - 1;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final cells = <Widget>[
      for (var i = 0; i < leading; i++) const SizedBox.shrink(),
      for (var day = 1; day <= daysInMonth; day++)
        _dayCell(DateTime(month.year, month.month, day), marks, scheme, today),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Previous month',
              icon: const Icon(Icons.chevron_left),
              onPressed: () => _page(-1),
            ),
            Expanded(
              child: Text(
                '${_months[month.month - 1]} ${month.year}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              tooltip: 'Next month',
              icon: const Icon(Icons.chevron_right),
              onPressed: () => _page(1),
            ),
          ],
        ),
        Row(
          children: [
            for (final label in _weekdays)
              Expanded(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: cells,
        ),
      ],
    );
  }

  Widget _dayCell(
    DateTime day,
    ({Set<String> daily, Set<String> refs}) marks,
    ColorScheme scheme,
    DateTime today,
  ) {
    final iso = _iso(day);
    final isToday =
        day.year == today.year &&
        day.month == today.month &&
        day.day == today.day;
    final isSelected =
        selected != null &&
        day.year == selected!.year &&
        day.month == selected!.month &&
        day.day == selected!.day;
    final hasDaily = marks.daily.contains(iso);
    final hasRefs = marks.refs.contains(iso);
    return InkWell(
      key: Key('calendar-day-$iso'),
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        if (widget.onDaySelected == null) {
          widget.onOpenDay(day);
        } else {
          setState(() => selected = day);
          widget.onDaySelected!(day);
        }
      },
      onDoubleTap: widget.onDaySelected == null
          ? null
          : () => widget.onOpenDay(day),
      child: Container(
        alignment: Alignment.center,
        decoration: isSelected
            ? BoxDecoration(
                color: scheme.secondaryContainer,
                borderRadius: BorderRadius.circular(8),
              )
            : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: isToday
                  ? BoxDecoration(
                      color: scheme.primaryContainer,
                      shape: BoxShape.circle,
                    )
                  : null,
              child: Text('${day.day}'),
            ),
            SizedBox(
              height: 6,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasDaily) _dot(scheme.primary),
                  if (hasDaily && hasRefs) const SizedBox(width: 2),
                  if (hasRefs) _dot(scheme.tertiary),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dot(Color color) => Container(
    width: 5,
    height: 5,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}
