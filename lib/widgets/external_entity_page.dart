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
    final assets = children.where((note) => note.path.startsWith('olt:asset:'));
    final stock = entity.properties['stock'] as List? ?? const [];
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
          for (final child in children.where(
            (note) => !note.path.startsWith('olt:asset:'),
          ))
            ListTile(title: Text(child.title), onTap: () => onOpen(child.path)),
          if (entity.kind == 'place') ...[
            const ListTile(title: Text('Assets here')),
            for (final asset in assets)
              ListTile(
                title: Text(asset.title),
                subtitle: Text(
                  [
                    asset.properties['item'],
                    asset.properties['condition'],
                    asset.properties['seen'],
                  ].where((v) => v != null && '$v'.isNotEmpty).join(' · '),
                ),
                onTap: () => onOpen(asset.path),
              ),
            const ListTile(title: Text('Stock')),
            for (final row in stock)
              ListTile(
                title: Text('${row['name']}'),
                subtitle: Text(
                  [
                    row['qty'],
                    row['unit'],
                  ].where((v) => v != null && '$v'.isNotEmpty).join(' '),
                ),
              ),
          ],
          const ListTile(title: Text('Linked references')),
          for (final ref in references)
            ListTile(title: Text(ref.title), onTap: () => onOpen(ref.path)),
        ],
      ),
    );
  }
}
