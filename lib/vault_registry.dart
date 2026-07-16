import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'nextcloud_sync.dart';
import 'vault.dart';
import 'vault_storage.dart';

class VaultEntry {
  const VaultEntry({
    required this.id,
    required this.name,
    required this.path,
    this.storageKind = 'local-path',
    this.treeUri,
    this.backupPath,
    this.cloud,
  });

  final String id;
  final String name;
  final String path;
  final String storageKind;
  final String? treeUri;
  final String? backupPath;
  final NextcloudConfig? cloud;

  VaultStorage get storage => storageKind == 'android-tree'
      ? AndroidTreeVaultStorage(uri: treeUri!, name: name)
      : LocalVaultStorage(Directory(path));

  VaultEntry copyWith({
    String? name,
    String? path,
    String? storageKind,
    String? treeUri,
    String? backupPath,
    NextcloudConfig? cloud,
  }) => VaultEntry(
    id: id,
    name: name ?? this.name,
    path: path ?? this.path,
    storageKind: storageKind ?? this.storageKind,
    treeUri: treeUri ?? this.treeUri,
    backupPath: backupPath ?? this.backupPath,
    cloud: cloud ?? this.cloud,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'storage': storageKind == 'android-tree'
        ? {'kind': storageKind, 'uri': treeUri, 'name': name}
        : {'kind': storageKind, 'path': path},
    if (backupPath != null) 'backupPath': backupPath,
    if (cloud != null) 'nextcloud': cloud!.toJson(),
  };

  factory VaultEntry.fromJson(Map<String, Object?> json) {
    final storage = json['storage'] is Map
        ? (json['storage'] as Map).cast<String, Object?>()
        : <String, Object?>{
            'kind': 'local-path',
            'path': json['path'] as String? ?? '',
          };
    final kind = storage['kind'] as String? ?? 'local-path';
    final name =
        json['name'] as String? ?? storage['name'] as String? ?? 'Vault';
    return VaultEntry(
      id: json['id'] as String,
      name: name,
      path: storage['path'] as String? ?? '',
      storageKind: kind,
      treeUri: storage['uri'] as String?,
      backupPath: json['backupPath'] as String?,
      cloud: json['nextcloud'] is Map
          ? NextcloudConfig.fromJson(
              (json['nextcloud'] as Map).cast<String, Object?>(),
            )
          : null,
    );
  }
}

bool vaultNeedsAndroidTreeMigration(VaultEntry entry, {bool? android}) =>
    (android ?? Platform.isAndroid) && entry.storageKind != 'android-tree';

bool shouldCreateDefaultReplacementVault({
  required bool entriesEmpty,
  bool? android,
}) => entriesEmpty && !(android ?? Platform.isAndroid);

String rebaseIosVaultPath(String path, String documentsPath, {bool? ios}) {
  if (!(ios ?? Platform.isIOS)) return path;
  final match = RegExp(
    r'^/var/mobile/Containers/Data/Application/[^/]+/Documents/(.+)$',
  ).firstMatch(path);
  return match == null ? path : '$documentsPath/${match.group(1)}';
}

class VaultRegistry {
  VaultRegistry(
    this.file,
    this.entries,
    this.activeId, {
    this.onboardingComplete = true,
    this.readingFontScale = 1,
    this.readingNightMode = false,
  });

  final File file;
  final List<VaultEntry> entries;
  String activeId;
  bool onboardingComplete;
  double readingFontScale;
  bool readingNightMode;
  Future<void> _pendingSave = Future.value();

  VaultEntry get active => entries.firstWhere((entry) => entry.id == activeId);

