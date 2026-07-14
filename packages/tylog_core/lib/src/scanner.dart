import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'models.dart';
import 'storage.dart';

enum TylogHelperKind { current, legacy, custom }

TylogHelperKind classifyTylogHelper(
  String source, {
  String? current,
  String? legacy,
}) {
  final normalized = source.replaceAll('\r\n', '\n').trim();
  if (current != null &&
      normalized == current.replaceAll('\r\n', '\n').trim()) {
    return TylogHelperKind.current;
  }
  if (legacy != null && normalized == legacy.replaceAll('\r\n', '\n').trim()) {
    return TylogHelperKind.legacy;
  }
  if (normalized.contains('// tylog-package: 0.1.0')) {
    return TylogHelperKind.current;
  }
  return TylogHelperKind.custom;
}

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
    this.kind = 'note',
    this.project,
    this.date,
    this.tags = const [],
    this.aliases = const [],
    this.properties = const {},
  });

  final String id;
  final String title;
  final String kind;
  final String? project;
  final String? date;
  final List<String> tags;
  final List<String> aliases;
  final Map<String, Object?> properties;
}

class QueriedMetadata {
  const QueriedMetadata({
    required this.note,
    required this.links,
    required this.tags,
    required this.dates,
    required this.attachments,
    required this.tasks,
  });

  final Map<String, Object?>? note;
  final List<String> links;
  final List<String> tags;
  final List<Map<String, Object?>> dates;
  final List<Map<String, Object?>> attachments;
  final List<Map<String, Object?>> tasks;
}

class TypstDocumentInput {
  const TypstDocumentInput({
    required this.path,
    required this.source,
    this.files = const {},
  });

  final String path;
  final String source;
  final Map<String, Uint8List> files;
}

class TypstMetadataRecord {
  const TypstMetadataRecord({required this.label, required this.value});

  final String label;
  final Object? value;
}

abstract interface class TypstInspector {
  Future<List<TypstMetadataRecord>> inspect(TypstDocumentInput input);
}

List<TypstMetadataRecord> decodeTypstMetadataRecords(String json) {
  final elements = (jsonDecode(json) as List).cast<Object?>();
  return [
    for (final element in elements)
      if (element is Map && element['label'] != null)
        TypstMetadataRecord(
          label: element['label'].toString(),
          value: element['value'],
        ),
  ];
}

List<Object?> decodeTypstMetadata(String json) =>
    (jsonDecode(json) as List).map((element) {
      if (element is Map && element.containsKey('value')) {
        return element['value'];
      }
      return element;
    }).toList();

QueriedMetadata decodeTylogMetadataRecords(
  Iterable<TypstMetadataRecord> records,
) {
  final noteValues = _recordValues(records, '<tylog-note>', 'note');
  return QueriedMetadata(
    note: noteValues.whereType<Map>().firstOrNull?.cast<String, Object?>(),
    links: _targets(_recordValues(records, '<tylog-link>', 'link'), 'target'),
    tags: _targets(_recordValues(records, '<tylog-tag>', 'tag'), 'name'),
    dates: _maps(_recordValues(records, '<tylog-date>', 'date')),
    attachments: _maps(
      _recordValues(records, '<tylog-attachment>', 'attachment'),
    ),
    tasks: _maps(_recordValues(records, '<tylog-task>', 'task')),
  );
}

List<Object?> _recordValues(
  Iterable<TypstMetadataRecord> records,
  String label,
  String entity,
) => records
    .where((record) => record.label == label)
    .map((record) {
      final value = record.value;
      if (value is! Map || value['schema'] == null) return value;
      return value['schema'] == 1 && value['entity'] == entity ? value : null;
    })
    .where((value) => value != null)
    .cast<Object?>()
    .toList();

