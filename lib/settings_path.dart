import 'dart:typed_data';

import 'package:tylog_core/storage.dart';

String localSettingsPath(String sharedPath) =>
    sharedPath.replaceFirst(RegExp(r'\.json$'), '.local.json');

Future<String> settingsPathFor(VaultStorage storage, String sharedPath) async {
  final localPath = localSettingsPath(sharedPath);
  return await storage.existsNow(localPath) ? localPath : sharedPath;
}

/// Copy whole files, preserving unknown keys and the shared copy when enabled.
Future<void> setSettingsDeviceOnly(
  VaultStorage storage,
  String sharedPath,
  bool enabled,
) async {
  final activePath = await settingsPathFor(storage, sharedPath);
  final localPath = localSettingsPath(sharedPath);
  if ((activePath == localPath) == enabled) return;
  final bytes = await storage.existsNow(activePath)
      ? await storage.readBytesNow(activePath)
      : Uint8List.fromList('{}'.codeUnits);
  await storage.createDirectory('_system/settings');
  await storage.writeBytes(enabled ? localPath : sharedPath, bytes);
  if (!enabled) await storage.delete(localPath);
}
