import 'package:flutter/material.dart';

import '../models.dart';
import 'audio_sheets.dart';

/// Library > Audio: every `kind: audio` note, newest first, plus record/import.
class AudioShelf extends StatelessWidget {
  const AudioShelf({
    super.key,
    required this.notes,
    required this.onOpen,
    required this.onRecord,
    required this.onImport,
  });

  final List<NoteRef> notes;
  final ValueChanged<NoteRef> onOpen;
  final VoidCallback onRecord;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final audio = [
      for (final n in notes)
        if (n.kind == 'audio') n,
    ]..sort((a, b) => b.id.compareTo(a.id)); // ids carry the timestamp
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              FilledButton.icon(
                onPressed: onRecord,
                icon: const Icon(Icons.mic),
                label: const Text('Record'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: onImport,
                icon: const Icon(Icons.audio_file_outlined),
                label: const Text('Import file'),
              ),
            ],
          ),
        ),
        Expanded(
          child: audio.isEmpty
              ? const Center(child: Text('No recordings yet'))
              : ListView.builder(
                  itemCount: audio.length,
                  itemBuilder: (context, i) {
                    final n = audio[i];
                    final ms = n.properties['duration_ms'];
                    return ListTile(
                      leading: const Icon(Icons.graphic_eq),
                      title: Text(n.title),
                      subtitle: ms is int
                          ? Text(formatClock(Duration(milliseconds: ms)))
                          : null,
                      onTap: () => onOpen(n),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