List<TypstCall> locateTypstCalls(
  String source, {
  Set<String> names = const {
    'tylog.ref-note',
    'tylog.tag',
    'tylog.task',
    'tylog.date-ref',
    'tylog.attachment',
  },
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
    var name = source.substring(nameStart, i);
    if (i < source.length && source.codeUnitAt(i) == 46) {
      final memberStart = ++i;
      while (i < source.length && _identifier(source.codeUnitAt(i))) {
        i++;
      }
      name = '$name.${source.substring(memberStart, i)}';
    }
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
    var callEnd = end;
    var contentStart = end;
    while (contentStart < source.length &&
        _space(source.codeUnitAt(contentStart))) {
      contentStart++;
    }
    if (contentStart < source.length && source.codeUnitAt(contentStart) == 91) {
      callEnd = _balancedContentEnd(source, contentStart) ?? end;
    }
    calls.add(
      TypstCall(name, start, callEnd, source.substring(start, callEnd)),
    );
    i = callEnd;
  }
  return calls;
}

TypstCall? _noteHeader(String source) {
  final match = RegExp(
    r'#show\s*:\s*tylog\.note\.with\s*\(',
  ).firstMatch(source);
  if (match == null) return null;
  final open = source.indexOf('(', match.start);
  final end = _balancedEnd(source, open);
  if (end == null) return null;
  return TypstCall(
    'tylog.note.with',
    match.start,
    end,
    source.substring(match.start, end),
  );
}

NoteRef scanNote(String relativePath, String source, {String? fingerprint}) =>
    _fallbackNote(relativePath, source, fingerprint: fingerprint);

Future<VaultIndex> scanVault(
  Directory root, {
  TypstInspector? inspector,
  VaultIndex? previous,
  bool force = false,
  void Function(int complete, int total)? onProgress,
  bool Function()? isCancelled,
}) => scanVaultStorage(
  LocalVaultStorage(root),
  inspector: inspector,
  previous: previous,
  force: force,
  onProgress: onProgress,
  isCancelled: isCancelled,
);

