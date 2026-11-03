import 'package:flutter/material.dart';

import '../connectors/connector.dart';
import '../models.dart';

class ExternalEntityPage extends StatelessWidget {
  const ExternalEntityPage({
    super.key,
    required this.entity,
    required this.notes,
    required this.onOpen,
  });

  final ExternalEntity entity;
  final List<NoteRef> notes;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final children = childrenByParent(notes)[entity.id] ?? const <NoteRef>[];
    final references = notes.where(
      (note) => note.outgoingLinks.contains(entity.id),
    );
    return Scaffold(
      appBar: AppBar(title: Text(entity.title)),
      body: ListView(
        children: [
          const ListTile(
            title: Text('OpenLabTwin'),
            subtitle: Text('Read only'),
          ),
          const ListTile(title: Text('Children')),
          for (final child in children)
            ListTile(title: Text(child.title), onTap: () => onOpen(child.path)),
          const ListTile(title: Text('Linked references')),
          for (final ref in references)
            ListTile(title: Text(ref.title), onTap: () => onOpen(ref.path)),
        ],
      ),
    );
  }
}
