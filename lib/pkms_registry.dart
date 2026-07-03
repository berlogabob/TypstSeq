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

  factory PkmsTagEntry.fromJson(String slug, Map<String, Object?> json) =>
      PkmsTagEntry(
        slug: slug,
        title: (json['title'] as String?) ?? slug,
        type: (json['type'] as String?) ?? 'topic',
        aliases: (json['aliases'] as List? ?? const []).cast<String>(),
      );
}

class PkmsTagRegistry {
  const PkmsTagRegistry({required this.tags});

  final Map<String, PkmsTagEntry> tags;

  static const empty = PkmsTagRegistry(tags: {});
}

class PkmsFileEntry {
  const PkmsFileEntry({
    required this.id,
    required this.path,
    required this.kind,
    required this.status,
    this.title,
    this.tags = const [],
    this.notes = const [],
  });

  final String id;
  final String path;
  final String kind;
  final String status;
  final String? title;
  final List<String> tags;
  final List<String> notes;

  String get displayTitle => title == null || title!.isEmpty ? id : title!;

  factory PkmsFileEntry.fromJson(String id, Map<String, Object?> json) =>
      PkmsFileEntry(
        id: id,
        path: (json['path'] as String?) ?? '',
        kind: (json['kind'] as String?) ?? 'file',
        status: (json['status'] as String?) ?? 'reference',
        title: json['title'] as String?,
        tags: (json['tags'] as List? ?? const []).cast<String>(),
        notes: (json['notes'] as List? ?? const []).cast<String>(),
      );
}

class PkmsFileRegistry {
  const PkmsFileRegistry({required this.files});

  final Map<String, PkmsFileEntry> files;

  static const empty = PkmsFileRegistry(files: {});
}

class PkmsValidationReport {
  const PkmsValidationReport({
    required this.unknownTags,
    required this.duplicateAliases,
    required this.missingFiles,
  });

  final int unknownTags;
  final int duplicateAliases;
  final int missingFiles;

  bool get hasIssues =>
      unknownTags > 0 || duplicateAliases > 0 || missingFiles > 0;

  String summary() =>
      'validation unknownTags=$unknownTags duplicateAliases=$duplicateAliases missingFiles=$missingFiles';
}

Future<PkmsTagRegistry> loadTagRegistry(Directory root) async {
  final file = File('${root.path}/.tylog/tags.json');
  if (!await file.exists()) return PkmsTagRegistry.empty;
  final data = jsonDecode(await file.readAsString()) as Map<String, Object?>;
  final tags = (data['tags'] as Map? ?? const {}).map<String, PkmsTagEntry>((
    key,
    value,
  ) {
    final slug = key.toString();
    return MapEntry(
      slug,
      PkmsTagEntry.fromJson(slug, (value as Map).cast<String, Object?>()),
    );
  });
  return PkmsTagRegistry(tags: tags);
}

Future<PkmsFileRegistry> loadFileRegistry(Directory root) async {
  final file = File('${root.path}/.tylog/files.json');
  if (!await file.exists()) return PkmsFileRegistry.empty;
  final data = jsonDecode(await file.readAsString()) as Map<String, Object?>;
  final files = (data['files'] as Map? ?? const {}).map<String, PkmsFileEntry>((
    key,
    value,
  ) {
    final id = key.toString();
    return MapEntry(
      id,
      PkmsFileEntry.fromJson(id, (value as Map).cast<String, Object?>()),
    );
  });
  return PkmsFileRegistry(files: files);
}

Future<PkmsValidationReport> validatePkms(
  Directory root,
  VaultIndex index,
) async {
  final tags = await loadTagRegistry(root);
  final files = await loadFileRegistry(root);
  final knownTags = tags.tags.keys.toSet();

  var unknownTags = 0;
  for (final note in index.notes) {
    for (final tag in note.tags) {
      if (!knownTags.contains(tag)) unknownTags++;
    }
  }
  for (final file in files.files.values) {
    for (final tag in file.tags) {
      if (!knownTags.contains(tag)) unknownTags++;
    }
  }

  final aliasOwners = <String, Set<String>>{};
  for (final note in index.notes) {
    for (final alias in note.aliases) {
      aliasOwners.putIfAbsent(alias, () => <String>{}).add('note:${note.id}');
    }
  }
  for (final tag in tags.tags.values) {
    for (final alias in tag.aliases) {
      aliasOwners.putIfAbsent(alias, () => <String>{}).add('tag:${tag.slug}');
    }
  }
  final duplicateAliases = aliasOwners.values
      .where((owners) => owners.length > 1)
      .length;

  var missingFiles = 0;
  for (final file in files.files.values) {
    if (file.path.isEmpty) {
      missingFiles++;
      continue;
    }
    final target = File('${root.path}/${file.path}');
    if (!target.existsSync()) missingFiles++;
  }

  return PkmsValidationReport(
    unknownTags: unknownTags,
    duplicateAliases: duplicateAliases,
    missingFiles: missingFiles,
  );
}
