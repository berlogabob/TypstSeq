import 'dart:convert';

import 'package:tylog_core/storage.dart';

import 'settings_path.dart';

const kindsSyncPath = '_system/settings/kinds.json';
typedef KindRegistry = Map<String, dynamic>;

Future<KindRegistry> readKindRegistry(VaultStorage storage) async {
  final path = await settingsPathFor(storage, kindsSyncPath);
  if (!await storage.existsNow(path)) return {};
  final decoded = jsonDecode(utf8.decode(await storage.readBytesNow(path)));
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Kind registry must be a JSON object');
  }
  return decoded;
}

Future<KindRegistry> writeKindRegistryEntry(
  VaultStorage storage,
  String kind, {
  required String icon,
  required String label,
}) async {
  // Read before editing so other kinds and unknown properties survive.
  final registry = await readKindRegistry(storage);
  registry[kind] = {
    if (registry[kind] is Map) ...registry[kind] as Map,
    'icon': icon,
    'label': label,
  };
  await storage.createDirectory('_system/settings');
  await storage.writeText(
    await settingsPathFor(storage, kindsSyncPath),
    const JsonEncoder.withIndent('  ').convert(registry),
  );
  return registry;
}
