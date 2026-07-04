import 'dart:convert';
import 'dart:io';

import 'models.dart';

class PkmsTagEntry {
  const PkmsTagEntry({
    required this.slug,
    required this.title,
    required this.type,
    this.aliases = const [],
  });

  final String slug;
  final String title;
  final String type;
  final List<String> aliases;

  PkmsTagEntry copyWith({String? title, String? type, List<String>? aliases}) =>
      PkmsTagEntry(
        slug: slug,
        title: title ?? this.title,
        type: type ?? this.type,
        aliases: aliases ?? this.aliases,
      );

  Map<String, Object?> toJson() => {
    'title': title,
    'type': type,
    'aliases': aliases,
  };

  factory PkmsTagEntry.fromJson(String slug, Map<String, Object?> json) =>
      PkmsTagEntry(
        slug: slug,
        title: (json['title'] as String?) ?? slug,
        type: (json['type'] as String?) ?? 'topic',
        aliases: _strings(json['aliases']),
      );
}

class PkmsTagRegistry {
  const PkmsTagRegistry({required this.tags, this.version = 2});

  final int version;
  final Map<String, PkmsTagEntry> tags;

  static PkmsTagRegistry get empty => PkmsTagRegistry(tags: {});

  Map<String, Object?> toJson() => {
    'version': version,
    'tags': {
      for (final slug in (tags.keys.toList()..sort()))
        slug: tags[slug]!.toJson(),
    },
  };
}

class PkmsFileEntry {
  const PkmsFileEntry({
    required this.id,
    required this.path,
    required this.kind,
    required this.status,
    this.title,
    this.tags = const [],
  });

  final String id;
  final String path;
  final String kind;
  final String status;
  final String? title;
  final List<String> tags;

  String get displayTitle => title == null || title!.isEmpty ? id : title!;

  PkmsFileEntry copyWith({
    String? path,
    String? kind,
    String? status,
    String? title,
    List<String>? tags,
  }) => PkmsFileEntry(
    id: id,
    path: path ?? this.path,
    kind: kind ?? this.kind,
    status: status ?? this.status,
    title: title ?? this.title,
    tags: tags ?? this.tags,
  );

  Map<String, Object?> toJson() => {
    'path': path,
    'kind': kind,
    'status': status,
    if (title != null) 'title': title,
    'tags': tags,
  };

  factory PkmsFileEntry.fromJson(String id, Map<String, Object?> json) =>
      PkmsFileEntry(
        id: id,
        path: (json['path'] as String?) ?? '',
        kind: (json['kind'] as String?) ?? 'file',
        status: (json['status'] as String?) ?? 'reference',
        title: json['title'] as String?,
        tags: _strings(json['tags']),
      );
}

class PkmsFileRegistry {
  const PkmsFileRegistry({required this.files, this.version = 2});

  final int version;
  final Map<String, PkmsFileEntry> files;

  static PkmsFileRegistry get empty => PkmsFileRegistry(files: {});

  Map<String, Object?> toJson() => {
    'version': version,
    'files': {
      for (final id in (files.keys.toList()..sort())) id: files[id]!.toJson(),
    },
  };
}

class PkmsCollectionEntry {
  const PkmsCollectionEntry({
    required this.id,
    required this.title,
    required this.noteIds,
    this.bibliographyPath,
  });

  final String id;
  final String title;
  final List<String> noteIds;
  final String? bibliographyPath;

  Map<String, Object?> toJson() => {
    'title': title,
    'noteIds': noteIds,
    if (bibliographyPath != null) 'bibliographyPath': bibliographyPath,
  };

  factory PkmsCollectionEntry.fromJson(String id, Map<String, Object?> json) =>
      PkmsCollectionEntry(
        id: id,
        title: json['title'] as String? ?? id,
        noteIds: _strings(json['noteIds']),
        bibliographyPath: json['bibliographyPath'] as String?,
      );
}

class PkmsCollectionRegistry {
  const PkmsCollectionRegistry({required this.collections, this.version = 1});

  final int version;
  final Map<String, PkmsCollectionEntry> collections;

  static PkmsCollectionRegistry get empty =>
      PkmsCollectionRegistry(collections: {});

  Map<String, Object?> toJson() => {
    'version': version,
    'collections': {
      for (final id in (collections.keys.toList()..sort()))
        id: collections[id]!.toJson(),
    },
  };
}

class PkmsData {
  const PkmsData({
    required this.tags,
    required this.files,
    required this.collections,
    this.problems = const [],
  });

  final PkmsTagRegistry tags;
  final PkmsFileRegistry files;
  final PkmsCollectionRegistry collections;
  final List<PkmsProblem> problems;
}

class PkmsValidationReport {
  const PkmsValidationReport({required this.problems});

  final List<PkmsProblem> problems;

  int count(String code) =>
      problems.where((problem) => problem.code == code).length;

