import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'nextcloud_sync.dart';
import 'vault_lock.dart';
import 'vault.dart';
import 'vault_storage.dart';

String readableVaultLocation(String location) {
  if (!location.startsWith('content://')) return location;
  final tree = location.indexOf('/tree/');
  final candidates = [
    if (tree >= 0) location.substring(tree + 6).split('/').first,
    location.split('/').last,
  ];
  for (final candidate in candidates) {
    if (candidate.isEmpty) continue;
    try {
      final decoded = Uri.decodeComponent(candidate)
          .replaceFirst(RegExp(r'^(?:raw|primary|msf):/*'), '')
          .replaceFirst(RegExp(r'^/?storage/emulated/0/+'), '');
      if (decoded.isNotEmpty) return decoded;
    } on FormatException {
      // Try the last path segment, then fall back to the original URI.
    }
  }
  return location;
}

class RecentNote {
  const RecentNote({
    required this.path,
    required this.openedAt,
    this.progress = 0,
  });

  final String path;
  final DateTime openedAt;
  final double progress;

  Map<String, Object?> toJson() => {
    'path': path,
    'openedAt': openedAt.toIso8601String(),
    if (progress > 0) 'progress': progress,
  };

  factory RecentNote.fromJson(Map<String, Object?> json) => RecentNote(
    path: json['path'] as String,
    openedAt: DateTime.parse(json['openedAt'] as String),
    progress: (json['progress'] as num?)?.toDouble() ?? 0,
  );
}

class VaultEntry {
  const VaultEntry({
    required this.id,
    required this.name,
    required this.path,
    this.storageKind = 'local-path',
    this.treeUri,
    this.backupPath,
    this.cloud,
    this.recent = const [],
  });

  final String id;
  final String name;
  final String path;
  final String storageKind;
  final String? treeUri;
  final String? backupPath;
  final NextcloudConfig? cloud;
  final List<RecentNote> recent;

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
    List<RecentNote>? recent,
  }) => VaultEntry(
    id: id,
    name: name ?? this.name,
    path: path ?? this.path,
    storageKind: storageKind ?? this.storageKind,
    treeUri: treeUri ?? this.treeUri,
    backupPath: backupPath ?? this.backupPath,
    cloud: cloud ?? this.cloud,
    recent: recent ?? this.recent,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'storage': storageKind == 'android-tree'
        ? {'kind': storageKind, 'uri': treeUri, 'name': name}
        : {'kind': storageKind, 'path': path},
    if (backupPath != null) 'backupPath': backupPath,
    if (cloud != null) 'nextcloud': cloud!.toJson(),
    if (recent.isNotEmpty) 'recent': recent.map((r) => r.toJson()).toList(),
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
      recent: json['recent'] is List
          ? (json['recent'] as List)
                .map(
                  (item) => RecentNote.fromJson(
                    (item as Map).cast<String, Object?>(),
                  ),
                )
                .toList()
          : const [],
    );
  }
}

