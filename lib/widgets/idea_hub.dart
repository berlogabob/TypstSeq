import 'package:flutter/material.dart';
import 'constants.dart';
import '../models.dart';
import '../scanner.dart';
import 'property_select_chip.dart';

const ideaStatuses = ['new', 'approved', 'archived'];
const ideaStatusLabels = {
  'new': 'New',
  'approved': 'Approved',
  'archived': 'Archived',
};

String setIdeaKind(String path, String source, bool enabled) {
  final note = scanNote(path, source);
  final properties = {...note.properties};
  if (enabled) properties['status'] = 'new';
  return replaceNoteHeader(
    source,
    NoteMetadataDraft.fromNote(
      note.copyWith(kind: enabled ? 'idea' : 'note', properties: properties),
    ),
  );
}

List<String> ideaHistoryOnDay(String source, String day) {
  var inHistory = false;
  final entries = <String>[];
  for (final line in source.split('\n')) {
    final heading = RegExp(r'^\s*(=+|#+)\s+(.+?)\s*$').firstMatch(line);
    if (heading != null) {
      inHistory = heading[2] == 'History';
      continue;
    }
    if (!inHistory) continue;
    final entry = RegExp(
      r'^\s*- (\d{4}-\d{2}-\d{2}):\s*(.+?)\s*$',
    ).firstMatch(line.replaceAll(r'\-', '-'));
    if (entry != null && entry[1] == day) entries.add(entry[2]!);
  }
  return entries;
}

class IdeaProperties extends StatelessWidget {
  const IdeaProperties({
    super.key,
    required this.note,
    required this.onToggle,
    required this.onStatus,
  });
  final NoteRef note;
  final ValueChanged<bool> onToggle;
  final ValueChanged<String> onStatus;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: kSpace8,
    children: [
      FilterChip(
        label: const Text('Idea'),
        avatar: const Icon(Icons.lightbulb_outline),
        selected: note.kind == 'idea',
        onSelected: onToggle,
      ),
      if (note.kind == 'idea')
        PropertySelectChip(
          value: note.properties['status']?.toString() ?? 'new',
          options: ideaStatuses,
          labels: ideaStatusLabels,
          onChanged: onStatus,
          tooltip: 'Change idea status',
        ),
    ],
  );
}

class IdeaHubStrip extends StatefulWidget {
  const IdeaHubStrip({
    super.key,
    required this.index,
    required this.day,
    required this.readSource,
    required this.onOpenPath,
  });
  final VaultIndex? index;
  final String day;
  final Future<String> Function(String) readSource;
  final ValueChanged<String> onOpenPath;
  @override
  State<IdeaHubStrip> createState() => _IdeaHubStripState();
}

class _IdeaHubStripState extends State<IdeaHubStrip> {
  late Future<List<(NoteRef, String)>> entries = _load();
  Future<List<(NoteRef, String)>> _load() async {
    final result = <(NoteRef, String)>[];
    for (final note in widget.index?.notes ?? const <NoteRef>[]) {
      if (note.kind != 'idea') continue;
      try {
        final source = await widget.readSource(note.path);
        for (final text in ideaHistoryOnDay(source, widget.day)) {
          result.add((note, text));
        }
      } catch (_) {
        // A note removed during sync should not hide the other idea events.
      }
    }
    return result;
  }

  @override
  void didUpdateWidget(IdeaHubStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index || oldWidget.day != widget.day) {
      entries = _load();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: entries,
    builder: (context, snapshot) {
      final rows = snapshot.data ?? const <(NoteRef, String)>[];
      if (rows.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(kSpace8),
            child: Text('Idea hub (${rows.length})'),
          ),
          SizedBox(
            height: 88,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final (note, text) in rows)
                  SizedBox(
                    width: 240,
                    child: ListTile(
                      leading: const Icon(Icons.lightbulb_outline),
                      title: Text(
                        note.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => widget.onOpenPath(note.path),
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    },
  );
}
