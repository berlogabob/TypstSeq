import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:tylog_core/storage.dart';

enum LegacyImportDialect { logseq, obsidian }

enum LegacyImportEntryKind { page, journal, asset, unsupported }

class LegacyImportEntry {
  const LegacyImportEntry({
    required this.path,
    required this.kind,
    required this.size,
    required this.modifiedMs,
  });

  final String path;
  final LegacyImportEntryKind kind;
  final int? size;
  final int? modifiedMs;
}

class LegacyImportManifest {
  const LegacyImportManifest({
    required this.dialect,
    required this.entries,
    required this.fingerprint,
  });

  final LegacyImportDialect dialect;
  final List<LegacyImportEntry> entries;
  final String fingerprint;
}

Future<LegacyImportManifest> buildLegacyImportManifest(
  VaultStorage storage,
  LegacyImportDialect dialect,
) async {
  final byPath = <String, LegacyImportEntry>{};
  for (final raw in await storage.list(recursive: true)) {
    if (raw.isDirectory) continue;
    final path = _normalizePath(raw.path);
    if (byPath.containsKey(path)) {
      throw StateError('duplicate normalized vault path');
    }
    byPath[path] = LegacyImportEntry(
      path: path,
      kind: _classify(path, dialect),
      size: raw.size,
      modifiedMs: raw.modified?.millisecondsSinceEpoch,
    );
  }
  final entries = byPath.values.toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  final canonical = StringBuffer('${dialect.name}\n');
  for (final entry in entries) {
    final fields = [
      entry.path,
      entry.kind.name,
      entry.size?.toString() ?? '',
      entry.modifiedMs?.toString() ?? '',
    ];
    for (final field in fields) {
      final bytes = utf8.encode(field);
      canonical
        ..write(bytes.length)
        ..write(':')
        ..write(field);
    }
    canonical.write('\n');
  }
  return LegacyImportManifest(
    dialect: dialect,
    entries: List.unmodifiable(entries),
    fingerprint: sha256.convert(utf8.encode(canonical.toString())).toString(),
  );
}

String _normalizePath(String raw) {
  final path = raw;
  validateVaultPath(path);
  if (path.split('/').any((part) => part.isEmpty || part == '.')) {
    throw ArgumentError.value(raw, 'path', 'must be normalized and safe');
  }
  return path;
}

LegacyImportEntryKind _classify(String path, LegacyImportDialect dialect) {
  final lower = path.toLowerCase();
  if (path.split('/').any((part) => part.startsWith('.'))) {
    return LegacyImportEntryKind.unsupported;
  }
  if (dialect == LegacyImportDialect.logseq &&
      lower.startsWith('journals/') &&
      lower.endsWith('.md')) {
    return LegacyImportEntryKind.journal;
  }
  if (dialect == LegacyImportDialect.logseq &&
      lower.startsWith('pages/') &&
      lower.endsWith('.md')) {
    return LegacyImportEntryKind.page;
  }
  if (lower.startsWith('assets/') || lower.startsWith('attachments/')) {
    return LegacyImportEntryKind.asset;
  }
  if (dialect == LegacyImportDialect.obsidian && lower.endsWith('.md')) {
    return LegacyImportEntryKind.page;
  }
  return LegacyImportEntryKind.unsupported;
}
