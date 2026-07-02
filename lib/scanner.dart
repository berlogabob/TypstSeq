import 'dart:io';

import 'models.dart';

// ponytail: regex scanner, replace with Typst metadata query when syntax coverage hurts real notes.
final _wikilink = RegExp(r'#wikilink\(\s*"([^"]+)"');
final _tag = RegExp(r'#tag\(\s*"([^"]+)"\s*\)');
final _title = RegExp(r'title:\s*"([^"]+)"');
final _date = RegExp(r'date:\s*"([^"]+)"');

NoteRef scanNote(String relativePath, String source) {
  final stem = relativePath.split('/').last.replaceFirst(RegExp(r'\.typ$'), '');
  return NoteRef(
    path: relativePath,
    title: _title.firstMatch(source)?.group(1) ?? stem,
    date: _date.firstMatch(source)?.group(1),
    tags: _tag.allMatches(source).map((m) => m.group(1)!).toSet().toList()
      ..sort(),
    outgoingLinks:
        _wikilink.allMatches(source).map((m) => m.group(1)!).toSet().toList()
          ..sort(),
  );
}

Future<VaultIndex> scanVault(Directory root) async {
  final notes = <String, NoteRef>{};
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is! File || !entity.path.endsWith('.typ')) continue;
    final relative = _relativePath(root, entity);
    if (relative.startsWith('.tylog/')) continue;
    notes[relative] = scanNote(relative, await entity.readAsString());
  }
  return VaultIndex(notesByPath: notes, backlinksByTarget: _backlinks(notes));
}

Map<String, List<String>> _backlinks(Map<String, NoteRef> notes) {
  final byTitle = <String, String>{};
  for (final note in notes.values) {
    byTitle[note.title] = note.path;
    byTitle[note.path.split('/').last.replaceFirst(RegExp(r'\.typ$'), '')] =
        note.path;
  }

  final backlinks = <String, Set<String>>{};
  for (final source in notes.values) {
    for (final target in source.outgoingLinks) {
      final targetPath = byTitle[target] ?? target;
      backlinks.putIfAbsent(targetPath, () => <String>{}).add(source.path);
    }
  }
  return {for (final e in backlinks.entries) e.key: (e.value.toList()..sort())};
}

String? resolveLinkPath(VaultIndex index, String title) {
  final notes = index.notes;
  for (final note in notes) {
    if (note.title == title) return note.path;
  }
  for (final note in notes) {
    final stem = note.path.split('/').last.replaceFirst(RegExp(r'\.typ$'), '');
    if (stem == title) return note.path;
  }
  for (final note in notes) {
    if (note.aliases.contains(title)) return note.path;
  }
  return null;
}

String _relativePath(Directory root, File file) {
  final rootPath = root.absolute.path.endsWith(Platform.pathSeparator)
      ? root.absolute.path
      : '${root.absolute.path}${Platform.pathSeparator}';
  return file.absolute.path
      .substring(rootPath.length)
      .replaceAll(Platform.pathSeparator, '/');
}
