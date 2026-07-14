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

enum VaultStorageKind { empty, validVault, nonVault, incompatibleVault }

class VaultStorageInspection {
  const VaultStorageInspection(this.kind, {this.entryCount = 0});

  final VaultStorageKind kind;
  final int entryCount;
}

Future<VaultStorageInspection> inspectVaultStorage(VaultStorage storage) async {
  final entries = (await storage.list())
      .where((entry) => entry.path.split('/').last != '.DS_Store')
      .toList();
  if (!await storage.exists(TylogVaultPaths.settings)) {
    return VaultStorageInspection(
      entries.isEmpty ? VaultStorageKind.empty : VaultStorageKind.nonVault,
      entryCount: entries.length,
    );
  }
  try {
    final settings = jsonDecode(
      await storage.readText(TylogVaultPaths.settings),
    );
    if (settings is Map && settings['version'] == 5) {
      return VaultStorageInspection(
        VaultStorageKind.validVault,
        entryCount: entries.length,
      );
    }
  } catch (_) {}
  return VaultStorageInspection(
    VaultStorageKind.incompatibleVault,
    entryCount: entries.length,
  );
}

Future<void> initializeVaultStorage(
  VaultStorage storage, {
  required Map<String, List<int>> managedFiles,
  required String currentHelper,
  required String legacyHelper,
  bool createIfMissing = true,
}) async {
  final inspection = await inspectVaultStorage(storage);
  final hasSettings = inspection.kind == VaultStorageKind.validVault;
  if (!hasSettings) {
    if (inspection.kind == VaultStorageKind.incompatibleVault) {
      throw StateError('This vault marker is malformed or unsupported.');
    }
    if (inspection.kind == VaultStorageKind.nonVault) {
      throw StateError(
        'This folder contains other files. Choose an empty folder or a TyLog v5 vault.',
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

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}