  int get unknownTags => count('unknown-tag');
  int get duplicateAliases => count('duplicate-alias');
  int get missingFiles => count('missing-file');
  bool get hasIssues =>
      problems.any((problem) => problem.severity != PkmsSeverity.info);

  String summary() =>
      'validation errors=${problems.where((p) => p.severity == PkmsSeverity.error).length} warnings=${problems.where((p) => p.severity == PkmsSeverity.warning).length}';
}

Future<PkmsData> loadPkmsData(Directory root) async {
  final problems = <PkmsProblem>[];
  final tags = await _load(
    File('${root.path}/.tylog/tags.json'),
    PkmsTagRegistry.empty,
    (json) => PkmsTagRegistry(
      version: (json['version'] as num?)?.toInt() ?? 1,
      tags: _entries(json['tags'], PkmsTagEntry.fromJson),
    ),
    problems,
    'tags-registry-invalid',
  );
  final files = await _load(
    File('${root.path}/.tylog/files.json'),
    PkmsFileRegistry.empty,
    (json) => PkmsFileRegistry(
      version: (json['version'] as num?)?.toInt() ?? 1,
      files: _entries(json['files'], PkmsFileEntry.fromJson),
    ),
    problems,
    'files-registry-invalid',
  );
  final collections = await _load(
    File('${root.path}/.tylog/collections.json'),
    PkmsCollectionRegistry.empty,
    (json) => PkmsCollectionRegistry(
      version: (json['version'] as num?)?.toInt() ?? 1,
      collections: _entries(json['collections'], PkmsCollectionEntry.fromJson),
    ),
    problems,
    'collections-registry-invalid',
  );
  if (await root.exists()) {
    await for (final entity in root.list(recursive: true)) {
      if (entity is File && entity.path.contains('.remote-conflict-')) {
        final subject = entity.path
            .substring(root.absolute.path.length + 1)
            .replaceAll(Platform.pathSeparator, '/');
        problems.add(
          PkmsProblem(
            code: 'sync-conflict',
            severity: PkmsSeverity.error,
            subject: subject,
            message: 'A synced file has a conflict copy.',
            fix: 'Tap to compare and merge the versions.',
          ),
        );
      }
    }
  }
  return PkmsData(
    tags: tags,
    files: files,
    collections: collections,
    problems: problems,
  );
}

Future<PkmsTagRegistry> loadTagRegistry(Directory root) async =>
    (await loadPkmsData(root)).tags;

Future<PkmsFileRegistry> loadFileRegistry(Directory root) async =>
    (await loadPkmsData(root)).files;

Future<PkmsCollectionRegistry> loadCollectionRegistry(Directory root) async =>
    (await loadPkmsData(root)).collections;

Future<void> saveTagRegistry(Directory root, PkmsTagRegistry registry) =>
    _writeJson(File('${root.path}/.tylog/tags.json'), registry.toJson());

Future<void> saveFileRegistry(Directory root, PkmsFileRegistry registry) =>
    _writeJson(File('${root.path}/.tylog/files.json'), registry.toJson());

Future<void> saveCollectionRegistry(
  Directory root,
  PkmsCollectionRegistry registry,
) =>
    _writeJson(File('${root.path}/.tylog/collections.json'), registry.toJson());

