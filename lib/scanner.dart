import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:typst_flutter/typst_flutter.dart';

import 'models.dart';

const tylogHelperSource = '''// tylog-helper-version: 3
#let note(
  id: none,
  title: none,
  date: none,
  tags: (),
  aliases: (),
  links: (),
  files: (),
) = [
  #metadata((
    id: id,
    title: title,
    date: date,
    tags: tags,
    aliases: aliases,
    links: links,
    files: files,
  )) <tylog-note>
]

#let wikilink(target, display: none) = [
  #metadata((target: target, display: display)) <tylog-link>
  #(if display == none { target } else { display })
]

#let tag(name) = [
  #metadata(name) <tylog-tag>
  #name
]

#let filelink(id, display: none) = [
  #metadata(id) <tylog-file>
  #(if display == none { id } else { display })
]
''';

const legacyTylogHelperSource = '''#let note(
  id: none,
  title: none,
  date: none,
  tags: (),
  aliases: (),
  links: (),
  files: (),
) = none

#let wikilink(target, display: none) = {
  if display == none { target } else { display }
}

#let tag(name) = [#name]
''';

final _quoted = RegExp(r'"((?:\\.|[^"\\])*)"');

enum LinkResolutionStatus { resolved, unresolved, ambiguous }

class LinkResolution {
  const LinkResolution({
    required this.target,
    required this.status,
    this.path,
    this.candidates = const [],
  });

  final String target;
  final LinkResolutionStatus status;
  final String? path;
  final List<String> candidates;
}

class LinkResolver {
  LinkResolver(Iterable<NoteRef> notes) {
    for (final note in notes) {
      _add(_ids, note.id, note.path);
      _add(_titles, note.title, note.path);
      _add(
        _stems,
        note.path.split('/').last.replaceFirst(RegExp(r'\.typ$'), ''),
        note.path,
      );
      for (final alias in note.aliases) {
        _add(_aliases, alias, note.path);
      }
    }
  }

  final _ids = <String, Set<String>>{};
  final _aliases = <String, Set<String>>{};
  final _titles = <String, Set<String>>{};
  final _stems = <String, Set<String>>{};

  LinkResolution resolve(String target) {
    for (final map in [_ids, _aliases, _titles, _stems]) {
      final candidates = map[target];
      if (candidates != null) return _resolveCandidates(target, candidates);
    }
    return LinkResolution(
      target: target,
      status: LinkResolutionStatus.unresolved,
    );
  }
}

class TypstCall {
  const TypstCall(this.name, this.start, this.end, this.source);

  final String name;
  final int start;
  final int end;
  final String source;
}

class IndexBuildCancelled implements Exception {
  const IndexBuildCancelled();
}

class NoteMetadataDraft {
  const NoteMetadataDraft({
    required this.id,
    required this.title,
    this.date,
    this.tags = const [],
    this.aliases = const [],
    this.links = const [],
    this.files = const [],
  });

  final String id;
  final String title;
  final String? date;
  final List<String> tags;
  final List<String> aliases;
  final List<String> links;
  final List<String> files;
}

class QueriedMetadata {
  const QueriedMetadata({
    required this.note,
    required this.links,
    required this.tags,
    required this.files,
  });

  final Map<String, Object?>? note;
  final List<String> links;
  final List<String> tags;
  final List<String> files;
}

class TypstMetadataReader {
  TypstMetadataReader._(this._compiler);

  final TypstCompiler _compiler;

  static Future<TypstMetadataReader> create() async =>
      TypstMetadataReader._(await TypstCompiler.create());