Future<VaultIndex> scanVaultStorage(
  VaultStorage storage, {
  TypstInspector? inspector,
  VaultIndex? previous,
  bool force = false,
  void Function(int complete, int total)? onProgress,
  bool Function()? isCancelled,
}) async {
  final files = <VaultStorageEntry>[];
  for (final entity in await storage.list(recursive: true)) {
    if (entity.isDirectory || !entity.path.endsWith('.typ')) continue;
    final relative = entity.path;
    if (!const [
      'daily/',
      'notes/',
      'projects/',
      'articles/',
    ].any(relative.startsWith)) {
      continue;
    }
    files.add(entity);
  }
  files.sort((a, b) => a.path.compareTo(b.path));
  Map<String, Uint8List>? inspectionFiles;

  final notes = <String, NoteRef>{};
  final tasks = <TaskRef>[];
  final problems = <PkmsProblem>[];
  for (var fileIndex = 0; fileIndex < files.length; fileIndex++) {
    if (isCancelled?.call() ?? false) throw const IndexBuildCancelled();
    final file = files[fileIndex];
    final relative = file.path;
    final fingerprint =
        '${file.modified?.millisecondsSinceEpoch ?? 0}:${file.size ?? 0}';
    final cached = previous?.notesByPath[relative];
    if (!force &&
        previous?.version == 5 &&
        cached?.fingerprint == fingerprint) {
      notes[relative] = cached!;
      tasks.addAll(
        previous?.tasks.where((task) => task.notePath == relative) ?? const [],
      );
      if (cached.metadataSource != 'typst-query') {
        problems.add(_fallbackProblem(relative));
      }
      onProgress?.call(fileIndex + 1, files.length);
      continue;
    }
    final source = await storage.readText(relative);
    inspectionFiles ??= inspector == null
        ? const <String, Uint8List>{}
        : await _inspectionFiles(storage);
    try {
      final queried = inspector == null
          ? null
          : decodeTylogMetadataRecords(
              await inspector.inspect(
                TypstDocumentInput(
                  path: relative,
                  source: source,
                  files: inspectionFiles,
                ),
              ),
            );
      notes[relative] = queried?.note == null
          ? _fallbackNote(
              relative,
              source,
              fingerprint: fingerprint,
              modifiedMillis: file.modified?.millisecondsSinceEpoch ?? 0,
            )
          : _queriedNote(
              relative,
              source,
              queried!,
              fingerprint,
              file.modified?.millisecondsSinceEpoch ?? 0,
            );
      tasks.addAll(
        queried == null
            ? _fallbackTasks(relative, locateTypstCalls(source))
            : _taskRefs(relative, queried.tasks),
      );
      if (queried?.note == null) {
        problems.add(_fallbackProblem(relative));
      }
    } catch (error) {
      final fallback = _fallbackNote(
        relative,
        source,
        fingerprint: fingerprint,
        modifiedMillis: file.modified?.millisecondsSinceEpoch ?? 0,
      );
      notes[relative] = cached?.copyWith(fingerprint: fingerprint) ?? fallback;
      tasks.addAll(_fallbackTasks(relative, locateTypstCalls(source)));
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
  return buildVaultIndex(notes, problems: problems, tasks: tasks);
}

Future<Map<String, Uint8List>> _inspectionFiles(VaultStorage storage) async {
  final files = <String, Uint8List>{};
  for (final entry in await storage.list(recursive: true)) {
    if (entry.isDirectory ||
        entry.path.startsWith('_index/') ||
        entry.path.startsWith('.tylog/')) {
      continue;
    }
    final bytes = await storage.readBytes(entry.path);
    files[entry.path] = bytes;
    files['/${entry.path}'] = bytes;
  }
  return files;
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
  List<TaskRef> tasks = const [],
}) {
  final resolver = LinkResolver(notes.values);
  final backlinks = <String, Set<String>>{};
  final attachmentBacklinks = <String, Set<String>>{};
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
    for (final attachment in source.attachments) {
      attachmentBacklinks
          .putIfAbsent(attachment.path, () => {})
          .add(source.path);
    }
  }
  return VaultIndex(
    notesByPath: notes,
    backlinksByTarget: _setsToSortedLists(backlinks),
    attachmentBacklinksByPath: _setsToSortedLists(attachmentBacklinks),
    problems: allProblems,
    tasks: tasks,
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
  final call = _noteHeader(source);
  if (call != null) {
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
    '  kind: ${_typstString(draft.kind)},',
    '  date: ${draft.date == null || draft.date!.isEmpty ? 'none' : _typstString(draft.date!)},',
    '  tags: ${_typstList(draft.tags)},',
    '  aliases: ${_typstList(draft.aliases)},',
    '  project: ${draft.project == null || draft.project!.isEmpty ? 'none' : _typstString(draft.project!)},',
    '  properties: ${_typstDictionary(draft.properties)},',
  ];
  return '#show: tylog.note.with(\n${fields.join('\n')}\n)';
}

String replaceTaskStatus(String source, String id, String status) {
  final call = locateTypstCalls(
    source,
    names: const {'tylog.task'},
  ).where((call) => _field(call.source, 'id') == id).firstOrNull;
  if (call == null) throw StateError('Task $id not found');
  final statusField = RegExp(r'status\s*:\s*"[^"]*"').firstMatch(call.source);
  final replacement = statusField == null
      ? call.source.replaceFirst(RegExp(r'\)\s*$'), '  status: "$status",\n)')
      : call.source.replaceRange(
          statusField.start,
          statusField.end,
          'status: "$status"',
        );
  return source.replaceRange(call.start, call.end, replacement);
}

String completeTaskOccurrence(String source, String id, String timestamp) {
  final call = locateTypstCalls(
    source,
    names: const {'tylog.task'},
  ).where((call) => _field(call.source, 'id') == id).firstOrNull;
  if (call == null) throw StateError('Task $id not found');
  final completed = RegExp(
    r'completed\s*:\s*\(([^)]*)\)',
  ).firstMatch(call.source);
  final replacement = completed == null
      ? call.source.replaceFirst(
          RegExp(r'\)\s*$'),
          '  completed: ("$timestamp",),\n)',
        )
      : call.source.replaceRange(
          completed.start,
          completed.end,
          'completed: (${completed.group(1)}"$timestamp",)',
        );
  return source.replaceRange(call.start, call.end, replacement);
}

NoteRef _queriedNote(
  String path,
  String source,
  QueriedMetadata metadata,
  String fingerprint,
  int modifiedMillis,
) {
  final note = metadata.note!;
  final stem = path.split('/').last.replaceFirst(RegExp(r'\.typ$'), '');
  return NoteRef(
    id: _text(note['id']) ?? '',
    path: path,
    title: _text(note['title']) ?? stem,
    kind: _text(note['kind']) ?? _kindFromPath(path),
    project: _text(note['project']),
    date: _text(note['date']),
    tags: _sorted({..._strings(note['tags']), ...metadata.tags}),
    aliases: _sorted(_strings(note['aliases']).toSet()),
    outgoingLinks: _sorted(metadata.links.toSet()),
    fileRefs: _sorted(
      metadata.attachments
          .map((item) => item['path']?.toString() ?? '')
          .where((path) => path.isNotEmpty)
          .toSet(),
    ),
    citations: _citations(source),
    dateRefs: metadata.dates
        .where((item) => item['date'] != null)
        .map(
          (item) => DateRef(
            date: item['date'].toString(),
            text: _cleanContentText(item['text']),
          ),
        )
        .toList(),
    attachments: [
      for (final item in metadata.attachments)
        if (item['path'] != null)
          AttachmentRef(
            path: item['path'].toString(),
            kind: item['kind']?.toString() ?? 'file',
            title: _cleanContentText(item['title']),
          ),
    ],
    properties: (note['properties'] as Map? ?? const {})
        .cast<String, Object?>(),
    fingerprint: fingerprint,
    modifiedMillis: modifiedMillis,
    metadataSource: 'typst-query',
  );
}

NoteRef _fallbackNote(
  String path,
  String source, {
  String? fingerprint,
  int? modifiedMillis,
}) {
  final stem = path.split('/').last.replaceFirst(RegExp(r'\.typ$'), '');
  final calls = locateTypstCalls(source);
  final header = _noteHeader(source)?.source ?? '';
  final dateCalls = calls.where((call) => call.name == 'tylog.date-ref');
  final attachmentCalls = calls.where(
    (call) => call.name == 'tylog.attachment',
  );
  return NoteRef(
    id: _field(header, 'id') ?? stem,
    path: path,
    title: _field(header, 'title') ?? stem,
    kind: _field(header, 'kind') ?? _kindFromPath(path),
    project: _field(header, 'project'),
    date: _field(header, 'date'),
    tags: _sorted({
      ..._parseList(header, 'tags'),
      ..._firstArguments(calls, 'tylog.tag'),
    }),
    aliases: _sorted(_parseList(header, 'aliases').toSet()),
    outgoingLinks: _sorted({..._firstArguments(calls, 'tylog.ref-note')}),
    fileRefs: _sorted({..._firstArguments(calls, 'tylog.attachment')}),
    citations: _citations(source),
    dateRefs: dateCalls
        .map(
          (call) => DateRef(
            date: _quoted.firstMatch(call.source)?.group(1) ?? '',
            text: _bracketBody(call.source),
          ),
        )
        .where((item) => item.date.isNotEmpty)
        .toList(),
    attachments: [
      for (final call in attachmentCalls)
        if (_quoted.firstMatch(call.source)?.group(1) case final path?)
          AttachmentRef(
            path: path,
            kind: _field(call.source, 'kind') ?? 'file',
            title: _bracketBody(call.source),
          ),
    ],
    properties: const {},
    fingerprint: fingerprint,
    modifiedMillis: modifiedMillis,
    metadataSource: 'fallback',
  );
}

List<TaskRef> _taskRefs(String path, List<Map<String, Object?>> values) =>
    values
        .map(
          (value) => TaskRef(
            id: _text(value['id']) ?? '',
            notePath: path,
            text: _text(value['text']) ?? '',
            status: value['status']?.toString() ?? 'todo',
            priority: value['priority']?.toString() ?? 'normal',
            project: _text(value['project']),
            scheduled: _text(value['scheduled']),
            due: _text(value['due']),
            remind: _text(value['remind']),
            timezone: _text(value['timezone']),
            recurrence: _text(value['recurrence']),
            dependencies: _strings(value['dependencies']),
            assignees: _strings(value['assignees']),
            tags: _strings(value['tags']),
            completed: _strings(value['completed']),
            properties: (value['properties'] as Map? ?? const {})
                .cast<String, Object?>(),
          ),
        )
        .toList();

List<TaskRef> _fallbackTasks(String path, List<TypstCall> calls) => calls
    .where((call) => call.name == 'tylog.task')
    .map(
      (call) => TaskRef(
        id: _field(call.source, 'id') ?? '',
        notePath: path,
        text: _field(call.source, 'text') ?? '',
        status: _field(call.source, 'status') ?? 'todo',
        priority: _field(call.source, 'priority') ?? 'normal',
        project: _field(call.source, 'project'),
        scheduled: _field(call.source, 'scheduled'),
        due: _field(call.source, 'due'),
        remind: _field(call.source, 'remind'),
        timezone: _field(call.source, 'timezone'),
        recurrence: _field(call.source, 'recurrence'),
        dependencies: _parseList(call.source, 'dependencies'),
        assignees: _parseList(call.source, 'assignees'),
        tags: _parseList(call.source, 'tags'),
        completed: _parseList(call.source, 'completed'),
      ),
    )
    .where((task) => task.id.isNotEmpty && task.text.isNotEmpty)
    .toList();

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
    } else if (source.codeUnitAt(i) == 92 && i + 1 < source.length) {
      masked.write('  ');
      i += 2;
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
            : value,
      )
      .whereType<Object>()
      .map((value) => value.toString())
      .toSet(),
);

