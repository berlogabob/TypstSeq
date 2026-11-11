import 'package:test/test.dart';
import 'package:tylog_core/tylog_core.dart';
import 'dart:io';

class _ThrowingStorage extends LocalVaultStorage {
  _ThrowingStorage(super.root);

  @override
  Future<String> readText(String path) =>
      throw const FileSystemException('transient read failure');
}

void main() {
  test(
    'inspectVaultStorage propagates an IO error instead of reporting incompatibleVault',
    () async {
      final dir = await Directory.systemTemp.createTemp('vault-io-test');
      addTearDown(() => dir.delete(recursive: true));
      final plain = LocalVaultStorage(dir);
      await plain.writeText(TylogVaultPaths.settings, '{"version":5}');
      final storage = _ThrowingStorage(dir);
      expect(inspectVaultStorage(storage), throwsA(isA<FileSystemException>()));
    },
  );

  test(
    'inspectVaultStorage reports incompatibleVault for malformed settings',
    () async {
      final dir = await Directory.systemTemp.createTemp('vault-io-test');
      addTearDown(() => dir.delete(recursive: true));
      final plain = LocalVaultStorage(dir);
      await plain.writeText(TylogVaultPaths.settings, '{not json');
      expect(
        (await inspectVaultStorage(plain)).kind,
        VaultStorageKind.incompatibleVault,
      );
    },
  );
}