  Future<QueriedMetadata> read(String source) async {
    final calls = locateTypstCalls(source);
    if (calls.isEmpty) {
      return const QueriedMetadata(note: null, links: [], tags: [], files: []);
    }
    final document = await _compiler.compile(
      source:
          '#import "/.tylog/tylog.typ": *\n${calls.map((call) => call.source).join('\n')}',
      files: FileSource.bytes({
        '.tylog/tylog.typ': Uint8List.fromList(utf8.encode(tylogHelperSource)),
        '/.tylog/tylog.typ': Uint8List.fromList(utf8.encode(tylogHelperSource)),
      }),
    );
    try {
      final noteValues = decodeTypstMetadata(
        await _compiler.query(document: document, selector: '<tylog-note>'),
      );
      return QueriedMetadata(
        note: noteValues.whereType<Map>().firstOrNull?.cast<String, Object?>(),
        links: _targets(
          decodeTypstMetadata(
            await _compiler.query(document: document, selector: '<tylog-link>'),
          ),
          'target',
        ),
        tags: _targets(
          decodeTypstMetadata(
            await _compiler.query(document: document, selector: '<tylog-tag>'),
          ),
        ),
        files: _targets(
          decodeTypstMetadata(
            await _compiler.query(document: document, selector: '<tylog-file>'),
          ),
        ),
      );
    } finally {
      document.dispose();
    }
  }

  void dispose() => _compiler.dispose();
}

List<Object?> decodeTypstMetadata(String json) {
  final elements = (jsonDecode(json) as List).cast<Object?>();
  return elements.map((element) {
    if (element is Map && element.containsKey('value')) return element['value'];
    return element;
  }).toList();
}

List<TypstCall> locateTypstCalls(
  String source, {
  Set<String> names = const {'note', 'wikilink', 'tag', 'filelink'},
}) {
  final calls = <TypstCall>[];
  var i = 0;
  while (i < source.length) {
    if (_starts(source, i, '//')) {
      i = source.indexOf('\n', i);
      if (i < 0) break;
      continue;
    }
    if (_starts(source, i, '/*')) {
      i = _skipBlockComment(source, i);
      continue;
    }
    if (source.codeUnitAt(i) == 34) {
      i = _skipString(source, i);
      continue;
    }
    if (source.codeUnitAt(i) == 96) {
      i = _skipRaw(source, i);
      continue;
    }
    if (source.codeUnitAt(i) != 35) {
      i++;
      continue;
    }
    final start = i++;
    final nameStart = i;
    while (i < source.length && _identifier(source.codeUnitAt(i))) {
      i++;
    }
    final name = source.substring(nameStart, i);
    while (i < source.length && _space(source.codeUnitAt(i))) {
      i++;
    }
    if (!names.contains(name) ||
        i >= source.length ||
        source.codeUnitAt(i) != 40) {
      continue;
    }
    final end = _balancedEnd(source, i);
    if (end == null) continue;
    calls.add(TypstCall(name, start, end, source.substring(start, end)));
    i = end;
  }
  return calls;
}

NoteRef scanNote(String relativePath, String source, {String? fingerprint}) =>
    _fallbackNote(relativePath, source, fingerprint: fingerprint);

Future<VaultIndex> scanVault(
  Directory root, {
  VaultIndex? previous,
  bool force = false,
  void Function(int complete, int total)? onProgress,
  bool Function()? isCancelled,
}) async {
  final files = <File>[];
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is! File || !entity.path.endsWith('.typ')) continue;
    final relative = _relativePath(root, entity);
    if (relative.startsWith('.tylog/')) continue;
    files.add(entity);
  }
  files.sort((a, b) => a.path.compareTo(b.path));

  TypstMetadataReader? reader;
  try {
    reader = await TypstMetadataReader.create();
  } catch (_) {
    // Native FFI is unavailable in plain flutter_test; production apps query Typst.
  }

  final notes = <String, NoteRef>{};
  final problems = <PkmsProblem>[];
  try {
    for (var fileIndex = 0; fileIndex < files.length; fileIndex++) {
      if (isCancelled?.call() ?? false) throw const IndexBuildCancelled();
      final file = files[fileIndex];
      final relative = _relativePath(root, file);
      final stat = await file.stat();
      final fingerprint =
          '${stat.modified.millisecondsSinceEpoch}:${stat.size}';
      final cached = previous?.notesByPath[relative];
      if (!force && cached?.fingerprint == fingerprint) {
        notes[relative] = cached!;
        if (cached.metadataSource != 'typst-query') {
          problems.add(_fallbackProblem(relative));
        }
        onProgress?.call(fileIndex + 1, files.length);
        continue;
      }
      final source = await file.readAsString();
      try {
        final queried = reader == null ? null : await reader.read(source);
        notes[relative] = queried?.note == null
            ? _fallbackNote(relative, source, fingerprint: fingerprint)
            : _queriedNote(relative, source, queried!, fingerprint);
        if (queried?.note == null) {
          problems.add(_fallbackProblem(relative));
        }
      } catch (error) {
        final fallback = _fallbackNote(
          relative,
          source,
          fingerprint: fingerprint,
        );
        notes[relative] =
            cached?.copyWith(fingerprint: fingerprint) ?? fallback;
        problems.add(
          PkmsProblem(
            code: 'metadata-query-failed',
            severity: PkmsSeverity.warning,
            subject: relative,
            message: 'Typst metadata query failed: $error',
            fix: 'Fix the metadata header or convert it to managed metadata.',
          ),
        );
      }
      onProgress?.call(fileIndex + 1, files.length);
    }
  } finally {
    reader?.dispose();
  }
  return buildVaultIndex(notes, problems: problems);
}

