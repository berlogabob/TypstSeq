import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// A synthetic fixture: this experiment never reads an existing vault.
String createScratchSnapshot() {
  final files = <String, List<int>>{
    'notes/welcome.typ': utf8.encode(
      '= P2P scratch vault\nThis is synthetic test data.\n',
    ),
    'assets/sample.bin': [0, 1, 2, 255],
    'assets/payload.bin': List.generate(
      128 * 1024,
      (i) => (i * 73 + i ~/ 251) % 256,
    ),
  };
  return jsonEncode({
    'version': 1,
    'files': [
      for (final entry in files.entries)
        {
          'path': entry.key,
          'sha256': sha256.convert(entry.value).toString(),
          'data': base64Encode(entry.value),
        },
    ],
  });
}

/// Generate and read a disposable folder; no existing folder is opened.
Future<String> createRepresentativeScratchSnapshot(Directory root) async {
  final source = await root.createTemp('p2p-source-');
  try {
    final files = <String, List<int>>{
      for (var i = 0; i < 200; i++)
        'notes/note-$i.typ': utf8.encode(
          '= Scratch note $i\n${'Synthetic content for transfer measurement.\n' * 20}',
        ),
      'assets/sample.bin': [0, 1, 2, 255],
      'assets/payload.bin': List.generate(
        128 * 1024,
        (i) => (i * 73 + i ~/ 251) % 256,
      ),
    };
    final entries = <Map<String, String>>[];
    for (final entry in files.entries) {
      final file = File('${source.path}/${entry.key}');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(entry.value);
      final bytes = await file.readAsBytes();
      entries.add({
        'path': entry.key,
        'sha256': sha256.convert(bytes).toString(),
        'data': base64Encode(bytes),
      });
    }
    return jsonEncode({'version': 1, 'files': entries});
  } finally {
    await source.delete(recursive: true);
  }
}

/// Validate the entire untrusted manifest before creating a fresh destination.
Future<Directory> restoreScratchSnapshot(
  String snapshot,
  Directory root,
) async {
  final decoded = jsonDecode(snapshot);
  if (decoded is! Map || decoded['version'] != 1 || decoded['files'] is! List) {
    throw const FormatException('Invalid snapshot');
  }
  final files = <String, List<int>>{};
  for (final item in decoded['files'] as List) {
    if (item is! Map ||
        item['path'] is! String ||
        item['data'] is! String ||
        item['sha256'] is! String) {
      throw const FormatException('Invalid file');
    }
    final path = item['path'] as String;
    if (path.isEmpty ||
        path.contains('\\') ||
        path
            .split('/')
            .any((part) => part.isEmpty || part == '.' || part == '..') ||
        files.containsKey(path)) {
      throw const FormatException('Unsafe or duplicate path');
    }
    final bytes = base64Decode(item['data'] as String);
    if (sha256.convert(bytes).toString() != item['sha256']) {
      throw const FormatException('Snapshot hash mismatch');
    }
    files[path] = bytes;
  }
  final destination = await root.createTemp('p2p-snapshot-');
  try {
    for (final entry in files.entries) {
      final file = File('${destination.path}/${entry.key}');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(entry.value);
    }
  } catch (_) {
    await destination.delete(recursive: true);
    rethrow;
  }
  return destination;
}
