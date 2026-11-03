import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:tylog_core/tylog_core.dart' show Mount;
import 'package:crypto/crypto.dart';

import 'github_client.dart';

class GitHubOutboxEntry {
  GitHubOutboxEntry({
    required this.id,
    required this.mountId,
    required this.path,
    required this.baseSha,
    required this.message,
    required this.at,
    required this.device,
    this.state = 'pending',
  });

  final String id, mountId, path, message, device;
  final String? baseSha;
  final DateTime at;
  final String state;

  factory GitHubOutboxEntry.fromJson(Map<String, dynamic> json) =>
      GitHubOutboxEntry(
        id: json['id'] as String,
        mountId: json['mountId'] as String,
        path: json['path'] as String,
        baseSha: json['baseSha'] as String?,
        message: json['message'] as String,
        at: DateTime.parse(json['at'] as String),
        device: json['device'] as String,
        state: json['state'] as String,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'mountId': mountId,
    'path': path,
    'baseSha': baseSha,
    'message': message,
    'at': at.toUtc().toIso8601String(),
    'device': device,
    'state': state,
  };
}

class GitHubOutbox {
  GitHubOutbox(this.dir);
  final Directory dir;

  File _entryFile(GitHubOutboxEntry entry) =>
      File('${dir.path}/${entry.mountId}/${entry.id}.json');

  Future<GitHubOutboxEntry> enqueue({
    required String mountId,
    required String path,
    required String? baseSha,
    required String message,
    required String device,
    DateTime? at,
  }) async {
    _validatePath(path);
    if (!RegExp(r'^[a-z0-9][a-z0-9-]{0,40}$').hasMatch(mountId)) {
      throw const FormatException('Invalid mount id');
    }
    final existing = (await entriesFor(
      mountId,
    )).where((entry) => entry.path == path);
    if (existing.isNotEmpty) return existing.first;
    final entry = GitHubOutboxEntry(
      id: List.generate(
        16,
        (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join(),
      mountId: mountId,
      path: path,
      baseSha: baseSha,
      message: message,
      at: at ?? DateTime.now().toUtc(),
      device: device,
    );
    await _save(entry);
    return entry;
  }

  Future<void> _save(GitHubOutboxEntry entry) async {
    final file = _entryFile(entry);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(entry.toJson()), flush: true);
  }

  Future<List<GitHubOutboxEntry>> entriesFor(String mountId) async {
    final folder = Directory('${dir.path}/$mountId');
    if (!await folder.exists()) return [];
    final entries = <GitHubOutboxEntry>[];
    await for (final file in folder.list()) {
      if (file is File && file.path.endsWith('.json')) {
        entries.add(
          GitHubOutboxEntry.fromJson(
            jsonDecode(await file.readAsString()) as Map<String, dynamic>,
          ),
        );
      }
    }
    entries.sort((a, b) {
      final order = a.at.compareTo(b.at);
      return order != 0 ? order : a.id.compareTo(b.id);
    });
    return entries;
  }

  Future<void> pushAll(GitHubClient client, Mount mount, File cacheMeta) async {
    final blocked = <String>{};
    for (final entry in await entriesFor(mount.id)) {
      if (entry.state == 'conflict') blocked.add(entry.path);
      if (blocked.contains(entry.path)) continue;
      if (!await _push(client, mount, cacheMeta, entry, entry.baseSha)) {
        blocked.add(entry.path);
      }
    }
  }

  Future<void> keepMine(
    GitHubOutboxEntry entry,
    GitHubClient client,
    Mount mount,
    File cacheMeta,
  ) async {
    final remote = await client.getContent(
      mount.source.repo!,
      _remotePath(mount, entry.path),
      mount.source.ref!,
    );
    await _push(client, mount, cacheMeta, entry, remote.sha);
  }

  Future<void> takeTheirs(GitHubOutboxEntry entry, File cacheMeta) async {
    final local = _localFile(cacheMeta, entry.path);
    final remote = _remoteFile(local);
    final bytes = await remote.readAsBytes();
    await local.writeAsBytes(bytes, flush: true);
    final meta =
        jsonDecode(await cacheMeta.readAsString()) as Map<String, dynamic>;
    final blobs = Map<String, dynamic>.from(meta['blobs'] as Map);
    blobs[entry.path] = sha1.convert([
      ...utf8.encode('blob ${bytes.length}\u0000'),
      ...bytes,
    ]).toString();
    meta['blobs'] = blobs;
    await cacheMeta.writeAsString(jsonEncode(meta), flush: true);
    await _entryFile(entry).delete();
    await remote.delete();
  }

  Future<bool> _push(
    GitHubClient client,
    Mount mount,
    File cacheMeta,
    GitHubOutboxEntry entry,
    String? sha,
  ) async {
    final local = _localFile(cacheMeta, entry.path);
    final remotePath = _remotePath(mount, entry.path);
    try {
      final newSha = await client.putContent(
        mount.source.repo!,
        remotePath,
        await local.readAsBytes(),
        entry.message,
        sha: sha,
        branch: mount.source.ref!,
      );
      final meta =
          jsonDecode(await cacheMeta.readAsString()) as Map<String, dynamic>;
      final blobs = Map<String, dynamic>.from(meta['blobs'] as Map);
      blobs[entry.path] = newSha;
      meta['blobs'] = blobs;
      await cacheMeta.writeAsString(jsonEncode(meta), flush: true);
      await _entryFile(entry).delete();
      final remote = _remoteFile(local);
      if (await remote.exists()) await remote.delete();
      return true;
    } on GitHubConflict {
      final remote = await client.getContent(
        mount.source.repo!,
        remotePath,
        mount.source.ref!,
      );
      await _remoteFile(local).writeAsBytes(remote.bytes, flush: true);
      final json = entry.toJson()..['state'] = 'conflict';
      await _save(GitHubOutboxEntry.fromJson(json));
      return false;
    }
  }

  File _localFile(File meta, String path) {
    _validatePath(path);
    return File('${meta.parent.path}/$path');
  }

  File _remoteFile(File local) {
    final name = local.path;
    final slash = name.lastIndexOf('/');
    final dot = name.lastIndexOf('.');
    return File(
      dot > slash + 1
          ? '${name.substring(0, dot)}.remote${name.substring(dot)}'
          : '$name.remote',
    );
  }

  String _remotePath(Mount mount, String path) {
    _validatePath(path);
    final subdir = mount.source.subdir;
    if (subdir == null || subdir.isEmpty) return path;
    final prefix = subdir.split('/').where((part) => part.isNotEmpty).join('/');
    if (prefix.isEmpty) return path;
    _validatePath(prefix);
    return '$prefix/$path';
  }
}

void _validatePath(String path) {
  if (path.isEmpty ||
      path.startsWith('/') ||
      path.contains('\\') ||
      path
          .split('/')
          .any((part) => part.isEmpty || part == '.' || part == '..') ||
      RegExp(r'^[A-Za-z]:').hasMatch(path)) {
    throw const FormatException('Invalid path');
  }
}