PkmsProblem _fallbackProblem(String path) => PkmsProblem(
  code: 'metadata-fallback',
  severity: PkmsSeverity.warning,
  subject: path,
  message: 'Typst metadata was unavailable; using legacy parsing.',
  fix: 'Convert this note to the managed metadata header.',
);

VaultIndex buildVaultIndex(
  Map<String, NoteRef> notes, {
  List<PkmsProblem> problems = const [],
}) {
  final resolver = LinkResolver(notes.values);
  final backlinks = <String, Set<String>>{};
  final fileBacklinks = <String, Set<String>>{};
  final allProblems = [...problems];
  for (final source in notes.values) {
    for (final target in source.outgoingLinks) {
      final resolved = resolver.resolve(target);
      if (resolved.status == LinkResolutionStatus.resolved) {
        backlinks.putIfAbsent(resolved.path!, () => {}).add(source.path);
      } else {
        allProblems.add(
          PkmsProblem(
            code: resolved.status == LinkResolutionStatus.ambiguous
                ? 'ambiguous-link'
                : 'broken-link',
            severity: PkmsSeverity.warning,
            subject: source.path,
            message: '${resolved.status.name} link: $target',
            fix: 'Choose a unique note ID or create the missing note.',
          ),
        );
      }
    }
    for (final id in source.fileRefs) {
      fileBacklinks.putIfAbsent(id, () => {}).add(source.path);
    }
  }
  return VaultIndex(
    notesByPath: notes,
    backlinksByTarget: _setsToSortedLists(backlinks),
    fileBacklinksById: _setsToSortedLists(fileBacklinks),
    problems: allProblems,
  );
}

String? resolveLinkPath(VaultIndex index, String target) {
  final resolved = LinkResolver(index.notes).resolve(target);
  return resolved.status == LinkResolutionStatus.resolved
      ? resolved.path
      : null;
}

LinkResolution resolveLink(VaultIndex index, String target) =>
    LinkResolver(index.notes).resolve(target);

String replaceNoteHeader(String source, NoteMetadataDraft draft) {
  final header = serializeNoteHeader(draft);
  final calls = locateTypstCalls(source, names: const {'note'});
  if (calls.isNotEmpty) {
    final call = calls.first;
    return source.replaceRange(call.start, call.end, header);
  }
  final importEnd = source.startsWith('#import ')
      ? source.indexOf('\n') + 1
      : 0;
  return source.replaceRange(importEnd, importEnd, '$header\n\n');
}

String serializeNoteHeader(NoteMetadataDraft draft) {
  final fields = <String>[
    '  id: ${_typstString(draft.id)},',
    '  title: ${_typstString(draft.title)},',
    if (draft.date != null && draft.date!.isNotEmpty)
      '  date: ${_typstString(draft.date!)},',
    '  tags: ${_typstList(draft.tags)},',
    '  aliases: ${_typstList(draft.aliases)},',
    '  links: ${_typstList(draft.links)},',
    '  files: ${_typstList(draft.files)},',
  ];
  return '#note(\n${fields.join('\n')}\n)';
}