Future<PkmsValidationReport> validatePkms(
  Directory root,
  VaultIndex index, {
  PkmsData? data,
}) async {
  final pkms = data ?? await loadPkmsData(root);
  final problems = <PkmsProblem>[...index.problems, ...pkms.problems];
  final knownTags = pkms.tags.tags.keys.toSet();

  for (final note in index.notes) {
    if (note.metadataSource != 'typst-query') {
      problems.add(
        PkmsProblem(
          code: 'legacy-note-metadata',
          severity: PkmsSeverity.info,
          subject: note.path,
          message: 'This note is not using verified Typst metadata.',
          fix: 'Open Edit metadata and save to convert the header.',
        ),
      );
    }
    for (final tag in note.tags) {
      if (!knownTags.contains(tag)) {
        problems.add(_unknownTag(note.path, tag));
      }
    }
    for (final id in note.fileRefs) {
      if (!pkms.files.files.containsKey(id)) {
        problems.add(
          PkmsProblem(
            code: 'unknown-file-id',
            severity: PkmsSeverity.error,
            subject: note.path,
            message: 'Unknown file id: $id',
            fix: 'Import the file or remove the reference.',
          ),
        );
      }
    }
  }
  for (final file in pkms.files.files.values) {
    for (final tag in file.tags) {
      if (!knownTags.contains(tag)) problems.add(_unknownTag(file.id, tag));
    }
    if (!_safeRelativePath(file.path)) {
      problems.add(
        PkmsProblem(
          code: 'unsafe-file-path',
          severity: PkmsSeverity.error,
          subject: file.id,
          message: 'File path must stay inside the vault: ${file.path}',
          fix: 'Choose a vault-relative asset path.',
        ),
      );
    } else if (!await File('${root.path}/${file.path}').exists()) {
      problems.add(
        PkmsProblem(
          code: 'missing-file',
          severity: PkmsSeverity.error,
          subject: file.id,
          message: 'Missing file: ${file.path}',
          fix: 'Restore, re-import, or remove this registry entry.',
        ),
      );
    }
  }
  final noteIds = index.notes.map((note) => note.id).toSet();
  for (final collection in pkms.collections.collections.values) {
    for (final id in collection.noteIds) {
      if (!noteIds.contains(id)) {
        problems.add(
          PkmsProblem(
            code: 'collection-note-missing',
            severity: PkmsSeverity.error,
            subject: collection.id,
            message: 'Collection note is missing: $id',
            fix: 'Remove the ID or restore the note.',
          ),
        );
      }
    }
    final bibliography = collection.bibliographyPath;
    if (bibliography != null && bibliography.isNotEmpty) {
      if (!_safeRelativePath(bibliography)) {
        problems.add(
          PkmsProblem(
            code: 'unsafe-bibliography-path',
            severity: PkmsSeverity.error,
            subject: collection.id,
            message: 'Bibliography path must stay inside the vault.',
            fix: 'Choose a vault-relative .bib or .yml file.',
          ),
        );
      } else if (!await File('${root.path}/$bibliography').exists()) {
        problems.add(
          PkmsProblem(
            code: 'bibliography-missing',
            severity: PkmsSeverity.error,
            subject: collection.id,
            message: 'Bibliography is missing: $bibliography',
            fix: 'Restore the file or clear the collection bibliography.',
          ),
        );
      }
    }
  }

  _duplicates(
    index.notes.map((note) => MapEntry(note.id, note.path)),
    'duplicate-note-id',
    problems,
  );
  _duplicates(
    [
      for (final note in index.notes)
        for (final alias in note.aliases) MapEntry(alias, note.path),
      for (final tag in pkms.tags.tags.values)
        for (final alias in tag.aliases) MapEntry(alias, 'tag:${tag.slug}'),
    ],
    'duplicate-alias',
    problems,
  );
  problems.sort((a, b) {
    final severity = b.severity.index.compareTo(a.severity.index);
    return severity != 0 ? severity : a.subject.compareTo(b.subject);
  });
  return PkmsValidationReport(problems: problems);
}

bool isSafeVaultPath(String path) => _safeRelativePath(path);

PkmsProblem _unknownTag(String subject, String tag) => PkmsProblem(
  code: 'unknown-tag',
  severity: PkmsSeverity.warning,
  subject: subject,
  message: 'Unknown tag: $tag',
  fix: 'Create the canonical tag or remove it.',
);

void _duplicates(
  Iterable<MapEntry<String, String>> values,
  String code,
  List<PkmsProblem> problems,
) {
  final owners = <String, Set<String>>{};
  for (final entry in values) {
    if (entry.key.isNotEmpty) {
      owners.putIfAbsent(entry.key, () => {}).add(entry.value);
    }
  }
  for (final entry in owners.entries.where((entry) => entry.value.length > 1)) {
    problems.add(
      PkmsProblem(
        code: code,
        severity: PkmsSeverity.error,
        subject: entry.key,
        message: '${entry.key} is owned by ${entry.value.join(', ')}',
        fix: 'Keep one canonical owner and rename or merge the others.',
      ),
    );
  }
}

Future<T> _load<T>(
  File file,
  T empty,
  T Function(Map<String, Object?> json) decode,
  List<PkmsProblem> problems,
  String errorCode,
) async {
  if (!await file.exists()) return empty;
  try {
    return decode(
      (jsonDecode(await file.readAsString()) as Map).cast<String, Object?>(),
    );
  } catch (error) {
    problems.add(
      PkmsProblem(
        code: errorCode,
        severity: PkmsSeverity.error,
        subject: file.path,
        message: 'Registry could not be read: $error',
        fix: 'Repair the JSON or restore a known-good copy.',
      ),
    );
    return empty;
  }
}

Map<String, T> _entries<T>(
  Object? value,
  T Function(String id, Map<String, Object?> json) decode,
) => (value as Map? ?? const {}).map<String, T>(
  (key, value) => MapEntry(
    key.toString(),
    decode(key.toString(), (value as Map).cast<String, Object?>()),
  ),
);

Future<void> _writeJson(File file, Map<String, Object?> value) async {
  await file.parent.create(recursive: true);
  final tmp = File('${file.path}.tmp');
  await tmp.writeAsString(
    const JsonEncoder.withIndent('  ').convert(value),
    flush: true,
  );
  if (await file.exists()) await file.delete();
  await tmp.rename(file.path);
}

bool _safeRelativePath(String path) {
  if (path.isEmpty || path.startsWith('/') || path.startsWith(r'\')) {
    return false;
  }
  if (RegExp(r'^[A-Za-z]:[\/]').hasMatch(path)) return false;
  return !path.replaceAll('\\', '/').split('/').contains('..');
}

List<String> _strings(Object? value) =>
    (value as List? ?? const []).map((item) => item.toString()).toList();