List<Map<String, Object?>> _maps(List<Object?> values) => values
    .whereType<Map>()
    .map((value) => value.cast<String, Object?>())
    .toList();

String _kindFromPath(String path) {
  if (path.startsWith('daily/')) return 'daily';
  if (path.startsWith('projects/')) return 'project';
  if (path.startsWith('articles/')) return 'article';
  return 'note';
}

String? _bracketBody(String source) {
  final start = source.indexOf('[');
  final end = source.lastIndexOf(']');
  if (start < 0 || end <= start) return null;
  return source.substring(start + 1, end).trim();
}

String? _cleanContentText(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  if (text.startsWith('[') && text.endsWith(']')) {
    return text.substring(1, text.length - 1).trim();
  }
  return text;
}

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

int? _balancedContentEnd(String source, int open) {
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
    if (source.codeUnitAt(i) == 91) depth++;
    if (source.codeUnitAt(i) == 93 && --depth == 0) return i + 1;
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

String _typstDictionary(Map<String, Object?> values) {
  if (values.isEmpty) return '(:)';
  return '(${values.entries.map((entry) => '${entry.key}: ${_typstValue(entry.value)}').join(', ')},)';
}

String _typstValue(Object? value) => switch (value) {
  null => 'none',
  bool() || num() => value.toString(),
  String() => _typstString(value),
  List() => '(${value.map(_typstValue).join(', ')},)',
  _ => _typstString(value.toString()),
};
