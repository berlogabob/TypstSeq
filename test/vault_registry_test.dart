import 'dart:io';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/nextcloud_sync.dart';
import 'package:tylog/vault_registry.dart';

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

  test('forgetting the last vault empties the registry and active id', () async {
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
    final json = jsonDecode(await file.readAsString()) as Map<String, Object?>;
    expect(json['vaults'], isEmpty);
    expect(json['active'], '');
  });

  test('first-run onboarding completion is persisted', () async {
    final base = await Directory.systemTemp.createTemp('tylog_onboarding_');
    addTearDown(() => base.delete(recursive: true));
    final file = File('${base.path}/vaults.json');
    final registry = VaultRegistry(file, [], '', onboardingComplete: false);

    await registry.completeOnboarding();

    expect(registry.onboardingComplete, isTrue);
    expect(await file.readAsString(), contains('"onboardingComplete":true'));
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
}
