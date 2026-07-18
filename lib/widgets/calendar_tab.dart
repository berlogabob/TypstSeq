import 'package:flutter/material.dart';

import '../models.dart';
import '../month_calendar.dart';
import 'date_format.dart';

class CalendarTab extends StatefulWidget {
  const CalendarTab({
    super.key,
    required this.index,
    required this.onOpenPath,
    required this.onOpenDay,
  });

  final VaultIndex? index;
  final ValueChanged<String> onOpenPath;
  final ValueChanged<DateTime> onOpenDay;

  @override
  State<CalendarTab> createState() => _CalendarTabState();
}

class _CalendarTabState extends State<CalendarTab> {
  DateTime selected = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final iso = isoDay(selected);
    final items = (widget.index?.calendar ?? const <CalendarItem>[])
        .where((item) => item.date == iso)
        .toList();
    const headerCount = 3;
    final itemCount = headerCount + (items.isEmpty ? 1 : items.length);
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      itemCount: itemCount,
      itemBuilder: (context, i) {
        switch (i) {
          case 0:
            return MonthCalendar(
              index: widget.index,
              initialMonth: selected,
              onDaySelected: (day) => setState(() => selected = day),
              onOpenDay: widget.onOpenDay,
            );
          case 1:
            return const Divider();
          case 2:
            return ListTile(
              leading: const Icon(Icons.edit_note),
              title: Text('Open journal $iso'),
              onTap: () => widget.onOpenDay(selected),
            );
          default:
            if (items.isEmpty) {
              return const ListTile(title: Text('Nothing on this day yet'));
            }
            final item = items[i - headerCount];
            return ListTile(
              leading: Icon(switch (item.kind) {
                CalendarItemKind.daily => Icons.book_outlined,
                CalendarItemKind.task => Icons.task_alt,
                _ => Icons.event,
              }),
              title: Text(item.title),
              onTap: () => widget.onOpenPath(item.notePath),
            );
        }
      },
    );
  }
}
