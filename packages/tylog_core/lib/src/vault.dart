import 'dart:convert';

import 'scanner.dart';
import 'storage.dart';

abstract final class TylogVaultPaths {
  static const index = '_index/index.json';
  static const searchIndex = '_index/search-index.json.gz';
  static const helper = '_system/tylog.typ';
  static const theme = '_system/theme.typ';
  static const export = '_system/export.typ';
  static const bibliography = '_system/bibliography.yml';
  static const settings = '.tylog/settings.json';

  static const directories = [
    'daily',
    'notes',
    'projects',
    'articles',
    'assets',
    'outputs',
    '_system',
    '_index',
    '.tylog',
    '.tylog/conflicts',
    '_system/templates',
  ];
}

Future<void> initializeVaultStorage(
  VaultStorage storage, {
  required Map<String, List<int>> managedFiles,
  required String currentHelper,
  required String legacyHelper,
  bool createIfMissing = true,
}) async {
  final hasSettings = await storage.exists(TylogVaultPaths.settings);
  if (!hasSettings) {
    if (await _hasLegacyContent(storage)) {
      throw StateError(
        'This is not a TyLog v5 vault. Choose an empty folder; automatic migration is intentionally unsupported.',
      );
    }
    if (!createIfMissing) {
      throw StateError(
        'TyLog vault marker is missing. Reselect the existing vault folder.',
      );
    }
  }
  if (!hasSettings) {
    for (final path in TylogVaultPaths.directories) {
      await storage.createDirectory(path);
    }
    await storage.writeText(
      TylogVaultPaths.settings,
      jsonEncode({'name': 'TyLogVault', 'version': 5}),
    );
  } else {
    final settings =
        jsonDecode(await storage.readText(TylogVaultPaths.settings)) as Map;
    if (settings['version'] != 5) {
      throw StateError(
        'This vault uses schema ${settings['version']}; TyLog requires a v5 vault.',
      );
    }
  }

  if (!await storage.exists(TylogVaultPaths.helper)) {
    await storage.writeBytes(
      TylogVaultPaths.helper,
      managedFiles[TylogVaultPaths.helper]!,
    );
  } else if (classifyTylogHelper(
        await storage.readText(TylogVaultPaths.helper),
        current: currentHelper,
        legacy: legacyHelper,
      ) ==
      TylogHelperKind.legacy) {
    await storage.writeBytes(
      TylogVaultPaths.helper,
      managedFiles[TylogVaultPaths.helper]!,
    );
  }
  for (final path in [TylogVaultPaths.theme, TylogVaultPaths.export]) {
    if (!await storage.exists(path)) {
      await storage.writeBytes(path, managedFiles[path]!);
    }
  }
  for (final entry in managedFiles.entries) {
    if (!entry.key.startsWith('_system/packages/')) continue;
    if (!await storage.exists(entry.key) ||
        !_sameBytes(await storage.readBytes(entry.key), entry.value)) {
      await storage.writeBytes(entry.key, entry.value);
    }
  }
  if (!await storage.exists(TylogVaultPaths.bibliography)) {
    await storage.writeText(TylogVaultPaths.bibliography, '{}\n');
  }
}

Future<bool> _hasLegacyContent(VaultStorage storage) async {
  for (final entry in await storage.list()) {
    final name = entry.path.split('/').last;
    if (name == '.DS_Store') continue;
    if (name == '.tylog' && entry.isDirectory) {
      if ((await storage.list(path: '.tylog')).isNotEmpty) return true;
      continue;
    }
    return true;
  }
  return false;
}

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}
