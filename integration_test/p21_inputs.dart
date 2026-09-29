import 'dart:io';

import 'package:path_provider/path_provider.dart';

const p21Handshake = bool.fromEnvironment('P21_HANDSHAKE');

Future<({Directory model, Directory? vault})?> awaitP21Inputs() async {
  if (!p21Handshake) return null;
  final dir = Directory('${(await getExternalStorageDirectory())!.path}/p21');
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  await dir.create(recursive: true);
  // ignore: avoid_print
  print('P21_READY ${dir.path}');
  for (var i = 0; i < 1200; i++) {
    if (File('${dir.path}/.done').existsSync()) {
      await File('${dir.path}/verified').writeAsString('verified\n');
      final vault = Directory('${dir.path}/TyLog');
      return (model: dir, vault: vault.existsSync() ? vault : null);
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  throw StateError('Handshake timed out waiting for the pushed P21 inputs.');
}