bool vaultNeedsAndroidTreeMigration(VaultEntry entry, {bool? android}) =>
    (android ?? Platform.isAndroid) &&
    entry.storageKind != 'android-tree' &&
    entry.storageKind != 'app-local';

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
    this.themeMode = 'system',
    this.pdfPaper = 'a4',
    this.screenshotsMode = 'off',
    this.screenshotsTime = '03:00',
    this.shelfPrefs = const {},
    String? deviceId,
  }) : deviceId = deviceId ?? newDeviceId();

  final File file;
  final List<VaultEntry> entries;
  String activeId;
  bool onboardingComplete;
  double readingFontScale;
  bool readingNightMode;

  /// App-wide appearance: 'system' | 'light' | 'dark'. Stored as a string so
  /// this Flutter-free file stays independent of `ThemeMode`.
  String themeMode;
  String pdfPaper;
  String screenshotsMode;
  String screenshotsTime;

  /// Article-shelf filter/sort/group choices, persisted so they survive an app
  /// restart (e.g. `{'status': 'unread', 'sort': 'relevance'}`).
  Map<String, String> shelfPrefs;

  /// Stable per-install identifier, used to name this device's reading-state
  /// file inside the vault (`_system/reading/<deviceId>.json`).
  final String deviceId;
  Future<void> _pendingSave = Future.value();

  static String newDeviceId() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
  }

  VaultEntry get active => entries.firstWhere((entry) => entry.id == activeId);

  static Future<VaultRegistry> load() async {
    final documents = await getApplicationDocumentsDirectory();
    final file = File('${documents.path}/vaults.json');
    var readingFontScale = 1.0;
    var readingNightMode = false;
    var themeMode = 'system';
    var pdfPaper = 'a4';
    if (await file.exists()) {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, Object?>;
      readingFontScale = _readingFontScale(json['readingFontScale']);
      readingNightMode = json['readingNightMode'] as bool? ?? false;
      themeMode = json['themeMode'] as String? ?? 'system';
      final storedPaper = json['pdfPaper'];
      if (const ['a4', 'us-letter', 'a5', 'us-legal'].contains(storedPaper)) {
        pdfPaper = storedPaper as String;
      }
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
        final storedDeviceId = json['deviceId'] as String?;
        if (storedDeviceId == null || storedDeviceId.isEmpty) migrated = true;
        final registry = VaultRegistry(
          file,
          entries,
          entries.any((entry) => entry.id == active)
              ? active!
              : entries.first.id,
          onboardingComplete: json['onboardingComplete'] as bool? ?? true,
          readingFontScale: readingFontScale,
          readingNightMode: readingNightMode,
          themeMode: themeMode,
          pdfPaper: pdfPaper,
          screenshotsMode:
              ['off', 'watch', 'schedule', 'both'].contains(json['screenshotsMode'])
              ? json['screenshotsMode'] as String
              : 'off',
          screenshotsTime: _screenshotsTime(json['screenshotsTime']),
          shelfPrefs:
              (json['shelfPrefs'] as Map?)?.map(
                (k, v) => MapEntry('$k', '$v'),
              ) ??
              const {},
          deviceId: storedDeviceId == null || storedDeviceId.isEmpty
              ? null
              : storedDeviceId,
        );
        // Rewrite vaults.json without the now-migrated inline passwords
        // (and persist a freshly generated deviceId).
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
        pdfPaper: pdfPaper,
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
      pdfPaper: pdfPaper,
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

  Future<Directory> _newAppDirectory(String name, Directory? support) async {
    final root = support ?? await getApplicationSupportDirectory();
    final parent = await Directory(
      '${root.absolute.path}/vaults',
    ).create(recursive: true);
    final safe = name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return parent.createTemp('${safe.isEmpty ? 'Vault' : safe}-');
  }

  Future<VaultEntry> createAppLocal(
    String name, {
    Directory? supportDirectory,
  }) async {
    final directory = await _newAppDirectory(name, supportDirectory);
    final entry = VaultEntry(
      id: _id(directory.path),
      name: name,
      path: directory.path,
      storageKind: 'app-local',
    );
    try {
      await Vault.withStorage(entry.storage).ensureCreated();
      entries.add(entry);
      await save();
      return entry;
    } catch (_) {
      entries.remove(entry);
      await directory.delete(recursive: true);
      rethrow;
    }
  }

  Future<VaultEntry> moveToAppStorage(
    VaultEntry entry, {
    Directory? supportDirectory,
    void Function(int done, int total)? onProgress,
    Future<void> Function(VaultEntry entry)? onOpen,
  }) async {
    if (entry.storageKind != 'android-tree') {
      throw ArgumentError('Only external vaults can be moved');
    }
    final index = entries.indexWhere((item) => item.id == entry.id);
    if (index < 0) throw StateError('Vault is no longer registered');
    final source = entry.storage as AndroidTreeVaultStorage;
    Directory? directory;
    final previousActive = activeId;
    var replaced = false;
    var saved = false;
    var syncAcquired = false;
    var lockAcquired = false;
    try {
      // Serialize with actual SAF sync as well as the cross-engine owner file.
      await source.acquireSync();
      syncAcquired = true;
      if (await VaultLock.currentOwner(source) != null ||
          !await VaultLock.acquire(
            source,
            'ui',
            // Long enough for a ~20k-file SAF copy; a killed copy must not
            // block background sync for a day.
            validFor: const Duration(hours: 2),
          )) {
        throw StateError('Vault is busy; try again after sync finishes');
      }
      lockAcquired = true;
      directory = await _newAppDirectory(entry.name, supportDirectory);
      final destination = LocalVaultStorage(directory);
      await copyVaultStorage(source, destination, onProgress: onProgress);
      await verifyMatchingVaultStorage(source, destination);
      // Release the native gate before committing so release errors also roll back.
      // The owner file continues to exclude background runs until the move ends.
      await source.releaseSync();
      syncAcquired = false;
      final moved = VaultEntry(
        id: entry.id,
        name: entry.name,
        path: directory.path,
        storageKind: 'app-local',
        backupPath: entry.treeUri,
        cloud: entry.cloud,
        recent: entry.recent,
      );
      entries[index] = moved;
      activeId = moved.id;
      replaced = true;
      await save();
      saved = true;
      await onOpen?.call(moved);
      return moved;
    } catch (_) {
      if (replaced) {
        entries[index] = entry;
        activeId = previousActive;
        // Atomic save failures leave the prior registry intact. If opening
        // failed after commit, restore it before removing the copied files.
        if (saved) await save();
      }
      if (directory != null) await directory.delete(recursive: true);
      rethrow;
    } finally {
      try {
        if (lockAcquired) await VaultLock.release(source, 'ui');
      } finally {
        if (syncAcquired) await source.releaseSync();
      }
    }
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

  static String _screenshotsTime(Object? value) =>
      value is String && RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(value)
      ? value
      : '03:00';

  Future<void> setScreenshotsOcr(String mode, String time) {
    if (!['off', 'watch', 'schedule', 'both'].contains(mode) ||
        _screenshotsTime(time) != time) {
      throw ArgumentError('Invalid screenshot mode or schedule');
    }
    screenshotsMode = mode;
    screenshotsTime = time;
    return save();
  }

  Future<void> setPdfPaper(String paper) {
    pdfPaper = paper;
    return save();
  }

  Future<void> setThemeMode(String mode) {
    themeMode = mode;
    return save();
  }

  Future<void> updateShelfPrefs(Map<String, String> prefs) {
    shelfPrefs = prefs;
    return save();
  }

  Future<void> setCloud(VaultEntry entry, NextcloudConfig cloud) async {
    await cloud.saveSecret(vaultId: entry.id);
    final index = entries.indexWhere((item) => item.id == entry.id);
    entries[index] = entry.copyWith(cloud: cloud);
    await save();
  }

  static const _maxRecentNotes = 30;

  /// [fallbackProgress] seeds the position when this device has no record of
  /// [path] yet (e.g. the article was read partway on another device).
  Future<void> recordOpen(
    VaultEntry entry,
    String path, {
    double fallbackProgress = 0,
  }) async {
    final index = entries.indexWhere((item) => item.id == entry.id);
    if (index == -1) return;
    // Keep the known reading position — reopening a note must not zero it.
    var progress = fallbackProgress;
    for (final r in entry.recent) {
      if (r.path == path) {
        progress = r.progress;
        break;
      }
    }
    final without = entry.recent.where((r) => r.path != path);
    final next = [
      RecentNote(path: path, openedAt: DateTime.now(), progress: progress),
      ...without,
    ].take(_maxRecentNotes).toList();
    entries[index] = entry.copyWith(recent: next);
    await save();
  }

  Future<void> recordProgress(
    VaultEntry entry,
    String path,
    double progress,
  ) async {
    final index = entries.indexWhere((item) => item.id == entry.id);
    if (index == -1) return;
    entries[index] = entry.copyWith(
      recent: [
        for (final r in entry.recent)
          r.path == path
              ? RecentNote(
                  path: r.path,
                  openedAt: r.openedAt,
                  progress: progress,
                )
              : r,
      ],
    );
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
        'deviceId': deviceId,
        'onboardingComplete': onboardingComplete,
        'readingFontScale': readingFontScale,
        'readingNightMode': readingNightMode,
        'themeMode': themeMode,
        'pdfPaper': pdfPaper,
        'screenshotsMode': screenshotsMode,
        'screenshotsTime': screenshotsTime,
        'shelfPrefs': shelfPrefs,
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

bool _copyableVaultFile(VaultStorageEntry item) =>
    !item.isDirectory &&
    !item.path.startsWith('_index/') &&
    item.path != VaultLock.path;

Future<void> copyVaultStorage(
  VaultStorage source,
  VaultStorage destination, {
  void Function(int done, int total)? onProgress,
}) async {
  if ((await destination.list()).isNotEmpty) {
    throw StateError('Choose an empty folder for migration');
  }
  final files = (await source.list(
    recursive: true,
  )).where(_copyableVaultFile).toList();
  onProgress?.call(0, files.length);
  var done = 0;
  for (final item in files) {
    validateVaultPath(item.path);
    final bytes = await source.readBytes(item.path);
    // Exact type: subclasses may override writeBytes and must keep it.
    if (destination.runtimeType == LocalVaultStorage) {
      // Raw atomic writes avoid generating new index-dirty metadata during a copy.
      final file = File('${destination.syncIdentity}/${item.path}');
      await writeFileAtomic(file, bytes);
      if (item.modified != null) await file.setLastModified(item.modified!);
    } else {
      await destination.writeBytes(item.path, bytes);
    }
    if (sha256.convert(bytes).toString() != await destination.hash(item.path)) {
      throw StateError('Migration verification failed for ${item.path}');
    }
    onProgress?.call(++done, files.length);
  }
}

Future<void> verifyMatchingVaultStorage(
  VaultStorage source,
  VaultStorage destination,
) async {
  final sourceFiles = (await source.list(
    recursive: true,
  )).where(_copyableVaultFile).map((item) => item.path).toSet();
  final destinationFiles = (await destination.list(
    recursive: true,
  )).where(_copyableVaultFile).map((item) => item.path).toSet();
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
