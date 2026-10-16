import 'dart:io';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/nextcloud_sync.dart';
import 'package:tylog/vault_registry.dart';
import 'package:tylog/vault_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // In-memory stand-in for the OS keystore (no platform channel in unit tests).
  final secureStore = <String, String>{};
  setUp(() {
    secureStore.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async {
            final args =
                (call.arguments as Map?)?.cast<String, Object?>() ?? const {};
            switch (call.method) {
              case 'write':
                secureStore[args['key'] as String] = args['value'] as String;
                return null;
              case 'read':
                return secureStore[args['key'] as String];
              case 'delete':
                secureStore.remove(args['key'] as String);
                return null;
              case 'containsKey':
                return secureStore.containsKey(args['key'] as String);
              case 'readAll':
                return secureStore;
              case 'deleteAll':
                secureStore.clear();
                return null;
            }
            return null;
          },
        );
  });
  test('app-local round trips and bypasses Android tree migration', () {
    const entry = VaultEntry(
      id: 'app',
      name: 'Private',
      path: '/app/support/vaults/private',
      storageKind: 'app-local',
    );
    final restored = VaultEntry.fromJson(
      (jsonDecode(jsonEncode(entry.toJson())) as Map).cast<String, Object?>(),
    );
    expect(restored.storageKind, 'app-local');
    expect(restored.path, entry.path);
    expect(restored.storage, isA<LocalVaultStorage>());
    expect(vaultNeedsAndroidTreeMigration(restored, android: true), isFalse);
  });

  test('new app-local vault uses a safe absolute support path', () async {
    final base = await Directory.systemTemp.createTemp('app-local-create-');
    addTearDown(() => base.delete(recursive: true));
    final registry = VaultRegistry(File('${base.path}/vaults.json'), [], '');
    final entry = await registry.createAppLocal(
      '../My vault',
      supportDirectory: base,
    );
    expect(entry.name, '../My vault');
    expect(entry.storageKind, 'app-local');
    expect(entry.path, startsWith('${base.path}/vaults/___My_vault-'));
    expect(await entry.storage.exists('.tylog/settings.json'), isTrue);
  });

  test(
    'copy preserves hidden bytes and mtimes, skips index and lock, reports progress',
    () async {
      final base = await Directory.systemTemp.createTemp('vault-copy-');
      addTearDown(() => base.delete(recursive: true));
      final source = LocalVaultStorage(Directory('${base.path}/source'));
      final destination = LocalVaultStorage(
        Directory('${base.path}/destination'),
      );
      final modified = DateTime.fromMillisecondsSinceEpoch(1700000000000);
      final paths = [
        'notes/a.typ',
        '.tylog/sync_state.json',
        '.other/nested/data',
      ];
      for (final path in [...paths, '_index/cache', '.tylog/vault.lock']) {
        await source.writeText(path, 'original $path');
        await File('${base.path}/source/$path').setLastModified(modified);
      }
      for (final item in await source.list(recursive: true)) {
        if (!item.isDirectory) {
          await File(
            '${base.path}/source/${item.path}',
          ).setLastModified(modified);
        }
      }
      final expected = (await source.list(recursive: true))
          .where(
            (item) =>
                !item.isDirectory &&
                !item.path.startsWith('_index/') &&
                item.path != '.tylog/vault.lock',
          )
          .map((item) => item.path)
          .toSet();
      final progress = <(int, int)>[];
      await copyVaultStorage(
        source,
        destination,
        onProgress: (done, total) => progress.add((done, total)),
      );
      expect(progress, [
        for (var i = 0; i <= expected.length; i++) (i, expected.length),
      ]);
      expect(
        (await destination.list(
          recursive: true,
        )).where((e) => !e.isDirectory).map((e) => e.path).toSet(),
        expected,
      );
      for (final path in expected) {
        expect(await destination.readBytes(path), await source.readBytes(path));
        expect((await destination.stat(path))!.modified, modified);
      }
      await verifyMatchingVaultStorage(source, destination);
      expect(await destination.exists('_index/cache'), isFalse);
      expect(await destination.exists('.tylog/vault.lock'), isFalse);
    },
  );

  for (final failure in ['copy', 'verification', 'open', 'none']) {
    test('move to app storage transaction: $failure', () async {
      final base = await Directory.systemTemp.createTemp('vault-move-');
      addTearDown(() => base.delete(recursive: true));
      final source = LocalVaultStorage(Directory('${base.path}/source'));
      await source.writeText('notes/a.typ', 'original');
      await source.writeText('.tylog/sync_state.json', 'cursor');
      final before = await source.hash('notes/a.typ');
      const channel = MethodChannel('org.tylog.tylog/saf');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            final args = (call.arguments as Map).cast<String, Object?>();
            final path = args['path'] as String? ?? '';
            Map<String, Object?> encode(VaultStorageEntry e) => {
              'path': e.path,
              'isDirectory': e.isDirectory,
              'size': e.size,
              'modified': e.modified?.millisecondsSinceEpoch,
            };
            switch (call.method) {
              case 'acquireSync':
              case 'releaseSync':
                return null;
              case 'exists':
              case 'existsNow':
                return source.exists(path);
              case 'read':
              case 'readNow':
                return source.readBytes(path);
              case 'write':
                await source.writeBytes(
                  path,
                  (args['bytes'] as List).cast<int>(),
                );
                return null;
              case 'delete':
                await source.delete(path);
                return null;
              case 'hash':
                if (failure == 'verification') return 'bad-hash';
                return source.hash(path);
              case 'list':
                return (await source.list(
                  path: path,
                  recursive: args['recursive'] as bool,
                )).map(encode).toList();
            }
            throw StateError('Unexpected SAF call: ${call.method}');
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      const cloud = NextcloudConfig(
        serverUrl: 'https://cloud.example',
        username: 'alice',
        password: 'secret',
      );
      const entry = VaultEntry(
        id: 'same-id',
        name: '../My vault',
        path: '',
        storageKind: 'android-tree',
        treeUri: 'content://test/tree',
        cloud: cloud,
      );
      final registry = VaultRegistry(File('${base.path}/vaults.json'), [
        entry,
      ], entry.id);
      await registry.save();
      Future<VaultEntry> move() => registry.moveToAppStorage(
        entry,
        supportDirectory: Directory('${base.path}/support'),
        onProgress: (done, total) {
          if (failure == 'copy' && done == 1) throw StateError('copy failed');
        },
        onOpen: (_) async {
          if (failure == 'open') throw StateError('open failed');
        },
      );
      if (failure == 'none') {
        final moved = await move();
        expect(moved.id, entry.id);
        expect(moved.cloud, same(cloud));
        expect(moved.backupPath, entry.treeUri);
        expect(moved.treeUri, isNull);
        expect(moved.storageKind, 'app-local');
        expect(moved.path, startsWith('${base.path}/support/vaults/'));
        await verifyMatchingVaultStorage(source, moved.storage);
      } else {
        await expectLater(move(), throwsStateError);
        expect(registry.active, same(entry));
        final saved = jsonDecode(await registry.file.readAsString()) as Map;
        expect(
          (saved['vaults'] as List).single['storage']['kind'],
          'android-tree',
        );
        expect(
          await Directory('${base.path}/support/vaults').list().toList(),
          isEmpty,
        );
      }
      expect(await source.hash('notes/a.typ'), before);
      expect(await source.readText('.tylog/sync_state.json'), 'cursor');
      expect(await source.exists('.tylog/vault.lock'), isFalse);
    });
  }

  test(
    'vault registry switches, keeps cloud settings separate, and forgets',
    () async {
      final base = await Directory.systemTemp.createTemp('tylog_registry_');
      addTearDown(() => base.delete(recursive: true));
      final first = await Directory('${base.path}/first').create();
      final second = await Directory('${base.path}/second').create();
      final file = File('${base.path}/vaults.json');
      final registry = VaultRegistry(file, [], '');

      final a = await registry.add(first.path);
      final b = await registry.add(second.path);
      await registry.select(b);
      const cloud = NextcloudConfig(
        serverUrl: 'https://cloud.example',
        username: 'alice',
        password: 'secret',
      );
      await registry.setCloud(b, cloud);

      expect(registry.activeId, b.id);
      expect(
        registry.entries.singleWhere((entry) => entry.id == a.id).cloud,
        isNull,
      );
      expect(registry.active.cloud?.username, 'alice');

      await registry.forget(a);
      expect(await first.exists(), isTrue);
      expect(registry.entries, hasLength(1));
    },
  );

  test('delete removes files before removing the vault entry', () async {
    final base = await Directory.systemTemp.createTemp('tylog_delete_');
    addTearDown(() async {
      if (await base.exists()) await base.delete(recursive: true);
    });
    final root = await Directory('${base.path}/doomed').create();
    await File('${root.path}/note.typ').writeAsString('keep until confirmed');
    final registry = VaultRegistry(File('${base.path}/vaults.json'), [], '');
    final entry = await registry.add(root.path);

    await registry.delete(entry);

    expect(await root.exists(), isFalse);
    expect(registry.entries, isEmpty);
  });

  test('Android tree deletion removes the root before forgetting it', () async {
    final base = await Directory.systemTemp.createTemp('tylog_tree_delete_');
    addTearDown(() => base.delete(recursive: true));
    const channel = MethodChannel('org.tylog.tylog/saf');
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    const entry = VaultEntry(
      id: 'tree',
      name: 'Tygo',
      path: '',
      storageKind: 'android-tree',
      treeUri: 'content://provider/tree/Tygo',
    );
    final registry = VaultRegistry(File('${base.path}/vaults.json'), [
      entry,
    ], entry.id);

    await registry.delete(entry);

    expect(calls, ['deleteRoot', 'releaseAccess']);
    expect(registry.entries, isEmpty);
  });

  test('failed Android tree deletion keeps the vault registered', () async {
    final base = await Directory.systemTemp.createTemp('tylog_tree_failure_');
    addTearDown(() => base.delete(recursive: true));
    const channel = MethodChannel('org.tylog.tylog/saf');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(code: 'unsupported', message: 'kept');
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    const entry = VaultEntry(
      id: 'tree',
      name: 'Tygo',
      path: '',
      storageKind: 'android-tree',
      treeUri: 'content://provider/tree/Tygo',
    );
    final registry = VaultRegistry(File('${base.path}/vaults.json'), [
      entry,
    ], entry.id);

    await expectLater(
      registry.delete(entry),
      throwsA(isA<PlatformException>()),
    );

    expect(registry.entries, [entry]);
  });

  test('forgetting an active Android vault only releases its grant', () async {
    final base = await Directory.systemTemp.createTemp('tylog_tree_forget_');
    addTearDown(() => base.delete(recursive: true));
    const channel = MethodChannel('org.tylog.tylog/saf');
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final keptDirectory = await Directory('${base.path}/kept').create();
    const forgotten = VaultEntry(
      id: 'tree',
      name: 'Tygo',
      path: '',
      storageKind: 'android-tree',
      treeUri: 'content://provider/tree/Tygo',
    );
    final kept = VaultEntry(id: 'kept', name: 'Kept', path: keptDirectory.path);
    final registry = VaultRegistry(File('${base.path}/vaults.json'), [
      forgotten,
      kept,
    ], forgotten.id);

    await registry.forget(forgotten);

    expect(calls, ['releaseAccess']);
    expect(registry.activeId, kept.id);
    expect(await keptDirectory.exists(), isTrue);
  });

  test('forget still removes the vault when the keystore fails', () async {
    // macOS keychain access can throw (entitlement/signature mismatch);
    // forgetting must not depend on the secret being deletable.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async {
            if (call.method == 'delete') {
              throw PlatformException(code: 'keystore_unavailable');
            }
            return null;
          },
        );
    final base = await Directory.systemTemp.createTemp('tylog_forget_');
    addTearDown(() => base.delete(recursive: true));
    final first = await Directory('${base.path}/first').create();
    final second = await Directory('${base.path}/second').create();
    final file = File('${base.path}/vaults.json');
    final registry = VaultRegistry(file, [], '');
    final a = await registry.add(first.path);
    await registry.add(second.path);

    await registry.forget(a);

    expect(registry.entries, hasLength(1));
    expect(await file.readAsString(), isNot(contains(a.id)));
  });

  test(
    'forgetting the last vault empties the registry and active id',
    () async {
      final base = await Directory.systemTemp.createTemp('tylog_forget_last_');
      addTearDown(() => base.delete(recursive: true));
      final root = await Directory('${base.path}/only').create();
      final file = File('${base.path}/vaults.json');
      final registry = VaultRegistry(file, [], '');
      final entry = await registry.add(root.path);

      await registry.forget(entry);

      expect(registry.entries, isEmpty);
      expect(registry.activeId, '');
      expect(await root.exists(), isTrue); // forget keeps files
      final json =
          jsonDecode(await file.readAsString()) as Map<String, Object?>;
      expect(json['vaults'], isEmpty);
      expect(json['active'], '');
    },
  );

  test('first-run onboarding completion is persisted', () async {
    final base = await Directory.systemTemp.createTemp('tylog_onboarding_');
    addTearDown(() => base.delete(recursive: true));
    final file = File('${base.path}/vaults.json');
    final registry = VaultRegistry(file, [], '', onboardingComplete: false);

    await registry.completeOnboarding();

    expect(registry.onboardingComplete, isTrue);
    expect(await file.readAsString(), contains('"onboardingComplete":true'));
  });

  test('reading preferences use legacy defaults and survive reload', () async {
    final base = await Directory.systemTemp.createTemp('tylog_reading_prefs_');
    addTearDown(() => base.delete(recursive: true));
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          pathProvider,
          (call) async => call.method == 'getApplicationDocumentsDirectory'
              ? base.path
              : null,
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProvider, null),
    );

    final vault = await Directory('${base.path}/vault').create();
    final file = File('${base.path}/vaults.json');
    final entry = VaultEntry(id: 'vault', name: 'Vault', path: vault.path);
    await file.writeAsString(
      jsonEncode({
        'version': 2,
        'active': entry.id,
        'onboardingComplete': true,
        'vaults': [entry.toJson()],
      }),
    );

    final legacy = await VaultRegistry.load();
    expect(legacy.readingFontScale, 1);
    expect(legacy.readingNightMode, isFalse);

    await legacy.updateReadingPreferences(fontScale: -1, nightMode: false);
    expect(legacy.readingFontScale, 0.8);
    await legacy.updateReadingPreferences(fontScale: 2.4, nightMode: true);
    final saved = jsonDecode(await file.readAsString()) as Map<String, Object?>;
    expect(saved['version'], 3);
    expect(saved['readingFontScale'], 2);
    expect(saved['readingNightMode'], isTrue);

    final restored = await VaultRegistry.load();
    expect(restored.readingFontScale, 2);
    expect(restored.readingNightMode, isTrue);
  });

  test('article-shelf prefs persist through save and reload', () async {
    final base = await Directory.systemTemp.createTemp('tylog_shelf_prefs_');
    addTearDown(() => base.delete(recursive: true));
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          pathProvider,
          (call) async => call.method == 'getApplicationDocumentsDirectory'
              ? base.path
              : null,
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProvider, null),
    );

    final vault = await Directory('${base.path}/vault').create();
    final file = File('${base.path}/vaults.json');
    final entry = VaultEntry(id: 'vault', name: 'Vault', path: vault.path);
    await file.writeAsString(
      jsonEncode({
        'version': 3,
        'active': entry.id,
        'onboardingComplete': true,
        'vaults': [entry.toJson()],
      }),
    );

    final registry = await VaultRegistry.load();
    expect(registry.shelfPrefs, isEmpty);
    await registry.updateShelfPrefs({'status': 'unread', 'sort': 'relevance'});

    final restored = await VaultRegistry.load();
    expect(restored.shelfPrefs, {'status': 'unread', 'sort': 'relevance'});
  });

  test(
    'registry reads legacy paths and writes typed Android tree locations',
    () {
      final legacy = VaultEntry.fromJson({
        'id': 'legacy',
        'name': 'Legacy',
        'path': '/old/vault',
      });
      expect(legacy.storageKind, 'local-path');
      expect(legacy.path, '/old/vault');

      const tree = VaultEntry(
        id: 'tree',
        name: 'TyLog',
        path: '',
        storageKind: 'android-tree',
        treeUri: 'content://provider/tree/primary%3ADocuments%2FTyLog',
        backupPath: '/private/TyLogVault',
      );
      final restored = VaultEntry.fromJson(
        (jsonDecode(jsonEncode(tree.toJson())) as Map).cast<String, Object?>(),
      );
      expect(restored.storageKind, 'android-tree');
      expect(restored.treeUri, tree.treeUri);
      expect(restored.backupPath, '/private/TyLogVault');
    },
  );

  test('Android uses SAF vaults and never creates a private replacement', () {
    const local = VaultEntry(
      id: 'local',
      name: 'Local',
      path: '/private/TyLog',
    );
    const tree = VaultEntry(
      id: 'tree',
      name: 'Tree',
      path: '',
      storageKind: 'android-tree',
      treeUri: 'content://provider/tree/primary%3ATyLog',
    );

    expect(vaultNeedsAndroidTreeMigration(local, android: true), isTrue);
    expect(vaultNeedsAndroidTreeMigration(tree, android: true), isFalse);
    expect(vaultNeedsAndroidTreeMigration(local, android: false), isFalse);
    expect(
      shouldCreateDefaultReplacementVault(entriesEmpty: true, android: true),
      isFalse,
    );
    expect(
      shouldCreateDefaultReplacementVault(entriesEmpty: true, android: false),
      isTrue,
    );
  });

  test('iOS vault paths follow the current app container', () {
    expect(
      rebaseIosVaultPath(
        '/var/mobile/Containers/Data/Application/OLD/Documents/TyLogVault',
        '/var/mobile/Containers/Data/Application/NEW/Documents',
        ios: true,
      ),
      '/var/mobile/Containers/Data/Application/NEW/Documents/TyLogVault',
    );
    expect(
      rebaseIosVaultPath('/external/TyLogVault', '/new/Documents', ios: true),
      '/external/TyLogVault',
    );
  });

  test(
    'deviceId is generated once, persisted, and honored when supplied',
    () async {
      final base = await Directory.systemTemp.createTemp('tylog_registry_');
      addTearDown(() => base.delete(recursive: true));
      final file = File('${base.path}/vaults.json');

      final generated = VaultRegistry(file, [], '');
      expect(generated.deviceId, matches(RegExp(r'^[0-9a-f]{16}$')));
      await generated.save();
      final stored =
          jsonDecode(await file.readAsString()) as Map<String, Object?>;
      expect(stored['deviceId'], generated.deviceId);

      final restored = VaultRegistry(
        file,
        [],
        '',
        deviceId: stored['deviceId'] as String,
      );
      expect(restored.deviceId, generated.deviceId);

      // Two fresh installs never collide on the same id.
      expect(VaultRegistry(file, [], '').deviceId, isNot(generated.deviceId));
    },
  );
}
