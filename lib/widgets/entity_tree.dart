import 'package:flutter/material.dart';

import '../models.dart';
import 'constants.dart';

class EntityTreeNode {
  const EntityTreeNode(this.note, this.children);
  final NoteRef note;
  final List<EntityTreeNode> children;
}

/// Builds each parent path independently, including otherwise rootless cycles.
List<EntityTreeNode> buildEntityTree(
  Iterable<NoteRef> notes,
  Set<String> matches,
) {
  final all = notes.toList()..sort((a, b) => a.title.compareTo(b.title));
  final children = childrenByParent(all);
  final hasParent = {
    for (final list in children.values)
      for (final n in list) n.id,
  };
  final visited = <String>{};
  EntityTreeNode? build(NoteRef note, Set<String> path) {
    if (path.contains(note.id)) return null;
    visited.add(note.id);
    final next = {...path, note.id};
    final descendants = <EntityTreeNode>[];
    final sorted = [...?children[note.id]]
      ..sort((a, b) => a.title.compareTo(b.title));
    for (final child in sorted) {
      final node = build(child, next);
      if (node != null) descendants.add(node);
    }
    if (!matches.contains(note.path) && descendants.isEmpty) return null;
    return EntityTreeNode(note, descendants);
  }

  final roots = <EntityTreeNode>[];
  for (final note in all.where((n) => !hasParent.contains(n.id))) {
    final node = build(note, {});
    if (node != null) roots.add(node);
  }
  for (final note in all) {
    if (!visited.contains(note.id)) {
      final node = build(note, {});
      if (node != null) roots.add(node);
    }
  }
  return roots;
}

class EntityTree extends StatelessWidget {
  const EntityTree({
    super.key,
    required this.nodes,
    required this.onOpen,
    this.expand = false,
  });
  final List<EntityTreeNode> nodes;
  final ValueChanged<String> onOpen;
  final bool expand;

  Widget _row(EntityTreeNode node) {
    final note = node.note;
    if (node.children.isEmpty) {
      return ListTile(
        leading: Icon(iconForKind(note.kind)),
        title: Text(note.title),
        onTap: () => onOpen(note.path),
      );
    }
    return ExpansionTile(
      key: ValueKey(
        '${note.path}-$expand-${node.children.map((n) => n.note.path).join('|')}',
      ),
      initiallyExpanded: expand,
      leading: Icon(iconForKind(note.kind)),
      title: InkWell(onTap: () => onOpen(note.path), child: Text(note.title)),
      children: [
        for (final child in node.children)
          Padding(padding: const EdgeInsets.only(left: 16), child: _row(child)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) =>
      Column(children: [for (final node in nodes) _row(node)]);
}

class EntityTreeToggle extends StatelessWidget {
  const EntityTreeToggle({
    super.key,
    required this.tree,
    required this.onChanged,
  });
  final bool tree;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => SegmentedButton<bool>(
    segments: const [
      ButtonSegment(value: false, label: Text('List')),
      ButtonSegment(value: true, label: Text('Tree')),
    ],
    selected: {tree},
    onSelectionChanged: (value) => onChanged(value.single),
  );
}
