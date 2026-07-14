import 'dart:io';

import 'package:open_file/open_file.dart';

import 'vault_storage.dart';

class PlatformFileActions {
  const PlatformFileActions();

  Future<void> importFile(
    VaultStorage storage,
    String path,
    File source,
  ) async {
    if (storage is AndroidTreeVaultStorage) {
      await AndroidTreeVaultStorage.invoke(
        AndroidTreeVaultStorage.channel.invokeMethod<void>(
          'import',
          storage.args({'path': path, 'source': source.path}),
        ),
        'import',
      );
      return;
    }
    await storage.writeBytes(path, await source.readAsBytes());
  }

  Future<void> openExternal(
    VaultStorage storage,
    String path, {
    Directory? localRoot,
  }) async {
    if (storage is AndroidTreeVaultStorage) {
      await AndroidTreeVaultStorage.invoke(
        AndroidTreeVaultStorage.channel.invokeMethod<void>(
          'open',
          storage.args({'path': path}),
        ),
        'open',
      );
      return;
    }
    if (localRoot == null) {
      throw StateError('A local vault path is required to open this file');
    }
    final result = await OpenFile.open('${localRoot.path}/$path');
    if (result.type != ResultType.done) throw StateError(result.message);
  }
}
