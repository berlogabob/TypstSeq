import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'nextcloud_sync.dart';
import 'vault.dart';

class VaultEntry {
  const VaultEntry({
    required this.id,
    required this.name,
    required this.path,
    this.cloud,
  });

  final String id;
  final String name;
  final String path;
  final NextcloudConfig? cloud;

  VaultEntry copyWith({NextcloudConfig? cloud}) =>
      VaultEntry(id: id, name: name, path: path, cloud: cloud);

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'path': path,
    if (cloud != null) 'nextcloud': cloud!.toJson(),
  };

  factory VaultEntry.fromJson(Map<String, Object?> json) => VaultEntry(
    id: json['id'] as String,
    name: json['name'] as String,
    path: json['path'] as String,
    cloud: json['nextcloud'] is Map
        ? NextcloudConfig.fromJson(
            (json['nextcloud'] as Map).cast<String, Object?>(),
          )
        : null,
  );
}

class VaultRegistry {
  VaultRegistry(
    this.file,
    this.entries,
    this.activeId, {
    this.onboardingComplete = true,
  });

  final File file;
  final List<VaultEntry> entries;
  String activeId;
  bool onboardingComplete;

  VaultEntry get active => entries.firstWhere((entry) => entry.id == activeId);

  static Future<VaultRegistry> load() async {
    final documents = await getApplicationDocumentsDirectory();
    final file = File('${documents.path}/vaults.json');
    if (await file.exists()) {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, Object?>;
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
      for (final entry in parsed) {
        final cloud = entry.cloud;
        if (cloud == null) {
          entries.add(entry);
          continue;
        }
        final secret = await NextcloudConfig.readSecret(vaultId: entry.id);
        if (secret != null) {
          entries.add(entry.copyWith(cloud: cloud.withPassword(secret)));
        } else {
          if (cloud.password.isNotEmpty) {
            await cloud.saveSecret(vaultId: entry.id);
            migrated = true;
          }
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
        );
        // Rewrite vaults.json without the now-migrated inline passwords.
        if (migrated) await registry.save();
        return registry;
      }
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

  Future<void> select(VaultEntry entry) async {
    activeId = entry.id;
    await save();
  }

  Future<void> completeOnboarding() async {
    onboardingComplete = true;
    await save();
  }

  Future<void> setCloud(VaultEntry entry, NextcloudConfig cloud) async {
    await cloud.saveSecret(vaultId: entry.id);
    final index = entries.indexWhere((item) => item.id == entry.id);
    entries[index] = entry.copyWith(cloud: cloud);
    await save();
  }

  Future<void> forget(VaultEntry entry) async {
    await NextcloudConfig.deleteSecret(vaultId: entry.id);
    entries.removeWhere((item) => item.id == entry.id);
    if (activeId == entry.id && entries.isNotEmpty) activeId = entries.first.id;
    await save();
  }

  Future<void> delete(VaultEntry entry) async {
    final directory = Directory(entry.path);
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
    await forget(entry);
  }

  Future<void> save() => file.writeAsString(
    jsonEncode({
      'active': activeId,
      'onboardingComplete': onboardingComplete,
      'vaults': entries.map((entry) => entry.toJson()).toList(),
    }),
    flush: true,
  );
}

String _name(String path) =>
    path.replaceAll(RegExp(r'[/\\]+$'), '').split(RegExp(r'[/\\]')).last;

String _id(String path) =>
    base64Url.encode(utf8.encode(path)).replaceAll('=', '');
