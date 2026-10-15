import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'scanner.dart' show locateTypstCalls, taskField;
import 'storage.dart';
import 'validation.dart' show isSafeVaultPath;

/// A data-only content pack (`*.tylogpack`, a zip): `manifest.json`, notes
/// under `notes/`, files under `assets/`. Nothing in a pack executes.
///
/// Install targets sit inside synced vault prefixes (a new top-level dir would
/// silently not sync): `notes/x` -> `projects/<id>/x`, `assets/x` ->
/// `assets/modules/<id>/x`. Notes may use these tokens, replaced at install:
/// `{{id}}` (the pack id) and `{{due:N}}` (start date + N days, ISO).
class ModulePack {
  ModulePack._(this.id, this.name, this.version, this.files);

  final String id;
  final String name;
  final String version;

  /// Pack-relative path -> bytes, already hash-verified.
  final Map<String, Uint8List> files;

  static final _idPattern = RegExp(r'^[a-z0-9][a-z0-9-]{0,63}$');

  /// [archive] maps zip entry names to bytes. Throws [FormatException].
  factory ModulePack.parse(Map<String, Uint8List> archive) {
    final raw = archive['manifest.json'];
    if (raw == null) throw const FormatException('manifest.json is missing');
    final Object? manifest;
    try {
      manifest = jsonDecode(utf8.decode(raw));
    } on FormatException catch (e) {
      throw FormatException('manifest.json is not valid JSON: ${e.message}');
    }
    if (manifest is! Map || manifest['schema'] != 1) {
      throw const FormatException('Unsupported pack schema');
    }
    final id = manifest['id'];
    if (id is! String || !_idPattern.hasMatch(id)) {
      throw const FormatException('Pack id must match [a-z0-9-]');
    }
    final listed = manifest['files'];
    if (listed is! List) throw const FormatException('files must be a list');
    final files = <String, Uint8List>{};
    for (final entry in listed) {
      if (entry is! Map ||
          entry['path'] is! String ||
          entry['sha256'] is! String) {
        throw const FormatException('Each file needs path and sha256');
      }
      final path = entry['path'] as String;
      if (!isSafeVaultPath(path) ||
          !(path.startsWith('notes/') || path.startsWith('assets/'))) {
        throw FormatException('Unsafe or unsupported pack path: $path');
      }
      final bytes = archive[path];
      if (bytes == null) throw FormatException('Listed file missing: $path');
      if (sha256.convert(bytes).toString() != entry['sha256']) {
        throw FormatException('Hash mismatch: $path');
      }
      files[path] = bytes;
    }
    final unlisted = archive.keys.where(
      (k) => k != 'manifest.json' && !files.containsKey(k) && !k.endsWith('/'),
    );
    if (unlisted.isNotEmpty) {
      throw FormatException('Unlisted file in pack: ${unlisted.first}');
    }
    return ModulePack._(
      id,
      (manifest['name'] as String?) ?? id,
      (manifest['version'] as String?) ?? '0',
      files,
    );
  }

  String targetOf(String packPath) => packPath.startsWith('notes/')
      ? 'projects/$id/${packPath.substring(6)}'
      : 'assets/modules/$id/${packPath.substring(7)}';

  /// Installed bytes: notes get tokens resolved; other files are verbatim.
  Uint8List render(String packPath, DateTime start) {
    final bytes = files[packPath]!;
    if (!packPath.startsWith('notes/') || !packPath.endsWith('.typ')) {
      return bytes;
    }
    final text = utf8
        .decode(bytes)
        .replaceAll('{{id}}', id)
        .replaceAllMapped(RegExp(r'\{\{due:(\d+)\}\}'), (m) {
          final d = DateTime.utc(
            start.year,
            start.month,
            start.day + int.parse(m[1]!),
          );
          return _iso(d);
        });
    return Uint8List.fromList(utf8.encode(text));
  }
}

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class ModuleInstallResult {
  const ModuleInstallResult({required this.written, required this.skipped});

  /// Vault paths written or deleted.
  final List<String> written;

  /// Vault paths left alone: the user edited them, or they pre-existed
  /// without belonging to this pack.
  final List<String> skipped;
}

String moduleRecordPath(String id) => '_system/modules/$id.json';

class InstalledModule {
  const InstalledModule({required this.id, required this.name, this.start});

  final String id;
  final String name;
  final DateTime? start;
}

/// Lists installed records, including older records without a name or start.
Future<List<InstalledModule>> listInstalledModules(VaultStorage storage) async {
  final modules = <InstalledModule>[];
  for (final entry in await storage.list(path: '_system/modules')) {
    if (entry.isDirectory || !entry.path.endsWith('.json')) continue;
    final id = entry.path.split('/').last.replaceFirst(RegExp(r'\.json$'), '');
    if (!ModulePack._idPattern.hasMatch(id)) continue;
    final record = jsonDecode(await storage.readText(entry.path)) as Map;
    modules.add(
      InstalledModule(
        id: id,
        name: (record['name'] as String?) ?? id,
        start: DateTime.tryParse((record['start'] as String?) ?? ''),
      ),
    );
  }
  modules.sort((a, b) => a.id.compareTo(b.id));
  return modules;
}

Future<Map<String, String>> _readRecord(VaultStorage s, String id) async {
  final path = moduleRecordPath(id);
  if (!await s.exists(path)) return {};
  final json = jsonDecode(await s.readText(path)) as Map;
  return {
    for (final e in (json['files'] as Map).entries)
      e.key as String: e.value as String,
  };
}

