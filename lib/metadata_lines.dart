import 'package:tylog_core/tylog_core.dart';

/// A note's editable metadata as Logseq-style `key:: value` lines: aliases,
/// tags (without the derived kind tag), parents by title, then every text
/// property. One editing language for the header, the Details card and lines
/// typed at the top of a page.
String metadataLines(NoteRef note, Iterable<NoteRef> notes) {
  final titles = {for (final n in notes) n.id: n.title};
  final parents = note.properties['part_of'];
  final parentIds = [
    if (parents is String) parents,
    if (parents is List) ...parents.whereType<String>(),
  ];
  return [
    if (note.aliases.isNotEmpty) 'alias:: ${note.aliases.join(', ')}',
    if (note.tags.any((t) => t != note.kind))
      'tags:: ${note.tags.where((t) => t != note.kind).join(', ')}',
    if (parentIds.isNotEmpty)
      'part of:: ${parentIds.map((id) => titles[id] ?? id).join(', ')}',
    for (final entry in note.properties.entries)
      if (entry.key != 'part_of' && entry.value is String)
        '${entry.key}:: ${entry.value}',
  ].join('\n');
}

/// The header for [note] after editing its [lines]: aliases, tags and parents
/// are replaced by what the lines say; text properties not in the lines are
/// removed; non-text properties (lists, maps) are kept untouched. Parent
/// titles that match a page are stored as its id.
NoteMetadataDraft applyMetadataLines(
  NoteRef note,
  String lines,
  Iterable<NoteRef> notes, {
  String? title,
  String? kind,
}) {
  final ids = <String, String>{};
  for (final n in notes) {
    ids.putIfAbsent(n.title.toLowerCase(), () => n.id);
  }
  List<String> csv(String value) => [
    for (final part in value.split(','))
      if (part.trim().isNotEmpty) part.trim(),
  ];
  final aliases = <String>[];
  final tags = <String>[];
  final parents = <String>[];
  final properties = <String, Object?>{
    for (final entry in note.properties.entries)
      if (entry.key != 'part_of' && entry.value is! String)
        entry.key: entry.value,
  };
  for (final line in lines.split('\n')) {
    final parsed = parsePropertyLine(line);
    if (parsed == null || parsed.value.isEmpty) continue;
    switch (parsed.key) {
      case 'alias' || 'aliases':
        aliases.addAll(csv(parsed.value));
      case 'tags' || 'tag':
        tags.addAll(csv(parsed.value));
      case 'part_of':
        parents.addAll(
          csv(parsed.value).map((name) => ids[name.toLowerCase()] ?? name),
        );
      default:
        properties[parsed.key] = parsed.value;
    }
  }
  return NoteMetadataDraft(
    id: note.id,
    title: title ?? note.title,
    kind: kind ?? note.kind,
    project: note.project,
    date: note.date,
    tags: tags,
    aliases: aliases,
    properties: {
      ...properties,
      if (parents.isNotEmpty) 'part_of': parents,
    },
  );
}
