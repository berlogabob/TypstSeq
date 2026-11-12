import 'package:material_ui/material_ui.dart';

import '../models.dart';
import 'constants.dart';

/// Parent chips and the reverse, grouped view of an entity's children.
class EntityRelationships extends StatefulWidget {
  const EntityRelationships({
    super.key,
    required this.note,
    required this.index,
    required this.onAdd,
    required this.onRemove,
    required this.onOpen,
  });

  final NoteRef note;
  final VaultIndex? index;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;
  final ValueChanged<String> onOpen;

  @override
  State<EntityRelationships> createState() => _EntityRelationshipsState();
}

class _EntityRelationshipsState extends State<EntityRelationships> {
  Map<String, NoteRef> _byId = {};
  Map<String, NoteRef> _byName = {};
  Map<String, List<NoteRef>> _children = {};

  @override
  void initState() {
    super.initState();
    _indexNotes();
  }

  @override
  void didUpdateWidget(EntityRelationships oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.index, widget.index)) _indexNotes();
  }

  void _indexNotes() {
    final notes = widget.index?.notes ?? const <NoteRef>[];
    _byId = {for (final item in notes) item.id: item};
    _byName = {};
    for (final item in notes) {
      for (final name in [item.title, ...item.aliases]) {
        _byName.putIfAbsent(name.toLowerCase(), () => item);
      }
    }
    _children = childrenByParent(notes);
  }

  @override
  Widget build(BuildContext context) {
    final note = widget.note;
    final children = _children[note.id] ?? const <NoteRef>[];
    final groups = <String, List<NoteRef>>{};
    for (final child in children) {
      (groups[child.kind] ??= []).add(child);
    }
    final kinds = groups.keys.toList()..sort();
    return Wrap(
      spacing: kSpace8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text('Part of'),
        for (final parentId in note.partOf)
          Builder(
            builder: (context) {
              final parent = _byId[parentId] ?? _byName[parentId.toLowerCase()];
              return InputChip(
                avatar: Icon(iconForKind(parent?.kind ?? 'note'), size: 18),
                label: Text(
                  parent?.title ?? parentId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                deleteIcon: const Icon(Icons.close, size: 18),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onPressed: parent == null
                    ? null
                    : () => widget.onOpen(parent.path),
                onDeleted: () => widget.onRemove(parentId),
              );
            },
          ),
        IconButton(
          tooltip: 'Add parent',
          visualDensity: VisualDensity.compact,
          onPressed: widget.onAdd,
          icon: const Icon(Icons.add),
        ),
        ActionChip(
          label: Text('Contains ${children.length}'),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            builder: (sheetContext) => SafeArea(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final kind in kinds) ...[
                    ListTile(
                      dense: true,
                      leading: Icon(iconForKind(kind), size: 18),
                      title: Text(
                        '${labelForKind(kind) == 'Entity' ? kind : labelForKind(kind)} (${groups[kind]!.length})',
                      ),
                    ),
                    for (final child in groups[kind]!)
                      ListTile(
                        dense: true,
                        title: Text(child.title),
                        onTap: () {
                          Navigator.pop(sheetContext);
                          widget.onOpen(child.path);
                        },
                      ),
                  ],
                  if (children.isEmpty)
                    const ListTile(title: Text('No children')),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
