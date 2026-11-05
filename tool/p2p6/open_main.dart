import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tylog/main.dart' as tylog;
import 'package:tylog/vault_registry.dart';

import 'open_vault.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!Platform.isAndroid ||
      await const MethodChannel(
            'org.tylog.tylog/share',
          ).invokeMethod<bool>('isProfileTest') !=
          true) {
    throw StateError('Requires isolated .profiletest package');
  }
  final path = '${(await getApplicationSupportDirectory()).path}/p2p6-received';
  if (!await Directory(path).exists()) {
    throw StateError('Received copy is missing');
  }
  await registerReceivedVault(await VaultRegistry.load(), path);
  tylog.main();
}
