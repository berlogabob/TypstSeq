import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:tylog_core/tylog_core.dart' show Mount;

import 'github_client.dart';

class MountFetcher {
  MountFetcher({
    required this.cache,
    required this.client,
    required this.reload,
  });
  final Directory cache;
  final GitHubClient client;
  final Future<void> Function() reload;
  final Map<String, Future<void>> _flights = {};
  final Map<String, DateTime> _attempts = {};

  Future<Map<String, dynamic>?> metadata(Mount mount) async {
    try {
      return jsonDecode(
            await File(
              '${cache.path}/${mount.id}/.tylog-mount.json',
            ).readAsString(),
          )
          as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> refresh(Mount mount, {bool automatic = false}) {
    return _flights.putIfAbsent(mount.id, () {
      final future = _refresh(mount, automatic);
      future.whenComplete(() => _flights.remove(mount.id)).ignore();
      return future;
    });
  }

  Future<void> _refresh(Mount mount, bool automatic) async {
    if (mount.source.kind != 'github') return;
    final meta = await metadata(mount);
    final fetched =
        _attempts[mount.id] ??
        DateTime.tryParse(meta?['fetchedAt']?.toString() ?? '');
    if (automatic &&
        fetched != null &&
        DateTime.now().difference(fetched) < const Duration(hours: 6)) {
      return;
    }
    _attempts[mount.id] = DateTime.now();
    final repo = mount.source.repo!;
    final ref = mount.source.ref!;
    final sha = await client.commitSha(repo, ref);
    if (sha == meta?['sha'] && meta?['blobs'] is Map) {
      await File('${cache.path}/${mount.id}/.tylog-mount.json').writeAsString(
        jsonEncode({
          ...?meta,
          'sha': sha,
          'fetchedAt': DateTime.now().toUtc().toIso8601String(),
        }),
      );
      return;
    }
    final zip = await client.downloadZipball(repo, sha);
    final tmp = Directory('${cache.path}/${mount.id}.tmp');
    final target = Directory('${cache.path}/${mount.id}');
    final backup = Directory('${cache.path}/${mount.id}.old');
    await cache.create(recursive: true);
    if (await tmp.exists()) await tmp.delete(recursive: true);
    try {
      await tmp.create();
      final blobs = await Isolate.run(
        () => _extract(zip, tmp.path, mount.source.subdir),
      );
      await File('${tmp.path}/.tylog-mount.json').writeAsString(
        jsonEncode({
          'sha': sha,
          'fetchedAt': DateTime.now().toUtc().toIso8601String(),
          'blobs': blobs,
        }),
      );
      if (await backup.exists()) await backup.delete(recursive: true);
      final hadOld = await target.exists();
      if (hadOld) await target.rename(backup.path);
      try {
        await tmp.rename(target.path);
      } catch (_) {
        if (hadOld) await backup.rename(target.path);
        rethrow;
      }
      if (hadOld) await backup.delete(recursive: true);
      await reload();
    } finally {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    }
  }
}

Map<String, String> _extract(
  Uint8List bytes,
  String destination,
  String? subdir,
) {
  final blobs = <String, String>{};
  final prefix = (subdir ?? '').split('/').where((s) => s.isNotEmpty).toList();
  if (prefix.any((s) => s == '.' || s == '..' || s.contains('\\'))) {
    throw const FormatException('Invalid subdirectory');
  }
  var total = 0;
  for (final entry in ZipDecoder().decodeBytes(bytes, verify: true)) {
    final name = entry.name;
    final parts = name.split('/');
    if (name.startsWith('/') ||
        name.contains('\\') ||
        parts.any((s) => s == '..' || s == '.') ||
        RegExp(r'^[A-Za-z]:').hasMatch(name) ||
        entry.isSymbolicLink) {
      throw const FormatException('Unsafe zip entry');
    }
    if (!entry.isFile || parts.length < 2) continue;
    final relative = parts.sublist(1);
    if (relative.length <= prefix.length ||
        !List.generate(
          prefix.length,
          (i) => relative[i] == prefix[i],
        ).every((v) => v)) {
      continue;
    }
    if (entry.size > 20 * 1024 * 1024) continue;
    total += entry.size;
    if (total > 500 * 1024 * 1024) {
      throw const FormatException('Archive exceeds size limit');
    }
    final path = relative.skip(prefix.length).join('/');
    final file = File('$destination/$path');
    file.parent.createSync(recursive: true);
    final content = entry.content;
    if (content.length != entry.size) {
      throw const FormatException('Invalid archive entry size');
    }
    file.writeAsBytesSync(content);
    blobs[path] = sha1.convert([
      ...utf8.encode('blob ${content.length}\u0000'),
      ...content,
    ]).toString();
  }
  return blobs;
}
