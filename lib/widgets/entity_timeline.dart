import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:tylog_core/tylog_core.dart';

import 'constants.dart';

class EntityTimeline extends StatefulWidget {
  const EntityTimeline({
    super.key,
    required this.entity,
    required this.index,
    required this.onOpenPath,
  });

  final NoteRef entity;
  final VaultIndex index;
  final ValueChanged<String> onOpenPath;

  @override
  State<EntityTimeline> createState() => _EntityTimelineState();
}

class _EntityTimelineState extends State<EntityTimeline> {
  int _limit = 20;
  bool _expanded = true;
  List<({String day, String title, String path, String kind})>? _entries;

  @override
  void didUpdateWidget(EntityTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entity.path != widget.entity.path) _limit = 20;
    if (oldWidget.entity.path != widget.entity.path ||
        !identical(oldWidget.index, widget.index)) {
      _entries = null;
    }
  }

  List<({String day, String title, String path, String kind})> _buildEntries() {
    final index = widget.index;
    final resolver = LinkResolver(index.notesByPath.values);
    final entries = <({String day, String title, String path, String kind})>[];
    String day(String? value, NoteRef? note) {
      final date =
          value ?? (note == null ? null : dailyDayOf(note) ?? note.date);
      if (date != null && RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(date)) {
        return date.substring(0, 10);
      }
      if (note?.modifiedMillis case final millis?) {
        return DateTime.fromMillisecondsSinceEpoch(
          millis,
        ).toIso8601String().substring(0, 10);
      }
      return '';
    }

    for (final path
        in index.backlinksByTarget[widget.entity.path] ?? const <String>[]) {
      final note = index.notesByPath[path];
      if (note != null && path != widget.entity.path) {
        entries.add((
          day: day(null, note),
          title: note.title,
          path: path,
          kind: note.kind,
        ));
      }
    }
    for (final task in index.tasks) {
      final linked =
          task.assignees.any(
            (target) => resolver.resolve(target).path == widget.entity.path,
          ) ||
          RegExp(
                r'(?:#tylog\.ref-note\(\s*["\x27]([^"\x27]+)["\x27]|\[\[([^\]]+)\]\])',
              )
              .allMatches(task.text)
              .any(
                (m) =>
                    resolver.resolve(m[1] ?? m[2]!).path == widget.entity.path,
              );
      if (linked) {
        entries.add((
          day: day(
            task.scheduled ?? task.due,
            index.notesByPath[task.notePath],
          ),
          title: task.text,
          path: task.notePath,
          kind: 'task',
        ));
      }
    }
    entries.sort((a, b) {
      final byDay = b.day.compareTo(a.day);
      return byDay != 0 ? byDay : a.title.compareTo(b.title);
    });
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final entries = _expanded ? (_entries ??= _buildEntries()) : _entries;
    final count = math.min(_limit, entries?.length ?? 0);
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Divider(height: 1),
          ListTile(
            dense: true,
            title: Text(
              entries == null ? 'Timeline' : 'Timeline (${entries.length})',
            ),
            trailing: Icon(_expanded ? Icons.expand_more : Icons.chevron_right),
            onTap: () => setState(() => _expanded = !_expanded),
          ),
          if (_expanded && entries != null)
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.35,
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: count + (count < entries.length ? 1 : 0),
                itemBuilder: (context, i) {
                  if (i == count) {
                    return TextButton(
                      onPressed: () => setState(() => _limit += 20),
                      child: const Text('Show more'),
                    );
                  }
                  final entry = entries[i];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (i == 0 || entries[i - 1].day != entry.day)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            kSpace16,
                            kSpace8,
                            kSpace16,
                            0,
                          ),
                          child: Text(
                            entry.day.isEmpty ? 'Undated' : entry.day,
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ),
                      ListTile(
                        dense: true,
                        leading: Icon(iconForKind(entry.kind), size: 18),
                        title: Text(
                          entry.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => widget.onOpenPath(entry.path),
                      ),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
