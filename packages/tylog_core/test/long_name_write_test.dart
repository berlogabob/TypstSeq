import 'dart:io';

import 'package:test/test.dart';
import 'package:tylog_core/tylog_core.dart';

void main() {
  test('atomic write handles a name at the 255-byte limit', () async {
    final dir = await Directory.systemTemp.createTemp('longname_');
    addTearDown(() => dir.delete(recursive: true));
    // 125 two-byte letters + '.typ' = 254 bytes, like long Cyrillic titles.
    // Fails pre-fix on ext4 (Linux CI, Android); APFS counts characters.
    final name = '${'ж' * 125}.typ';
    final storage = LocalVaultStorage(dir);
    await storage.writeText('articles/$name', 'ok');
    expect(await storage.readText('articles/$name'), 'ok');
    expect(
      Directory('${dir.path}/articles').listSync().map((e) => e.path),
      hasLength(1),
    );
  });
}
