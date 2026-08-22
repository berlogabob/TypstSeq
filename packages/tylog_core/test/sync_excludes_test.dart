import 'dart:io';

import 'package:test/test.dart';
import 'package:tylog_core/tylog_core.dart';

/// The vault commonly lives inside `~/Nextcloud`, and the desktop client
/// uploads whatever it finds there — including the search index, which
/// tokenises whole note bodies and so carries note text.
///
/// The app wrote this file; `initializeVaultStorage` did not. So the CLI, the
/// context most likely to be pointed at a desktop vault inside a synced folder,
/// was the one that never got it.
void main() {
  late Directory root;
  late LocalVaultStorage storage;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('tylog_excludes_');
    storage = LocalVaultStorage(root);
  });
  tearDown(() => root.delete(recursive: true));

  test('an existing exclude list is never overwritten', () async {
    await storage.writeText('.sync-exclude.lst', '# hand written\nmine\n');
    await writeSyncExcludes(storage);

    expect(
      await storage.readText('.sync-exclude.lst'),
      '# hand written\nmine\n',
      reason: "the user's own rules must survive",
    );
  });
}
