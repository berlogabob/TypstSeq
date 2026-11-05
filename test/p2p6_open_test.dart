import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/vault_registry.dart';
import '../tool/p2p6/open_vault.dart';

void main() {
  test(
    'registers the received copy without replacing existing vaults',
    () async {
      final dir = await Directory.systemTemp.createTemp('p2p6-open-');
      addTearDown(() => dir.delete(recursive: true));
      final registry = VaultRegistry(File('${dir.path}/vaults.json'), [
        const VaultEntry(id: 'other', name: 'Other', path: '/other'),
      ], 'other');
      await registerReceivedVault(registry, '${dir.path}/received');
      await registerReceivedVault(registry, '${dir.path}/received');
      expect(registry.entries.length, 2);
      expect(registry.active.path, '${dir.path}/received');
      expect(registry.active.storageKind, 'app-local');
      expect(registry.active.cloud, isNull);
    },
  );
}