/// Idempotent: reinstalling rewrites only files still byte-identical to what
/// this module installed (so upgrades never clobber user edits) and creates
/// missing ones. A pre-existing file the module did not install is never
/// overwritten.
Future<ModuleInstallResult> installModule(
  VaultStorage storage,
  ModulePack pack,
  DateTime start,
) async {
  final owned = await _readRecord(storage, pack.id);
  final installed = <String, String>{};
  final written = <String>[];
  final skipped = <String>[];
  final targets = pack.files.keys.map(pack.targetOf).toSet();
  for (final entry in owned.entries) {
    if (targets.contains(entry.key) || !await storage.exists(entry.key)) {
      continue;
    }
    if (await storage.hash(entry.key) == entry.value) {
      await storage.delete(entry.key);
      written.add(entry.key);
    } else {
      skipped.add(entry.key);
    }
  }
  for (final packPath in pack.files.keys) {
    final target = pack.targetOf(packPath);
    final bytes = pack.render(packPath, start);
    final digest = sha256.convert(bytes).toString();
    if (await storage.exists(target)) {
      final current = await storage.hash(target);
      if (current == digest) {
        installed[target] = digest;
        continue;
      }
      if (owned[target] != current) {
        skipped.add(target);
        if (owned.containsKey(target)) installed[target] = owned[target]!;
        continue;
      }
    }
    await storage.writeBytes(target, bytes);
    installed[target] = digest;
    written.add(target);
  }
  await storage.writeText(
    moduleRecordPath(pack.id),
    jsonEncode({
      'id': pack.id,
      'name': pack.name,
      'version': pack.version,
      'start': _iso(start),
      'files': installed,
    }),
  );
  return ModuleInstallResult(written: written, skipped: skipped);
}

/// Deletes only files still identical to what was installed.
Future<ModuleInstallResult> uninstallModule(
  VaultStorage storage,
  String id,
) async {
  final owned = await _readRecord(storage, id);
  final written = <String>[];
  final skipped = <String>[];
  for (final entry in owned.entries) {
    if (!await storage.exists(entry.key)) continue;
    if (await storage.hash(entry.key) == entry.value) {
      await storage.delete(entry.key);
      written.add(entry.key);
    } else {
      skipped.add(entry.key);
    }
  }
  if (await storage.exists(moduleRecordPath(id))) {
    await storage.delete(moduleRecordPath(id));
  }
  return ModuleInstallResult(written: written, skipped: skipped);
}

/// Shifts open-task due dates in owned notes, including user-edited notes.
/// Only date literals change; the resulting bytes become the recorded version.
Future<ModuleInstallResult> rescheduleModule(
  VaultStorage storage,
  String id,
  DateTime newStart,
  DateTime oldStart,
) async {
  final recordPath = moduleRecordPath(id);
  if (!await storage.exists(recordPath)) {
    return const ModuleInstallResult(written: [], skipped: []);
  }
  final record = jsonDecode(await storage.readText(recordPath)) as Map;
  final owned = (record['files'] as Map).cast<String, String>();
  final days = DateTime.utc(newStart.year, newStart.month, newStart.day)
      .difference(DateTime.utc(oldStart.year, oldStart.month, oldStart.day))
      .inDays;
  final written = <String>[];
  for (final path in owned.keys) {
    if (!path.startsWith('projects/$id/') ||
        !path.endsWith('.typ') ||
        !await storage.exists(path)) {
      continue;
    }
    final source = await storage.readText(path);
    var next = source;
    for (final call in locateTypstCalls(
      source,
      names: const {'tylog.task'},
    ).reversed) {
      final status = taskField(call.source, 'status');
      if (status == 'done' || status == 'cancelled') continue;
      final due = taskField(call.source, 'due');
      if (due == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(due)) {
        continue;
      }
      final date = DateTime.tryParse(due);
      if (date == null || _iso(date) != due) continue;
      final shifted = _iso(
        DateTime.utc(date.year, date.month, date.day + days),
      );
      // Probe candidates through the scanner to avoid strings/comments/nested fields.
      for (final match in RegExp('"$due"').allMatches(call.source)) {
        final probe = call.source.replaceRange(
          match.start,
          match.end,
          '"_due_"',
        );
        if (taskField(probe, 'due') != '_due_') continue;
        next = next.replaceRange(
          call.start + match.start,
          call.start + match.end,
          '"$shifted"',
        );
        break;
      }
    }
    if (next == source) continue;
    await storage.writeText(path, next);
    owned[path] = sha256.convert(utf8.encode(next)).toString();
    written.add(path);
  }
  record['start'] = _iso(newStart);
  await storage.writeText(recordPath, jsonEncode(record));
  return ModuleInstallResult(written: written, skipped: []);
}

class ModuleProgress {
  const ModuleProgress({
    required this.total,
    required this.done,
    required this.scores,
  });

  final int total;
  final int done;
  final List<({String path, String score})> scores;
}

/// Reads current progress from all notes under the module's project directory.
Future<ModuleProgress> moduleProgress(VaultStorage storage, String id) async {
  var total = 0;
  var done = 0;
  final scores = <({String path, String score})>[];
  // Owned files from the install record: a recursive vault listing is far
  // too slow on a large SAF vault.
  final owned = await _readRecord(storage, id);
  for (final path in owned.keys) {
    if (!path.startsWith('projects/$id/') ||
        !path.endsWith('.typ') ||
        !await storage.exists(path)) {
      continue;
    }
    final source = await storage.readText(path);
    for (final call in locateTypstCalls(source, names: const {'tylog.task'})) {
      total++;
      if (taskField(call.source, 'status') == 'done') done++;
    }
    for (final match in RegExp(
      r'^\s*score::[ \t]*(\d+[ \t]*/[ \t]*\d+)[ \t]*$',
      multiLine: true,
    ).allMatches(source)) {
      scores.add((path: path, score: match[1]!));
    }
  }
  return ModuleProgress(total: total, done: done, scores: scores);
}
