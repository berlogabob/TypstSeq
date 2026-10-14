import 'package:flutter/material.dart';

import '../models.dart';
import 'audio_sheets.dart';
import 'constants.dart';
import 'ds/library_toolbar.dart';
import 'ds/app_empty_state.dart';

/// Library > Audio: every `kind: audio` note, newest first, plus record/import.
class AudioShelf extends StatefulWidget {
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
  State<AudioShelf> createState() => _AudioShelfState();
}

class _AudioShelfState extends State<AudioShelf> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.text.trim().toLowerCase();
    final audio = [
      for (final n in widget.notes)
        if (n.kind == 'audio' &&
            (n.title.toLowerCase().contains(query) ||
                n.aliases.any((alias) => alias.toLowerCase().contains(query))))
          n,
    ]..sort((a, b) => b.id.compareTo(a.id)); // ids carry the timestamp
    return Column(
      children: [
        LibraryToolbar(
          controller: _query,
          searchKey: const Key('audio-search'),
          hintText: 'Search audio',
          onChanged: (_) => setState(() {}),
        ),
        Padding(
          padding: const EdgeInsets.all(kSpace16),
          child: Row(
            children: [
              FilledButton.icon(
                onPressed: widget.onRecord,
                icon: const Icon(Icons.mic, size: kIcon),
                label: const Text('Record'),
              ),
              const SizedBox(width: kSpace8),
              OutlinedButton.icon(
                onPressed: widget.onImport,
                icon: const Icon(Icons.audio_file_outlined, size: kIcon),
                label: const Text('Import file'),
              ),
            ],
          ),
        ),
        Expanded(
          child: audio.isEmpty
              ? AppEmptyState(
                  icon: Icons.graphic_eq,
                  title: query.isEmpty ? 'No recordings yet' : 'Nothing matches',
                  hint: query.isEmpty
                      ? 'Record or import audio to get started.'
                      : 'Try another search.',
                )
              : ListView.builder(
                  itemCount: audio.length,
                  itemBuilder: (context, i) {
                    final n = audio[i];
                    final ms = n.properties['duration_ms'];
                    return ListTile(
                      leading: const Icon(Icons.graphic_eq, size: kIcon),
                      title: Text(
                        n.aliases.isEmpty ? n.title : n.aliases.first,
                      ),
                      subtitle: ms is int
                          ? Text(formatClock(Duration(milliseconds: ms)))
                          : null,
                      onTap: () => widget.onOpen(n),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
