import 'package:tylog_core/tylog_core.dart';
import 'package:tylog_core/namespace_plan.dart';
import 'package:tylog_core/values.dart';

export 'package:tylog_core/namespace_plan.dart' show NamespacePlan;

import 'vault.dart';

NamespacePlan namespacePlan(Iterable<NoteRef> notes, {String? noteId}) {
  final candidates = notes.where(
    (n) => n.kind == 'note' || entityNoteKinds.contains(n.kind),
  );
  final pages = [
    for (final n in candidates) NamespacePage(n.id, n.title, n.aliases),
  ];
  final plan = planNamespaces([
    if (noteId != null) ...pages.where((p) => p.id == noteId),
    ...pages.where((p) => p.id != noteId),
  ]);
  if (noteId == null) return plan;
  final target = plan.changes.where((c) => c.existingId == noteId).toList();
  if (target.isEmpty) {
    final titles = pages.where((p) => p.id == noteId).map((p) => p.title);
    return NamespacePlan([], plan.skipped.where(titles.contains).toList());
  }
  final path = target.single.fullPath.toLowerCase();
  return NamespacePlan(
    plan.changes.where((c) {
      final ancestor = c.fullPath.toLowerCase();
      return path == ancestor || path.startsWith('$ancestor/');
    }).toList(),
    [],
  );
}

// Only replace the two scalar/list header fields; leave all other Typst intact.
String namespaceHeader(
  String source,
  NoteRef note,
  NamespaceChange change,
  String? parent,
) {
  final aliases = {
    ...note.aliases,
    if (note.title.contains('/')) note.title,
    if (change.fullPath.contains('/')) change.fullPath,
  };
  var updated = replaceNoteFields(source, {
    'title': typstString(change.newTitle),
    'aliases': '(${aliases.map(typstString).map((s) => '$s,').join(' ')})',
  });
  if (parent != null) {
    updated = replaceNotePartOf(updated, NoteMetadataDraft.fromNote(note), [
      ...note.partOf,
      parent,
    ]);
  }
  return updated;
}

Future<void> applyNamespacePlan(
  Vault vault,
  List<NoteRef> notes,
  NamespacePlan plan, {
  required Future<bool> Function(String, String Function(String)) mutate,
}) async {
  final byId = {for (final note in notes) note.id: note};
  final ids = {for (final note in notes) note.id};
  final paths = <String, String>{};
  final plannedIds = <String, String>{
    for (final change in plan.changes)
      change.fullPath.toLowerCase():
          change.existingId ?? 'namespace:${change.fullPath.toLowerCase()}',
  };
  final names = <String, String>{
    for (final note in notes) note.id.toLowerCase(): note.id,
    for (final note in notes) note.title.toLowerCase(): note.id,
    for (final note in notes)
      for (final alias in note.aliases) alias.toLowerCase(): note.id,
  };
  final edges = <String, Set<String>>{
    for (final note in notes)
      note.id: {
        for (final parent in note.partOf) names[parent.toLowerCase()] ?? parent,
      },
  };
  bool reaches(String from, String target, Set<String> seen) {
    if (from == target) return true;
    if (!seen.add(from)) return false;
    return (edges[from] ?? {}).any((p) => reaches(p, target, seen));
  }

  for (final change in plan.changes) {
    if (change.parentPath == null) continue;
    final child = plannedIds[change.fullPath.toLowerCase()]!;
    final parent = plannedIds[change.parentPath!.toLowerCase()];
    if (parent == null || reaches(parent, child, {})) {
      throw StateError('Invalid namespace parent for ${change.fullPath}');
    }
    (edges[child] ??= {}).add(parent);
  }
  for (final change in plan.changes) {
    final note = byId[change.existingId];
    if (note != null &&
        (note.title != change.newTitle || change.parentPath != null)) {
      namespaceHeader(
        await vault.storage.readText(note.path),
        note,
        change,
        change.parentPath == null ? null : 'preflight',
      );
    }
  }
  for (final change in plan.changes) {
    final parent = change.parentPath == null
        ? null
        : paths[change.parentPath!.toLowerCase()];
    if (change.parentPath != null && parent == null) {
      throw StateError('Missing parent ${change.parentPath}');
    }
    var id = change.existingId;
    if (id == null) {
      id = await vault.nextNoteId(change.fullPath, knownIds: ids);
      ids.add(id);
      var path =
          'notes/${change.newTitle.replaceAll(RegExp(r'[\\\\/]'), '-')}.typ';
      var suffix = 2;
      while (await vault.storage.exists(path)) {
        path =
            'notes/${change.newTitle.replaceAll(RegExp(r'[\\\\/]'), '-')} (${suffix++}).typ';
      }
      await vault.page(
        change.newTitle,
        eventPath: path,
        metadata: NoteMetadataDraft(
          id: id,
          title: change.newTitle,
          aliases: [if (change.fullPath.contains('/')) change.fullPath],
          properties: {
            if (parent != null) 'part_of': [parent],
          },
        ),
      );
    } else {
      final note = byId[id];
      if (note != null &&
          note.title == change.newTitle &&
          change.parentPath == null) {
        paths[change.fullPath.toLowerCase()] = id;
        continue;
      }
      if (note == null ||
          !await mutate(
            note.path,
            (source) => namespaceHeader(source, note, change, parent),
          )) {
        throw StateError('Could not migrate ${change.fullPath}');
      }
    }
    paths[change.fullPath.toLowerCase()] = id;
  }
}
