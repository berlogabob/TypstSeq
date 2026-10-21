import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../vault_storage.dart' show userHome;

const _storage = FlutterSecureStorage();

Future<String?> readApiKey(String connectionId) =>
    _storage.read(key: 'ai-key:$connectionId');

Future<void> writeApiKey(String connectionId, String? key) async {
  final value = key?.trim();
  if (value == null || value.isEmpty) {
    await _storage.delete(key: 'ai-key:$connectionId');
  } else {
    await _storage.write(key: 'ai-key:$connectionId', value: value);
  }
  // The Mac's background scripts (screenshots) run without the app and
  // cannot read its keychain items without a prompt; they read this file.
  if (Platform.isMacOS && !Platform.environment.containsKey('FLUTTER_TEST')) {
    await mirrorWorkerKey(connectionId, value);
  }
}

/// Keeps `~/.tylog/keys.json` ({connection id: key}, owner-only, never
/// synced) in step with the keys saved in the app. A null or empty key
/// removes the entry.
Future<void> mirrorWorkerKey(
  String connectionId,
  String? key, {
  String? home,
}) async {
  final dir = home ?? userHome();
  if (dir == null) return;
  final file = File('$dir/.tylog/keys.json');
  var keys = <String, Object?>{};
  try {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is Map) keys = decoded.cast<String, Object?>();
  } catch (_) {}
  if (key == null || key.isEmpty) {
    if (keys.remove(connectionId) == null && !await file.exists()) return;
  } else {
    keys[connectionId] = key;
  }
  await file.parent.create(recursive: true);
  final temp = File('${file.path}.tmp');
  // Owner-only before the key is written into it.
  await temp.writeAsString('');
  await Process.run('chmod', ['600', temp.path]);
  await temp.writeAsString(const JsonEncoder.withIndent('  ').convert(keys));
  await temp.rename(file.path);
}