  static Future<VaultRegistry> load() async {
    final documents = await getApplicationDocumentsDirectory();
    final file = File('${documents.path}/vaults.json');
    var readingFontScale = 1.0;
    var readingNightMode = false;
    if (await file.exists()) {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, Object?>;
      readingFontScale = _readingFontScale(json['readingFontScale']);
      readingNightMode = json['readingNightMode'] as bool? ?? false;
      final parsed = (json['vaults'] as List)
          .map(
            (item) =>
                VaultEntry.fromJson((item as Map).cast<String, Object?>()),
          )
          .toList();
      // Hydrate each cloud password from the OS keystore (migrating any legacy
      // inline password out of vaults.json on first load after upgrade).
      final entries = <VaultEntry>[];
      var migrated = false;
      for (var entry in parsed) {
        final rebasedPath = rebaseIosVaultPath(entry.path, documents.path);
        if (rebasedPath != entry.path &&
            await Directory(rebasedPath).exists()) {
          entry = entry.copyWith(path: rebasedPath);
          migrated = true;
        }
        final cloud = entry.cloud;
        if (cloud == null) {
          entries.add(entry);
          continue;
        }
        // Keystore access can fail (e.g. macOS keychain entitlement/signature
        // mismatch on dev runs). A local vault must still open, so fall back
        // to whatever the entry already carries instead of aborting startup.
        try {
          final secret = await NextcloudConfig.readSecret(
            vaultId: entry.id,
          ).timeout(const Duration(seconds: 5));
          if (secret != null) {
            entries.add(entry.copyWith(cloud: cloud.withPassword(secret)));
          } else {
            if (cloud.password.isNotEmpty) {
              await cloud.saveSecret(vaultId: entry.id);
              migrated = true;
            }
            entries.add(entry);
          }
        } on Exception {
          entries.add(entry);
        }
      }
      if (entries.isNotEmpty) {
        final active = json['active'] as String?;
        final registry = VaultRegistry(
          file,
          entries,
          entries.any((entry) => entry.id == active)
              ? active!
              : entries.first.id,
          onboardingComplete: json['onboardingComplete'] as bool? ?? true,
          readingFontScale: readingFontScale,
          readingNightMode: readingNightMode,
        );
        // Rewrite vaults.json without the now-migrated inline passwords.
        if (migrated) await registry.save();
        return registry;
      }
    }

    if (Platform.isAndroid) {
      final registry = VaultRegistry(
        file,
        [],
        '',
        onboardingComplete: false,
        readingFontScale: readingFontScale,
        readingNightMode: readingNightMode,
      );
      await registry.save();
      return registry;
    }

    final root = defaultVaultDirectory(documents).absolute.path;
    final legacyCloud = await NextcloudConfig.load();
    final entry = VaultEntry(
      id: _id(root),
      name: _name(root),
      path: root,
      cloud: legacyCloud,
    );
    // Key the legacy single-vault password under this entry's id.
    if (legacyCloud != null) await legacyCloud.saveSecret(vaultId: entry.id);
    final registry = VaultRegistry(
      file,
      [entry],
      entry.id,
      onboardingComplete: false,
      readingFontScale: readingFontScale,
      readingNightMode: readingNightMode,
    );
    await registry.save();
    return registry;
  }

  Future<VaultEntry> add(String path) async {
    final normalized = Directory(path).absolute.path;
    final existing = entries
        .where((entry) => entry.path == normalized)
        .firstOrNull;
    if (existing != null) return existing;
    final entry = VaultEntry(
      id: _id(normalized),
      name: _name(normalized),
      path: normalized,
    );
    entries.add(entry);
    await save();
    return entry;
  }

  Future<VaultEntry> addTree(AndroidTreeSelection selection) async {
    final existing = entries
        .where((entry) => entry.treeUri == selection.uri)
        .firstOrNull;
    if (existing != null) return existing;
    final entry = VaultEntry(
      id: _id(selection.uri),
      name: selection.name,
      path: '',
      storageKind: 'android-tree',
      treeUri: selection.uri,
    );
    entries.add(entry);
    await save();
    return entry;
  }

  Future<VaultEntry> migrateToTree(
    VaultEntry entry,
    AndroidTreeSelection selection,
  ) async {
    final destination = AndroidTreeVaultStorage(
      uri: selection.uri,
      name: selection.name,
    );
    if ((await destination.list()).isEmpty) {
      await copyVaultStorage(entry.storage, destination);
    } else {
      await verifyMatchingVaultStorage(entry.storage, destination);
    }
    final migrated = entry.copyWith(
      name: selection.name,
      storageKind: 'android-tree',
      treeUri: selection.uri,
      backupPath: entry.path,
    );
    entries[entries.indexWhere((item) => item.id == entry.id)] = migrated;
    await save();
    return migrated;
  }

