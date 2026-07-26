import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

import 'vault_storage.dart';

Future<void> importPlatformFile(
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

Future<void> openPlatformFile(
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
  final uri = Uri.file('${localRoot.path}/$path');
  if (!await launchUrl(uri)) {
    throw StateError('Could not open $path');
  }
}