NoteRef _queriedNote(
  String path,
  String source,
  QueriedMetadata metadata,
  String fingerprint,
) {
  final note = metadata.note!;
  final stem = path.split('/').last.replaceFirst(RegExp(r'\.typ$'), '');
  return NoteRef(
    id: _text(note['id']) ?? stem,
    path: path,
    title: _text(note['title']) ?? stem,
    date: _text(note['date']),
    tags: _sorted({..._strings(note['tags']), ...metadata.tags}),
    aliases: _sorted(_strings(note['aliases']).toSet()),
    outgoingLinks: _sorted({..._strings(note['links']), ...metadata.links}),
    fileRefs: _sorted({..._strings(note['files']), ...metadata.files}),
    citations: _citations(source),
    fingerprint: fingerprint,
    metadataSource: 'typst-query',
  );
}

NoteRef _fallbackNote(String path, String source, {String? fingerprint}) {
  final stem = path.split('/').last.replaceFirst(RegExp(r'\.typ$'), '');
  final calls = locateTypstCalls(source);
  final header =
      calls.where((call) => call.name == 'note').firstOrNull?.source ?? '';
  return NoteRef(
    id: _field(header, 'id') ?? stem,
    path: path,
    title: _field(header, 'title') ?? stem,
    date: _field(header, 'date'),
    tags: _sorted({
      ..._parseList(header, 'tags'),
      ..._firstArguments(calls, 'tag'),
    }),
    aliases: _sorted(_parseList(header, 'aliases').toSet()),
    outgoingLinks: _sorted({
      ..._parseList(header, 'links'),
      ..._firstArguments(calls, 'wikilink'),
    }),
    fileRefs: _sorted({
      ..._parseList(header, 'files'),
      ..._firstArguments(calls, 'filelink'),
    }),
    citations: _citations(source),
    fingerprint: fingerprint,
    metadataSource: 'fallback',
  );
}

String? _field(String source, String name) =>
    RegExp('$name\\s*:\\s*"((?:\\\\.|[^"\\\\])*)"')
        .firstMatch(source)
        ?.group(1)
        ?.replaceAllMapped(RegExp(r'\\(.)'), (match) => match.group(1)!);

List<String> _parseList(String source, String field) {
  final match = RegExp(
    '$field\\s*:\\s*\\(([^)]*)\\)',
    dotAll: true,
  ).firstMatch(source);
  if (match == null) return const [];
  return _quoted
      .allMatches(match.group(1)!)
      .map((match) => match.group(1)!.replaceAll(r'\"', '"'))
      .toSet()
      .toList();
}

List<String> _firstArguments(List<TypstCall> calls, String name) => calls
    .where((call) => call.name == name)
    .map((call) => _quoted.firstMatch(call.source)?.group(1))
    .whereType<String>()
    .toList();

List<String> _citations(String source) {
  final masked = StringBuffer();
  var i = 0;
  while (i < source.length) {
    if (_starts(source, i, '//')) {
      final end = source.indexOf('\n', i);
      masked.write(''.padRight((end < 0 ? source.length : end) - i));
      i = end < 0 ? source.length : end;
    } else if (_starts(source, i, '/*')) {
      final end = _skipBlockComment(source, i);
      masked.write(''.padRight(end - i));
      i = end;
    } else if (source.codeUnitAt(i) == 34) {
      final end = _skipString(source, i);
      masked.write(''.padRight(end - i));
      i = end;
    } else if (source.codeUnitAt(i) == 96) {
      final end = _skipRaw(source, i);
      masked.write(''.padRight(end - i));
      i = end;
    } else {
      masked.writeCharCode(source.codeUnitAt(i++));
    }
  }
  return _sorted(
    RegExp(r'@([A-Za-z0-9_:.+-]+)')
        .allMatches(masked.toString())
        .map((match) => match.group(1)!.replaceFirst(RegExp(r'[.,;:!?]+$'), ''))
        .toSet(),
  );
}

