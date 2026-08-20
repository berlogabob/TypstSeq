import 'package:flutter/material.dart';
import 'package:tylog_core/models.dart';

import 'constants.dart';

/// Bottom-sheet note picker with a filter field. The magic-menu choosers used
/// to render every note in the vault as one unsearchable ListView — unusable
/// at a few thousand notes. Returns the chosen [NoteRef], or
/// [NotePickerSheet.createSentinel] when the create row is tapped.
class NotePickerSheet extends StatefulWidget {
  const NotePickerSheet({
    super.key,
    required this.notes,
    this.heading,
    this.createLabel,
    this.subtitleFor = _idSubtitle,
  });

  static const createSentinel = 'create';

  final List<NoteRef> notes;
  final String? heading;

  /// Label for the create row; null hides it.
  final String? createLabel;
  final String Function(NoteRef) subtitleFor;

  static String _idSubtitle(NoteRef note) => note.id;

  @override
  State<NotePickerSheet> createState() => _NotePickerSheetState();
}

class _NotePickerSheetState extends State<NotePickerSheet> {
  var _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    bool matches(NoteRef note) =>
        q.isEmpty ||
        note.title.toLowerCase().contains(q) ||
        note.id.toLowerCase().contains(q) ||
        note.aliases.any((alias) => alias.toLowerCase().contains(q));
    final filtered = [
      for (final note in widget.notes)
        if (matches(note)) note,
    ];
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.heading != null)
            ListTile(
              title: Text(widget.heading!),
              subtitle: const Text('Dismiss to use no filter'),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              autofocus: false,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Filter notes',
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                if (widget.createLabel != null)
                  ListTile(
                    leading: const Icon(Icons.add),
                    title: Text(widget.createLabel!),
                    onTap: () =>
                        Navigator.pop(context, NotePickerSheet.createSentinel),
                  ),
                for (final item in filtered)
                  ListTile(
                    leading: Icon(iconForKind(item.kind)),
                    title: Text(item.title),
                    subtitle: Text(widget.subtitleFor(item)),
                    onTap: () => Navigator.pop(context, item),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
