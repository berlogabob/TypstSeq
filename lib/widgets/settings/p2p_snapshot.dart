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

/// Create a synthetic source folder for the streamed native harness.
Future<Directory> createScratchFolder(Directory root) async {
  final source = await root.createTemp('p2p-source-');
  for (var i = 0; i < 200; i++) {
    final file = File('${source.path}/notes/note-$i.typ');
    await file.parent.create(recursive: true);
    await file.writeAsString(
      '= Scratch note $i\n${'Synthetic content for transfer measurement.\n' * 20}',
    );
  }
  final asset = File('${source.path}/assets/payload.bin');
  await asset.parent.create(recursive: true);
  await asset.writeAsBytes(
    List.generate(128 * 1024, (i) => (i * 73 + i ~/ 251) % 256),
  );
  return source;
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

Map<String, List<int>> _decodeScratchSnapshot(String snapshot) {
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
  return files;
}

/// Verify each restored file against the validated snapshot.
Future<int> verifyScratchSnapshot(String snapshot, Directory directory) async {
  final files = _decodeScratchSnapshot(snapshot);
  for (final entry in files.entries) {
    final file = File('${directory.path}/${entry.key}');
    if (!await file.exists() ||
        await sha256.bind(file.openRead()).first !=
            sha256.convert(entry.value)) {
      throw const FormatException('Restored file hash mismatch');
    }
  }
  return files.length;
}

/// Validate the entire untrusted manifest before creating a fresh destination.
Future<Directory> restoreScratchSnapshot(
  String snapshot,
  Directory root,
) async {
  final files = _decodeScratchSnapshot(snapshot);
  final destination = await root.createTemp('p2p-snapshot-');
  try {
    for (final entry in files.entries) {
      final file = File('${destination.path}/${entry.key}');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(entry.value);
    }
    await verifyScratchSnapshot(snapshot, destination);
  } catch (_) {
    await destination.delete(recursive: true);
    rethrow;
  }
  return destination;
}

/// Transfer changed files against the deterministic synthetic baseline only.
String createScratchDelta(String baseline, String changed) {
  final original = jsonDecode(baseline) as Map<String, dynamic>;
  final updated = jsonDecode(changed) as Map<String, dynamic>;
  final before = {for (final f in original['files'] as List) f['path']: f};
  final after = updated['files'] as List;
  if (before.length != after.length ||
      after.any((f) => !before.containsKey(f['path']))) {
    throw const FormatException('Scratch baseline paths changed');
  }
  return jsonEncode({
    'version': 1,
    'baselineSha256': sha256.convert(utf8.encode(baseline)).toString(),
    'files': [
      for (final f in after)
        if (f['sha256'] != before[f['path']]['sha256']) f,
    ],
  });
}

Future<String> createChangedScratchDelta(Directory root) async {
  final baseline = await createRepresentativeScratchSnapshot(root);
  final changed = jsonDecode(baseline) as Map<String, dynamic>;
  final first = (changed['files'] as List).first as Map<String, dynamic>;
  final bytes = utf8.encode('= Changed synthetic scratch note\n');
  first['data'] = base64Encode(bytes);
  first['sha256'] = sha256.convert(bytes).toString();
  return createScratchDelta(baseline, jsonEncode(changed));
}

Future<Directory> restoreScratchDelta(String delta, Directory root) async {
  final baseline = await createRepresentativeScratchSnapshot(root);
  final decoded = jsonDecode(delta);
  if (decoded is! Map ||
      decoded['version'] != 1 ||
      decoded['files'] is! List ||
      decoded['baselineSha256'] !=
          sha256.convert(utf8.encode(baseline)).toString()) {
    throw const FormatException('Invalid scratch delta or baseline');
  }
  final snapshot = jsonDecode(baseline) as Map<String, dynamic>;
  final files = snapshot['files'] as List;
  final positions = <String, int>{
    for (var i = 0; i < files.length; i++) files[i]['path'] as String: i,
  };
  final seen = <String>{};
  for (final file in decoded['files'] as List) {
    if (file is! Map ||
        file['path'] is! String ||
        !positions.containsKey(file['path']) ||
        !seen.add(file['path'] as String)) {
      throw const FormatException('Invalid changed file');
    }
    files[positions[file['path']]!] = file;
  }
  return restoreScratchSnapshot(jsonEncode(snapshot), root);
}