List<String> _targets(List<Object?> values, [String? key]) => _sorted(
  values
      .map(
        (value) => key == null
            ? value
            : value is Map
            ? value[key]
            : null,
      )
      .whereType<Object>()
      .map((value) => value.toString())
      .toSet(),
);

List<String> _strings(Object? value) =>
    (value as List? ?? const []).map((item) => item.toString()).toList();

String? _text(Object? value) => value?.toString();

List<String> _sorted(Set<String> values) => values.toList()..sort();

Map<String, List<String>> _setsToSortedLists(Map<String, Set<String>> value) =>
    {
      for (final key in (value.keys.toList()..sort()))
        key: value[key]!.toList()..sort(),
    };

void _add(Map<String, Set<String>> map, String key, String path) {
  if (key.isNotEmpty) map.putIfAbsent(key, () => {}).add(path);
}

LinkResolution _resolveCandidates(String target, Set<String> candidates) {
  final sorted = candidates.toList()..sort();
  if (sorted.length == 1) {
    return LinkResolution(
      target: target,
      status: LinkResolutionStatus.resolved,
      path: sorted.first,
      candidates: sorted,
    );
  }
  return LinkResolution(
    target: target,
    status: LinkResolutionStatus.ambiguous,
    candidates: sorted,
  );
}

int? _balancedEnd(String source, int open) {
  var depth = 0;
  var i = open;
  while (i < source.length) {
    if (_starts(source, i, '//')) {
      i = source.indexOf('\n', i);
      if (i < 0) return null;
      continue;
    }
    if (_starts(source, i, '/*')) {
      i = _skipBlockComment(source, i);
      continue;
    }
    if (source.codeUnitAt(i) == 34) {
      i = _skipString(source, i);
      continue;
    }
    if (source.codeUnitAt(i) == 96) {
      i = _skipRaw(source, i);
      continue;
    }
    if (source.codeUnitAt(i) == 40) depth++;
    if (source.codeUnitAt(i) == 41 && --depth == 0) return i + 1;
    i++;
  }
  return null;
}

int _skipString(String source, int start) {
  var i = start + 1;
  while (i < source.length) {
    if (source.codeUnitAt(i) == 92) {
      i += 2;
    } else if (source.codeUnitAt(i++) == 34) {
      break;
    }
  }
  return i;
}

int _skipRaw(String source, int start) {
  var ticks = 1;
  while (start + ticks < source.length &&
      source.codeUnitAt(start + ticks) == 96) {
    ticks++;
  }
  final delimiter = List.filled(ticks, '`').join();
  final end = source.indexOf(delimiter, start + ticks);
  return end < 0 ? source.length : end + ticks;
}

int _skipBlockComment(String source, int start) {
  var depth = 1;
  var i = start + 2;
  while (i < source.length && depth > 0) {
    if (_starts(source, i, '/*')) {
      depth++;
      i += 2;
    } else if (_starts(source, i, '*/')) {
      depth--;
      i += 2;
    } else {
      i++;
    }
  }
  return i;
}

bool _starts(String source, int at, String value) =>
    at + value.length <= source.length && source.startsWith(value, at);

bool _identifier(int code) =>
    code >= 65 && code <= 90 ||
    code >= 97 && code <= 122 ||
    code >= 48 && code <= 57 ||
    code == 45 ||
    code == 95;

bool _space(int code) => code == 9 || code == 10 || code == 13 || code == 32;

String _typstString(String value) =>
    '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';

String _typstList(List<String> values) =>
    values.isEmpty ? '()' : '(${values.map(_typstString).join(', ')},)';

String _relativePath(Directory root, File file) {
  final rootPath = root.absolute.path.endsWith(Platform.pathSeparator)
      ? root.absolute.path
      : '${root.absolute.path}${Platform.pathSeparator}';
  return file.absolute.path
      .substring(rootPath.length)
      .replaceAll(Platform.pathSeparator, '/');
}
