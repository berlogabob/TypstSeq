import 'dart:convert';

import 'package:tylog_core/storage.dart';
import 'package:tylog_core/tylog_core.dart' show loadOntology;

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

/// kinds.json over the domain ontologies' classes, for display: a domain kind
/// gets its icon, label and `is_a` without an entry in kinds.json.
Future<KindRegistry> readKindsWithOntology(VaultStorage storage) async {
  final merged = <String, dynamic>{};
  for (final document in [
    ...(await loadOntology(storage)).domains,
    {'classes': await readKindRegistry(storage)},
  ]) {
    final classes = (document as Map)['classes'];
    if (classes is! Map) continue;
    classes.forEach((kind, entry) {
      if (kind is String && entry is Map) {
        merged[kind] = {...?(merged[kind] as Map?), ...entry};
      }
    });
  }
  return merged;
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
