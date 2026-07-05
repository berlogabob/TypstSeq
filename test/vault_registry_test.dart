import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/nextcloud_sync.dart';
import 'package:tylog/vault_registry.dart';

void main() {
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

  test('first-run onboarding completion is persisted', () async {
    final base = await Directory.systemTemp.createTemp('tylog_onboarding_');
    addTearDown(() => base.delete(recursive: true));
    final file = File('${base.path}/vaults.json');
    final registry = VaultRegistry(file, [], '', onboardingComplete: false);

    await registry.completeOnboarding();

    expect(registry.onboardingComplete, isTrue);
    expect(await file.readAsString(), contains('"onboardingComplete":true'));
  });
}
