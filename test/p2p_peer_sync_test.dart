import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/nextcloud_sync.dart';
import 'package:tylog/p2p/vault_dav_server.dart';
import 'package:tylog/vault.dart';
import 'support/temp_dir.dart';

/// A paired peer is synced by the ordinary engine against the peer's vault
/// served as WebDAV. Here the tunnel is skipped: the client talks to the
/// server's loopback port directly, which is all the tunnel forwards to.
void main() {
  test('two vaults converge through the peer DAV server', () async {
    final root = await Directory.systemTemp.createTemp('p2p-peer-');
    addTearDown(() => deleteTempDir(root));
    final a = Vault(await Directory('${root.path}/a').create());
    await a.ensureCreated();
    for (var i = 0; i < 5; i++) {
      await a.saveNote('notes/n$i.typ', 'Note $i — тест');
    }
    final asset = Uint8List(300 * 1024)..fillRange(0, 1024, 7);
    await a.storage.writeBytes('assets/pic.bin', asset);

    final written = <String>[];
    var notified = 0;
    final server = VaultDavServer(
      storage: a.storage,
      password: 'secret',
      generation: a.writeGeneration,
      onWritten: written.add,
      onNotify: () => notified++,
    );
    final port = await server.start();
    addTearDown(server.close);

    const peerId = 'a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6';
    final config = NextcloudConfig(
      serverUrl: 'http://127.0.0.1:$port${VaultDavServer.rootPath}',
      username: 'peer',
      password: 'secret',
      kind: 'peer',
      peerId: peerId,
    );
    expect(config.isReady, isTrue);
    expect(config.isWebDav, isTrue);

    final b = Vault(await Directory('${root.path}/b').create());
    await b.ensureCreated();
    await NextcloudSync(config).sync(b);
    for (var i = 0; i < 5; i++) {
      expect(await b.storage.readText('notes/n$i.typ'), 'Note $i — тест');
    }
    expect(await b.storage.readBytes('assets/pic.bin'), asset);
    // Cursors live in a per-peer file; the server's file stays untouched.
    expect(
      await b.storage.exists('.tylog/sync_state.peer-a1b2c3d4e5f6a7b8.json'),
      isTrue,
    );
    expect(await b.storage.exists('.tylog/sync_state.json'), isFalse);

    // B -> A
    await b.saveNote('notes/n1.typ', 'Edited on b');
    await NextcloudSync(config).sync(b);
    expect(await a.storage.readText('notes/n1.typ'), 'Edited on b');
    expect(written, contains('notes/n1.typ'));

    // A -> B
    await a.saveNote('notes/n2.typ', 'Edited on a');
    await NextcloudSync(config).sync(b);
    expect(await b.storage.readText('notes/n2.typ'), 'Edited on a');

    // Deletion on A reaches B.
    await a.storage.delete('notes/n3.typ');
    await NextcloudSync(config).sync(b);
    expect(await b.storage.exists('notes/n3.typ'), isFalse);

    // Deletion on B reaches A.
    await b.storage.delete('notes/n0.typ');
    await NextcloudSync(config).sync(b);
    expect(await a.storage.exists('notes/n0.typ'), isFalse);

    // Both sides edit: one conflict, nothing lost.
    await a.saveNote('notes/n4.typ', 'A version');
    await b.saveNote('notes/n4.typ', 'B version');
    await NextcloudSync(config).sync(b);
    final conflicts = await loadSyncConflicts(b);
    expect(conflicts.map((c) => c.path), contains('notes/n4.typ'));
    expect(await a.storage.readText('notes/n4.typ'), 'A version');

    // Nothing changed: a second pass writes nothing on A.
    written.clear();
    await NextcloudSync(config).sync(b);
    expect(written, isEmpty);
    expect(notified, 0);
  });

  test(
    'the peer DAV server hides internal paths and needs the password',
    () async {
      final root = await Directory.systemTemp.createTemp('p2p-dav-');
      addTearDown(() => deleteTempDir(root));
      final a = Vault(await Directory('${root.path}/a').create());
      await a.ensureCreated();
      await a.saveNote('notes/x.typ', 'x');
      await a.storage.writeText('.tylog/secret.json', '{}');
      var notified = 0;
      final server = VaultDavServer(
        storage: a.storage,
        password: 'secret',
        onNotify: () => notified++,
      );
      final port = await server.start();
      addTearDown(server.close);
      final client = HttpClient();
      addTearDown(client.close);

      Future<int> call(
        String method,
        String path, {
        String password = 'secret',
      }) async {
        final request = await client.openUrl(
          method,
          Uri.parse('http://127.0.0.1:$port$path'),
        );
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Basic ${base64Encode(utf8.encode('peer:$password'))}',
        );
        final response = await request.close();
        await response.drain<void>();
        return response.statusCode;
      }

      const dav = VaultDavServer.rootPath;
      expect(await call('GET', '${dav}notes/x.typ'), 200);
      expect(await call('GET', '${dav}notes/x.typ', password: 'nope'), 401);
      expect(await call('GET', '$dav.tylog/secret.json'), 404);
      expect(await call('GET', '${dav}notes/../.tylog/secret.json'), 404);
      expect(await call('PUT', '$dav.tylog/evil.json'), 403);
      expect(await call('DELETE', '$dav.tylog/secret.json'), 404);
      expect(await a.storage.exists('.tylog/secret.json'), isTrue);
      expect(await call('POST', '/tylog-notify'), 204);
      expect(notified, 1);
    },
  );

  test('a peer and the server each keep their own pending writes', () async {
    final root = await Directory.systemTemp.createTemp('p2p-pending-');
    addTearDown(() => deleteTempDir(root));
    final vault = Vault(await Directory('${root.path}/v').create());
    await vault.ensureCreated();
    await vault.saveNote('notes/early.typ', 'before the peer existed');
    // A peer first asked mid-run still sees writes from earlier in the run.
    expect(vault.pendingSyncWritesFor('peer-1'), contains('notes/early.typ'));
    vault.clearPendingSyncWrites(['notes/early.typ']);
    expect(vault.pendingSyncWrites, isNot(contains('notes/early.typ')));
    expect(vault.pendingSyncWritesFor('peer-1'), contains('notes/early.typ'));
    vault.clearPendingSyncWrites(['notes/early.typ'], remote: 'peer-1');
    expect(vault.pendingSyncWritesFor('peer-1'), isEmpty);
    await vault.saveNote('notes/late.typ', 'after');
    expect(vault.pendingSyncWrites, contains('notes/late.typ'));
    expect(vault.pendingSyncWritesFor('peer-1'), contains('notes/late.typ'));
    expect(vault.writeGeneration('notes/late.typ'), greaterThan(0));
  });
}
