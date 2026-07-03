import 'dart:io';

import 'models.dart';

// ponytail: regex scanner, replace with Typst metadata query when syntax coverage hurts real notes.
final _wikilink = RegExp(r'#wikilink\(\s*"([^"]+)"');
final _tag = RegExp(r'#tag\(\s*"([^"]+)"\s*\)');
final _title = RegExp(r'title:\s*"([^"]+)"');
final _date = RegExp(r'date:\s*"([^"]+)"');
final _id = RegExp(r'id:\s*"([^"]+)"');
final _quoted = RegExp(r'"([^"]+)"');

enum LinkResolutionStatus { resolved, unresolved, ambiguous }

class LinkResolution {
  const LinkResolution({required this.target, required this.status, this.path});

  final String target;
  final LinkResolutionStatus status;
  final String? path;
}

NoteRef scanNote(String relativePath, String source) {
  final stem = relativePath.split('/').last.replaceFirst(RegExp(r'\.typ$'), '');
  final tags = <String>{
    ..._parseList(source, 'tags'),
    ..._tag.allMatches(source).map((m) => m.group(1)!),
  }.toList()..sort();
  final links = <String>{
    ..._parseList(source, 'links'),
    ..._wikilink.allMatches(source).map((m) => m.group(1)!),
  }.toList()..sort();
  final aliases = [..._parseList(source, 'aliases')]..sort();
  final fileRefs = [..._parseList(source, 'files')]..sort();
  return NoteRef(
    id: _id.firstMatch(source)?.group(1) ?? stem,
    path: relativePath,
    title: _title.firstMatch(source)?.group(1) ?? stem,
    date: _date.firstMatch(source)?.group(1),
    tags: tags,
    aliases: aliases,
    outgoingLinks: links,
    fileRefs: fileRefs,
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
  final backlinks = <String, Set<String>>{};
  final index = VaultIndex(notesByPath: notes, backlinksByTarget: const {});
  for (final source in notes.values) {
    for (final target in source.outgoingLinks) {
      final resolved = resolveLink(index, target);
      if (resolved.status == LinkResolutionStatus.resolved &&
          resolved.path != null) {
        backlinks
            .putIfAbsent(resolved.path!, () => <String>{})
            .add(source.path);
      }
    }
  }
  return {for (final e in backlinks.entries) e.key: (e.value.toList()..sort())};
}

String? resolveLinkPath(VaultIndex index, String title) {
  final resolved = resolveLink(index, title);
  return resolved.status == LinkResolutionStatus.resolved
      ? resolved.path
      : null;
}

LinkResolution resolveLink(VaultIndex index, String target) {
  final lookup = _buildLookup(index.notes);
  final byId = lookup['id']![target];
  if (byId != null) return _resolveCandidates(target, byId);
  final byAlias = lookup['alias']![target];
  if (byAlias != null) return _resolveCandidates(target, byAlias);
  final byTitle = lookup['title']![target];
  if (byTitle != null) return _resolveCandidates(target, byTitle);
  final byStem = lookup['stem']![target];
  if (byStem != null) return _resolveCandidates(target, byStem);
  return LinkResolution(
    target: target,
    status: LinkResolutionStatus.unresolved,
  );
}

LinkResolution _resolveCandidates(String target, Set<String> candidates) {
  if (candidates.length == 1) {
    return LinkResolution(
      target: target,
      status: LinkResolutionStatus.resolved,
      path: candidates.first,
    );
  }
  return LinkResolution(target: target, status: LinkResolutionStatus.ambiguous);
}

Map<String, Map<String, Set<String>>> _buildLookup(List<NoteRef> notes) {
  final lookup = {
    'id': <String, Set<String>>{},
    'alias': <String, Set<String>>{},
    'title': <String, Set<String>>{},
    'stem': <String, Set<String>>{},
  };
  for (final note in notes) {
    _addLookup(lookup['id']!, note.id, note.path);
    _addLookup(lookup['title']!, note.title, note.path);
    final stem = note.path.split('/').last.replaceFirst(RegExp(r'\.typ$'), '');
    _addLookup(lookup['stem']!, stem, note.path);
    for (final alias in note.aliases) {
      _addLookup(lookup['alias']!, alias, note.path);
    }
  }
  return lookup;
}

void _addLookup(Map<String, Set<String>> map, String key, String path) {
  map.putIfAbsent(key, () => <String>{}).add(path);
}

List<String> _parseList(String source, String field) {
  final match = RegExp(
    '$field\\s*:\\s*\\(([^)]*)\\)',
    dotAll: true,
  ).firstMatch(source);
  if (match == null) return const [];
  return _quoted
      .allMatches(match.group(1)!)
      .map((m) => m.group(1)!)
      .toSet()
      .toList();
}

String _relativePath(Directory root, File file) {
  final rootPath = root.absolute.path.endsWith(Platform.pathSeparator)
      ? root.absolute.path
      : '${root.absolute.path}${Platform.pathSeparator}';
  return file.absolute.path
      .substring(rootPath.length)
      .replaceAll(Platform.pathSeparator, '/');
}
