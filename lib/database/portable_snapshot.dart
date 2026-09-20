import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:tylog_core/storage.dart';

import 'tylog_database.dart';

const _portableFormat = 'tylog-portable-snapshot';
const _portableVersion = 1;
const _portableSchemaVersion = 8;
const _manifestPath = 'manifest.json';
const _recordNames = ['sources', 'nodes', 'edges', 'revisions'];

/// A validated, read-only portable snapshot.
class PortableSnapshot {
  const PortableSnapshot({
    required this.schemaVersion,
    required this.entries,
    required this.sources,
    required this.nodes,
    required this.edges,
    required this.revisions,
    required this.vaultFiles,
  });

  final int schemaVersion;
  final Map<String, PortableSnapshotEntry> entries;
  final List<Map<String, Object?>> sources;
  final List<Map<String, Object?>> nodes;
  final List<Map<String, Object?>> edges;
  final List<Map<String, Object?>> revisions;

  /// Vault-relative path to bytes. Derived and transient paths are absent.
  final Map<String, Uint8List> vaultFiles;

  List<Map<String, Object?>> records(String name) => switch (name) {
    'sources' => sources,
    'nodes' => nodes,
    'edges' => edges,
    'revisions' => revisions,
    _ => throw ArgumentError.value(name, 'name', 'unknown record set'),
  };
}

class PortableSnapshotEntry {
  const PortableSnapshotEntry({
    required this.path,
    required this.size,
    required this.sha256,
  });

  final String path;
  final int size;
  final String sha256;
}

/// Serializes the durable graph rows and syncable vault files into a
/// deterministic ZIP. The manifest describes every data entry; it excludes
/// itself because a file cannot contain its own hash.
Future<Uint8List> exportPortableSnapshot({
  required TyLogDatabase database,
  required VaultStorage storage,
}) async {
  // ponytail: archives are assembled in memory; switch to archive streams when
  // measured export memory exceeds the mobile acceptance budget.
  final data = <String, List<int>>{};
  data['records/sources.jsonl'] = _encodeRows(
    (await database.select(database.sources).get()).map(_sourceRow),
  );
  data['records/nodes.jsonl'] = _encodeRows(
    (await database.select(database.nodes).get()).map(_nodeRow),
  );
  data['records/edges.jsonl'] = _encodeRows(
    (await database.select(database.edges).get()).map(_edgeRow),
  );
  data['records/revisions.jsonl'] = _encodeRows(
    (await database.select(database.revisions).get()).map(_revisionRow),
  );

  final files =
      (await storage.list(recursive: true))
          .where(
            (entry) => !entry.isDirectory && !_excludeVaultPath(entry.path),
          )
          .map((entry) => entry.path)
          .toList()
        ..sort();
  final foldedPaths = <String>{};
  for (final path in files) {
    _safePath(path);
    if (!foldedPaths.add(path.toLowerCase())) {
      throw ArgumentError('Vault paths differ only by letter case: $path');
    }
    data['vault/$path'] = await storage.readBytes(path);
  }

  final paths = data.keys.toList()..sort();
  final entries = [
    for (final path in paths)
      {
        'path': path,
        'size': data[path]!.length,
        'sha256': sha256.convert(data[path]!).toString(),
      },
  ];
  final manifest = utf8.encode(
    jsonEncode({
      'format': _portableFormat,
      'version': _portableVersion,
      'schemaVersion': database.schemaVersion,
      'entries': entries,
    }),
  );

  final archive = Archive();
  archive.add(ArchiveFile.bytes(_manifestPath, manifest));
  for (final path in paths) {
    archive.add(ArchiveFile.bytes(path, data[path]!));
  }
  return ZipEncoder().encodeBytes(
    archive,
    level: 6,
    modified: DateTime.utc(1980, 1, 1),
  );
}

