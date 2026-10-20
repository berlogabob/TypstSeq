import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/nextcloud_sync.dart';
import 'package:tylog/vault.dart';

/// The 'WebDAV (any server)' backend against a real server: rclone's WebDAV
/// on loopback. Skipped where rclone is not installed (CI).
void main() {
  final rclone = Process.runSync('which', ['rclone']).stdout.toString().trim();

  test(
    'two vaults converge through rclone serve webdav, large file included',
    () async {
      final root = await Directory.systemTemp.createTemp('rclone-webdav-');
      addTearDown(() => root.delete(recursive: true));
      final served = await Directory('${root.path}/served').create();
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = probe.port;
      await probe.close();
      final server = await Process.start(rclone, [
        'serve',
        'webdav',
        served.path,
        '--addr',
        '127.0.0.1:$port',
        '--user',
        'alice',
        '--pass',
        'secret',
      ]);
      addTearDown(server.kill);
      for (var i = 0; i < 50; i++) {
        try {
          await (await Socket.connect('127.0.0.1', port)).close();
          break;
        } on SocketException {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
      final config = NextcloudConfig(
        serverUrl: 'http://127.0.0.1:$port/',
        username: 'alice',
        password: 'secret',
        kind: 'webdav',
      );
      expect(config.isReady, isTrue);

      final a = Vault(await Directory('${root.path}/a').create());
      await a.ensureCreated();
      for (var i = 0; i < 20; i++) {
        await a.saveNote('notes/n$i.typ', 'Note $i — тест');
      }
      // Above the 10 MB chunk threshold: plain WebDAV must take one PUT.
      final big = Uint8List(12 * 1024 * 1024)..fillRange(0, 1024, 7);
      await a.storage.writeBytes('assets/big.bin', big);
      await NextcloudSync(config).sync(a);

      final b = Vault(await Directory('${root.path}/b').create());
      await b.ensureCreated();
      await NextcloudSync(config).sync(b);
      for (var i = 0; i < 20; i++) {
        expect(await b.storage.readText('notes/n$i.typ'), 'Note $i — тест');
      }
      expect(await b.storage.readBytes('assets/big.bin'), big);

      await b.saveNote('notes/n3.typ', 'Edited on b');
      await NextcloudSync(config).sync(b);
      await NextcloudSync(config).sync(a);
      expect(await a.storage.readText('notes/n3.typ'), 'Edited on b');

      await a.storage.delete('notes/n5.typ');
      await NextcloudSync(config).sync(a);
      await NextcloudSync(config).sync(b);
      expect(await b.storage.exists('notes/n5.typ'), isFalse);
      expect(File('${served.path}/notes/n5.typ').existsSync(), isFalse);
    },
    skip: rclone.isEmpty ? 'rclone not installed' : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
