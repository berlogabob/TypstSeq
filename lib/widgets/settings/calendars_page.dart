import 'package:flutter/material.dart';
import '../app_icons.dart';
import '../../calendar_feeds.dart' show isValidFeedUrl;
import '../date_format.dart' show shortStamp;
import '../settings_sheet.dart';
import 'settings_page.dart';

class CalendarsPage extends StatefulWidget {
  const CalendarsPage({super.key, required this.settings});
  final SettingsSheet settings;
  @override
  State<CalendarsPage> createState() => _CalendarsPageState();
}

class _CalendarsPageState extends State<CalendarsPage> {
  late final feeds = [
    for (final feed
        in (widget.settings.calendarSettings['feeds'] as List? ?? const []))
      if (feed is Map) Map<String, dynamic>.from(feed),
  ];
  Map<String, dynamic> get cache =>
      (widget.settings.calendarSettings['cache'] as Map?)
          ?.cast<String, dynamic>() ??
      const {};

  @override
  Widget build(BuildContext context) => SettingsPage(
    title: 'Calendars',
    children: [
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(onPressed: _done, child: const Text('Done')),
      ),
      if (feeds.isEmpty) const ListTile(title: Text('No calendars configured')),
      for (final (index, feed) in feeds.indexed)
        ListTile(
          leading: const Icon(AppIcons.calendars),
          title: Text(feed['name']?.toString() ?? ''),
          subtitle: Text(_status(feed)),
          trailing: IconButton(
            icon: const Icon(AppIcons.delete),
            onPressed: () => setState(() => feeds.removeAt(index)),
          ),
          onTap: () => _edit(index),
        ),
      PopupMenuButton<String>(
        onSelected: _add,
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'google', child: Text('Google Calendar')),
          PopupMenuItem(value: 'outlook', child: Text('Microsoft Outlook')),
          PopupMenuItem(value: 'iade', child: Text('IADE')),
          PopupMenuItem(value: 'other', child: Text('Other (ICS link)')),
        ],
        child: const Chip(avatar: Icon(Icons.add), label: Text('Add calendar')),
      ),
    ],
  );

  String _status(Map<String, dynamic> feed) {
    final value = cache[feed['id']];
    if (value is Map && value['error'] != null) {
      return 'Error: ${value['error']}';
    }
    final fetched = value is Map ? value['fetched'] : null;
    return '${feed['kind'] == 'iade-timetable' ? 'IADE timetable' : 'ICS'} · ${fetched == null ? 'Not refreshed' : 'Refreshed ${shortStamp('$fetched')}'}';
  }

  Future<void> _add(String kind) async {
    if (kind == 'iade') {
      final choices = await showDialog<List<Map<String, dynamic>>>(
        context: context,
        builder: (_) => const _IadeCalendarDialog(),
      );
      if (choices != null) {
        setState(() => feeds.addAll(choices));
      }
      return;
    }
    final feed = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _CalendarEditor(preset: kind),
    );
    if (feed != null) setState(() => feeds.add(feed));
  }

  Future<void> _edit(int index) async {
    final feed = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _CalendarEditor(feed: feeds[index]),
    );
    if (feed != null) setState(() => feeds[index] = feed);
  }

  Future<void> _done() async {
    await widget.settings.onConfigureCalendars?.call({'feeds': feeds});
    if (mounted) Navigator.pop(context);
  }
}

class _CalendarEditor extends StatefulWidget {
  const _CalendarEditor({this.feed, this.preset = 'other'});
  final Map<String, dynamic>? feed;
  final String preset;
  @override
  State<_CalendarEditor> createState() => _CalendarEditorState();
}

class _CalendarEditorState extends State<_CalendarEditor> {
  late final name = TextEditingController(
    text: widget.feed?['name']?.toString() ?? '',
  );
  late final url = TextEditingController(
    text: widget.feed?['url']?.toString() ?? '',
  );
  late final hours = TextEditingController(
    text: '${widget.feed?['hours'] ?? 6}',
  );
  @override
  void initState() {
    super.initState();
    if (widget.preset == 'google') name.text = 'Google Calendar';
    if (widget.preset == 'outlook') name.text = 'Microsoft Outlook';
  }

  @override
  void dispose() {
    name.dispose();
    url.dispose();
    hours.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.feed == null ? 'Add calendar' : 'Edit calendar'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          TextField(
            controller: url,
            decoration: InputDecoration(
              labelText: 'ICS URL',
              helperText: widget.preset == 'google'
                  ? 'Google Calendar > Settings > your calendar > Integrate calendar > Secret address in iCal format'
                  : widget.preset == 'outlook'
                  ? 'Outlook on the web > Settings > Calendar > Shared calendars > Publish a calendar > ICS link'
                  : null,
            ),
          ),
          TextField(
            controller: hours,
            decoration: const InputDecoration(labelText: 'Refresh hours'),
            keyboardType: TextInputType.number,
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          final refreshHours = int.tryParse(hours.text.trim());
          if (name.text.trim().isEmpty ||
              !isValidFeedUrl(url.text.trim()) ||
              refreshHours == null ||
              refreshHours < 1) {
            return;
          }
          Navigator.pop(context, {
            ...?widget.feed,
            'id':
                widget.feed?['id'] ??
                'calendar-${DateTime.now().microsecondsSinceEpoch}',
            'kind': 'ics',
            'name': name.text.trim(),
            'url': url.text.trim(),
            'hours': refreshHours,
          });
        },
        child: const Text('Save'),
      ),
    ],
  );
}

class _IadeCalendarDialog extends StatefulWidget {
  const _IadeCalendarDialog();
  @override
  State<_IadeCalendarDialog> createState() => _IadeCalendarDialogState();
}

class _IadeCalendarDialogState extends State<_IadeCalendarDialog> {
  bool classes = true, lab = true;
  final group = TextEditingController(),
      programme = TextEditingController(),
      degree = TextEditingController();
  @override
  void dispose() {
    group.dispose();
    programme.dispose();
    degree.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('IADE calendars'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CheckboxListTile(
            value: classes,
            onChanged: (v) => setState(() => classes = v ?? false),
            title: const Text('My classes'),
            contentPadding: EdgeInsets.zero,
          ),
          if (classes) ...[
            TextField(
              controller: group,
              decoration: const InputDecoration(labelText: 'Group'),
            ),
            TextField(
              controller: programme,
              decoration: const InputDecoration(
                labelText: 'Programme (optional)',
              ),
            ),
            TextField(
              controller: degree,
              decoration: const InputDecoration(labelText: 'Degree (optional)'),
            ),
          ],
          CheckboxListTile(
            value: lab,
            onChanged: (v) => setState(() => lab = v ?? false),
            title: const Text('Lab schedule'),
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, [
          if (classes)
            {
              'id': 'classes-${DateTime.now().microsecondsSinceEpoch}',
              'kind': 'iade-timetable',
              'name': 'IADE classes',
              'url': 'https://berlogabob.github.io/iade-lab-schedule/all.json',
              'hours': 6,
              'group': group.text.trim(),
              'programme': programme.text.trim(),
              'degree': degree.text.trim(),
            },
          if (lab)
            {
              'id': 'lab-${DateTime.now().microsecondsSinceEpoch}',
              'kind': 'ics',
              'name': 'IADE lab schedule',
              'url':
                  'https://berlogabob.github.io/openlabtwin/calendar/lab.ics',
              'hours': 6,
            },
        ]),
        child: const Text('Save'),
      ),
    ],
  );
}