/// Decodes and verifies a snapshot before any caller can apply it.
PortableSnapshot parsePortableSnapshot(List<int> bytes) {
  final names = <String>[];
  late final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(
      bytes,
      verify: true,
      callback: (entry) => names.add(entry.name),
    );
  } catch (error) {
    throw FormatException('Invalid portable snapshot ZIP: $error');
  }
  if (names.length != names.toSet().length) {
    throw const FormatException('Portable snapshot contains duplicate entries');
  }
  for (final name in names) {
    _validateEntryPath(name);
  }

  final manifestFile = archive.find(_manifestPath);
  if (manifestFile == null || !manifestFile.isFile) {
    throw const FormatException('Portable snapshot manifest is missing');
  }
  final manifest = _decodeObject(manifestFile.readBytes() ?? const []);
  if (manifest['format'] != _portableFormat ||
      manifest['version'] != _portableVersion ||
      manifest['schemaVersion'] != _portableSchemaVersion) {
    throw const FormatException('Unsupported portable snapshot manifest');
  }

  final rawEntries = manifest['entries'];
  if (rawEntries is! List) {
    throw const FormatException('Portable snapshot manifest has no entries');
  }
  final expected = <String, PortableSnapshotEntry>{};
  final foldedVaultPaths = <String>{};
  for (final raw in rawEntries) {
    if (raw is! Map ||
        raw['path'] is! String ||
        raw['size'] is! int ||
        raw['sha256'] is! String) {
      throw const FormatException('Malformed portable snapshot entry');
    }
    final path = raw['path']! as String;
    _validateEntryPath(path);
    if (path.startsWith('vault/') &&
        !foldedVaultPaths.add(path.substring('vault/'.length).toLowerCase())) {
      throw const FormatException(
        'Portable snapshot contains case-colliding vault paths',
      );
    }
    if (path == _manifestPath || expected.containsKey(path)) {
      throw const FormatException(
        'Duplicate or self-referencing manifest entry',
      );
    }
    final hash = raw['sha256']! as String;
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) {
      throw const FormatException('Malformed portable snapshot hash');
    }
    expected[path] = PortableSnapshotEntry(
      path: path,
      size: raw['size']! as int,
      sha256: hash,
    );
  }

  final actual = <String, ArchiveFile>{};
  for (final entry in archive) {
    if (!entry.isFile) {
      throw FormatException(
        'Portable snapshot contains directory ${entry.name}',
      );
    }
    if (entry.name != _manifestPath) actual[entry.name] = entry;
  }
  if (!_recordNames.every(
    (name) => expected.containsKey('records/$name.jsonl'),
  )) {
    throw const FormatException('Portable snapshot is missing record sets');
  }
  if (actual.length != expected.length ||
      actual.keys.any((path) => !expected.containsKey(path))) {
    throw const FormatException(
      'Portable snapshot entries do not match manifest',
    );
  }

  for (final entry in expected.entries) {
    final content = actual[entry.key]!.readBytes() ?? const <int>[];
    if (content.length != entry.value.size ||
        sha256.convert(content).toString() != entry.value.sha256) {
      throw FormatException(
        'Portable snapshot integrity check failed for ${entry.key}',
      );
    }
  }

  final records = <String, List<Map<String, Object?>>>{};
  for (final name in _recordNames) {
    final content = actual['records/$name.jsonl']!.readBytes()!;
    records[name] = _decodeRows(content);
  }
  final vaultFiles = <String, Uint8List>{};
  for (final entry in actual.entries.where(
    (entry) => entry.key.startsWith('vault/'),
  )) {
    final path = entry.key.substring('vault/'.length);
    vaultFiles[path] = Uint8List.fromList(entry.value.readBytes()!);
  }
  return PortableSnapshot(
    schemaVersion: manifest['schemaVersion']! as int,
    entries: Map.unmodifiable(expected),
    sources: List.unmodifiable(records['sources']!),
    nodes: List.unmodifiable(records['nodes']!),
    edges: List.unmodifiable(records['edges']!),
    revisions: List.unmodifiable(records['revisions']!),
    vaultFiles: Map.unmodifiable(vaultFiles),
  );
}

List<int> _encodeRows(Iterable<Map<String, Object?>> rows) {
  final sorted = rows.toList()
    ..sort((a, b) => _rowKey(a).compareTo(_rowKey(b)));
  return utf8.encode('${sorted.map(jsonEncode).join('\n')}\n');
}

List<Map<String, Object?>> _decodeRows(List<int> bytes) {
  final text = utf8.decode(bytes);
  if (!text.endsWith('\n')) {
    throw const FormatException('Record set must end with a newline');
  }
  final lines = text.trimRight().split('\n');
  if (lines.length == 1 && lines.single.isEmpty) return [];
  return [for (final line in lines) _decodeObject(utf8.encode(line))];
}

Map<String, Object?> _decodeObject(List<int> bytes) {
  final value = jsonDecode(utf8.decode(bytes));
  if (value is! Map) throw const FormatException('Expected a JSON object');
  return value.cast<String, Object?>();
}

String _rowKey(Map<String, Object?> row) =>
    '${row['id'] ?? ''}\u0000${row['entityKind'] ?? ''}\u0000${row['entityId'] ?? ''}';

Map<String, Object?> _sourceRow(SourceData row) => {
  'id': row.id,
  'kind': row.kind,
  'title': row.title,
  'locator': row.locator,
  'attributesJson': row.attributesJson,
  'createdAtMs': row.createdAtMs,
  'updatedAtMs': row.updatedAtMs,
};

Map<String, Object?> _nodeRow(NodeData row) => {
  'id': row.id,
  'type': row.type,
  'title': row.title,
  'content': row.content,
  'attributesJson': row.attributesJson,
  'eventStartMs': row.eventStartMs,
  'eventEndMs': row.eventEndMs,
  'createdAtMs': row.createdAtMs,
  'updatedAtMs': row.updatedAtMs,
};

Map<String, Object?> _edgeRow(EdgeData row) => {
  'id': row.id,
  'fromNodeId': row.fromNodeId,
  'toNodeId': row.toNodeId,
  'type': row.type,
  'attributesJson': row.attributesJson,
  'validFromMs': row.validFromMs,
  'validToMs': row.validToMs,
  'createdAtMs': row.createdAtMs,
  'updatedAtMs': row.updatedAtMs,
};

Map<String, Object?> _revisionRow(RevisionData row) => {
  'id': row.id,
  'entityKind': row.entityKind,
  'entityId': row.entityId,
  'parentRevisionId': row.parentRevisionId,
  'payloadJson': row.payloadJson,
  'createdAtMs': row.createdAtMs,
};

void _safePath(String path) {
  if (path.isEmpty || path.contains('\n') || path.contains('\r')) {
    throw ArgumentError.value(path, 'path', 'must be a safe vault path');
  }
  validateVaultPath(path);
}

void _validateEntryPath(String path) {
  if (path == _manifestPath) return;
  if (path.startsWith('records/')) {
    if (!RegExp(
      r'^records/(sources|nodes|edges|revisions)\.jsonl$',
    ).hasMatch(path)) {
      throw FormatException('Unsupported record path $path');
    }
    return;
  }
  if (path.startsWith('vault/')) {
    _safePath(path.substring('vault/'.length));
    return;
  }
  throw FormatException('Unsupported portable snapshot path $path');
}

bool _excludeVaultPath(String path) {
  return path == '_index' ||
      path.startsWith('_index/') ||
      path == '.tylog' ||
      path.startsWith('.tylog/') ||
      path.endsWith('.tmp') ||
      path.endsWith('.db-wal') ||
      path.endsWith('.db-shm');
}