  Future<VaultEntry> rebindTree(
    VaultEntry entry,
    AndroidTreeSelection selection,
  ) async {
    final rebound = entry.copyWith(
      name: selection.name,
      storageKind: 'android-tree',
      treeUri: selection.uri,
    );
    entries[entries.indexWhere((item) => item.id == entry.id)] = rebound;
    await save();
    return rebound;
  }

  Future<void> select(VaultEntry entry) async {
    activeId = entry.id;
    await save();
  }

  Future<void> completeOnboarding() async {
    onboardingComplete = true;
    await save();
  }

  Future<void> updateReadingPreferences({
    required double fontScale,
    required bool nightMode,
  }) {
    readingFontScale = _readingFontScale(fontScale);
    readingNightMode = nightMode;
    return save();
  }

  Future<void> setCloud(VaultEntry entry, NextcloudConfig cloud) async {
    await cloud.saveSecret(vaultId: entry.id);
    final index = entries.indexWhere((item) => item.id == entry.id);
    entries[index] = entry.copyWith(cloud: cloud);
    await save();
  }

  Future<void> forget(VaultEntry entry) async {
    if (entry.storageKind == 'android-tree') {
      try {
        await (entry.storage as AndroidTreeVaultStorage).releaseAccess();
      } catch (_) {}
    }
    // Keystore access can fail/hang (macOS keychain entitlement mismatch);
    // an orphaned secret must not block forgetting the vault.
    try {
      await NextcloudConfig.deleteSecret(
        vaultId: entry.id,
      ).timeout(const Duration(seconds: 5));
    } catch (_) {}
    entries.removeWhere((item) => item.id == entry.id);
    if (activeId == entry.id) {
      activeId = entries.isNotEmpty ? entries.first.id : '';
    }
    await save();
  }

  Future<void> delete(VaultEntry entry) async {
    if (entry.storageKind == 'android-tree') {
      await (entry.storage as AndroidTreeVaultStorage).deleteRoot();
    } else {
      final directory = Directory(entry.path);
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    }
    await forget(entry);
  }

  Future<void> save() {
    final bytes = utf8.encode(
      jsonEncode({
        'version': 3,
        'active': activeId,
        'onboardingComplete': onboardingComplete,
        'readingFontScale': readingFontScale,
        'readingNightMode': readingNightMode,
        'vaults': entries.map((entry) => entry.toJson()).toList(),
      }),
    );
    final next = _pendingSave
        .catchError((_) {})
        .then((_) => writeFileAtomic(file, bytes));
    _pendingSave = next;
    return next;
  }
}

Future<void> copyVaultStorage(
  VaultStorage source,
  VaultStorage destination,
) async {
  if ((await destination.list()).isNotEmpty) {
    throw StateError('Choose an empty folder for migration');
  }
  for (final item in await source.list(recursive: true)) {
    if (item.isDirectory || item.path.startsWith('_index/')) continue;
    await destination.writeBytes(item.path, await source.readBytes(item.path));
    if (await source.hash(item.path) != await destination.hash(item.path)) {
      throw StateError('Migration verification failed for ${item.path}');
    }
  }
}

Future<void> verifyMatchingVaultStorage(
  VaultStorage source,
  VaultStorage destination,
) async {
  final sourceFiles = (await source.list(recursive: true))
      .where((item) => !item.isDirectory && !item.path.startsWith('_index/'))
      .map((item) => item.path)
      .toSet();
  final destinationFiles = (await destination.list(recursive: true))
      .where((item) => !item.isDirectory && !item.path.startsWith('_index/'))
      .map((item) => item.path)
      .toSet();
  if (!destinationFiles.containsAll(sourceFiles)) {
    throw StateError('Selected folder is not the existing vault');
  }
  for (final path in sourceFiles) {
    if (await source.hash(path) != await destination.hash(path)) {
      throw StateError('Selected folder differs at $path');
    }
  }
}

String _name(String path) =>
    path.replaceAll(RegExp(r'[/\\]+$'), '').split(RegExp(r'[/\\]')).last;

String _id(String path) =>
    base64Url.encode(utf8.encode(path)).replaceAll('=', '');

double _readingFontScale(Object? value) => value is num && value.isFinite
    ? value.toDouble().clamp(0.8, 2).toDouble()
    : 1;
