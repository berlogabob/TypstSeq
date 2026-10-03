// ignore_for_file: avoid_print
// Real-account host rehearsal. Production vault is read-only; all mutations
// and databases live in temporary directories, remote writes in one scratch.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/database/note_persistence.dart';
import 'package:tylog/database/portable_import.dart';
import 'package:tylog/database/portable_snapshot.dart';
import 'package:tylog/database/revision_publisher.dart';
import 'package:tylog/database/tylog_database.dart';
import 'package:tylog/nextcloud_sync.dart';
import 'package:tylog/vault.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

final _env = Platform.environment;
final _configured = [
  'NC_URL',
  'NC_USER',
  'NC_PW',
  'P24_VAULT_ROOT',
].every((key) => (_env[key] ?? '').isNotEmpty);

void main() {
  test(
    'P24 real-vault migration, interrupted sync, restore and restart',
    () async {
      final folder = 'TyLogP24Scratch-${DateTime.now().millisecondsSinceEpoch}';
      final config = NextcloudConfig(
        serverUrl: _env['NC_URL']!,
        username: _env['NC_USER']!,
        password: _env['NC_PW']!,
        remoteFolder: folder,
      );
      addTearDown(() => _deleteRemote(config, folder));
      final root = await Directory.systemTemp.createTemp('tylog_p24_');
      addTearDown(() => root.delete(recursive: true));
      final aDir = await Directory('${root.path}/a').create();
      final bDir = await Directory('${root.path}/b').create();
      final source = Directory(_env['P24_VAULT_ROOT']!);
      final sample = await _copySample(source, aDir);
      // The vault marker makes the copy a valid v5 vault, as in production.
      await Directory('${aDir.path}/.tylog').create();
      await File('${source.path}/.tylog/settings.json')
          .copy('${aDir.path}/.tylog/settings.json');
      final sourceBefore = await _hashPaths(source, sample);
      var a = Vault(aDir);
      var b = Vault(bDir);
      var dbA = await openDatabaseWithFile(File('${root.path}/a.sqlite'));
      var dbB = await openDatabaseWithFile(File('${root.path}/b.sqlite'));
      addTearDown(() async {
        await dbA.close();
        await dbB.close();
      });
      final before = await _hashPaths(aDir, sample);
      // Production vault initialization performs storage/helper migration. Existing
      // Typst notes use the same durable note persistence as workspace writes.
      await a.ensureCreated();
      await b.ensureCreated();
      for (final path in sample.where((path) => path.endsWith('.typ'))) {
        await persistVaultNote(
          dbA,
          path: path,
          source: await a.storage.readText(path),
          nowMs: 1,
        );
      }
      expect(await _hashPaths(aDir, sample), before);
      expect(await _hashPaths(source, sample), sourceBefore);
      expect(await dbA.select(dbA.nodes).get(), isNotEmpty);

      // The local WebDAV failure fixture tears down a transfer socket and disables
      // transient retries. This relay uses that same fault against real scratch
      // PUTs after two completed transfers, without touching the real server.
      final relay = await _FaultRelay.start(config.serverUrl);
      addTearDown(relay.close);
      final proxied = NextcloudConfig(
        serverUrl: relay.url,
        username: config.username,
        password: config.password,
        remoteFolder: folder,
      );
      final retryDelays = NextcloudSync.connectionRetryDelays;
      NextcloudSync.connectionRetryDelays = const [];
      addTearDown(() => NextcloudSync.connectionRetryDelays = retryDelays);
      Future<SyncResult> pass(
        Vault vault,
        TyLogDatabase db, {
        InitialSyncMode? mode,
      }) async {
        final publisher = RevisionPublisher(db);
        final ids = <String>[];
        while (true) {
          final page = await publisher.materialize(
            write: vault.storage.writeBytes,
            limit: 1000,
          );
          ids.addAll(page);
          if (page.length < 1000) break;
        }
        final result = await NextcloudSync(
          proxied,
        ).sync(vault, initialMode: mode);
        final envelopes = <RevisionEnvelope>[];
        for (final file in await vault.storage.list(
          path: '_system/revisions',
        )) {
          if (!file.isDirectory && file.path.endsWith('.json')) {
            envelopes.add(
              RevisionPublisher.decodeEnvelope(
                await vault.storage.readBytes(file.path),
              ),
            );
          }
        }
        envelopes.sort(
          (a, b) => a.revision.createdAtMs.compareTo(b.revision.createdAtMs),
        );
        for (final envelope in envelopes) {
          if (envelope.node != null) {
            await db.receiveRevision(
              node: envelope.node!,
              revision: envelope.revision,
            );
          }
        }
        await publisher.acknowledge(ids);
        return result;
      }

      final initial = await pass(a, dbA, mode: InitialSyncMode.uploadLocal);
      expect(initial.conflicts, 0);
      expect(initial.uploaded, greaterThan(0));
      for (var i = 0; i < 5; i++) {
        final path = 'notes/p24-recovery-$i.typ';
        expect(await a.storage.exists(path), isFalse);
        final content = '= P24 recovery $i\n\nCommitted edit $i\n';
        await a.saveNote(path, content);
        await persistVaultNote(dbA, path: path, source: content, nowMs: 10 + i);
      }
      relay.interrupt = true;
      Object? interruptError;
      try {
        await pass(a, dbA);
      } catch (error) {
        interruptError = error;
      }
      print('P24 interrupt error: ${interruptError.runtimeType} '
          '${'$interruptError'.split('\n').first.replaceAll(RegExp(r'https?://\S+'), '<url>')}');
      expect(interruptError, isNotNull);
      // Uploads run in parallel, so the abort can land before any PUT
      // completes; the dropped PUT is what this step must prove.
      expect(relay.dropped, greaterThan(0));
      final interruptedPuts = relay.completedPuts;
      relay.interrupt = false;
      final recovered = await pass(a, dbA);
      expect(recovered.conflicts, 0);
      final aManifest = await _manifest(a);
      final restored = await pass(b, dbB, mode: InitialSyncMode.downloadRemote);
      expect(restored.conflicts, 0);
      expect(restored.downloaded, greaterThan(0));
      final bManifest = await _manifest(b);
      final onlyA = aManifest.keys.where((k) => !bManifest.containsKey(k));
      final onlyB = bManifest.keys.where((k) => !aManifest.containsKey(k));
      final differ = aManifest.keys.where(
        (k) => bManifest.containsKey(k) && bManifest[k] != aManifest[k],
      );
      print('P24 restore diff: onlyA=${onlyA.length} ${onlyA.take(5).toList()} '
          'onlyB=${onlyB.length} ${onlyB.take(5).toList()} '
          'differ=${differ.length} ${differ.take(5).toList()}');
      expect(bManifest, aManifest);
      expect(
        (await dbB.select(dbB.nodes).get()).map((n) => n.id).toSet(),
        (await dbA.select(dbA.nodes).get()).map((n) => n.id).toSet(),
      );
      expect(
        aManifest.keys.where((path) => path.startsWith('notes/p24-recovery-')),
        hasLength(5),
      );

      const conflictPath = 'notes/p24-recovery-0.typ';
      const localA = '= P24 recovery 0\n\nDevice A edit\n';
      const localB = '= P24 recovery 0\n\nDevice B edit\n';
      await a.saveNote(conflictPath, localA);
      await b.saveNote(conflictPath, localB);
      await persistVaultNote(
        dbA,
        path: conflictPath,
        source: localA,
        nowMs: 30,
      );
      await persistVaultNote(
        dbB,
        path: conflictPath,
        source: localB,
        nowMs: 31,
      );
      await pass(a, dbA);
      expect((await pass(b, dbB)).conflicts, greaterThan(0));
      final conflicts = await loadSyncConflicts(b);
      final conflict = conflicts.singleWhere((c) => c.path == conflictPath);
      expect(await b.storage.readText(conflict.localSnapshot!), localB);
      expect(await b.storage.readText(conflict.remoteSnapshot!), localA);
      expect(await b.storage.readText(conflictPath), localB);
      await NextcloudSync(
        proxied,
      ).resolveConflict(b, conflict, SyncConflictResolution.keepRemote);
      await pass(b, dbB);
      await pass(a, dbA);
      // Stabilize the remote root etag after the last revision upload.
      await pass(b, dbB);
      await pass(a, dbA);
      final stableA = await _manifest(a);
      final stableB = await _manifest(b);
      final rowsA = await dbA.select(dbA.nodes).get();
      final rowsB = await dbB.select(dbB.nodes).get();
      await dbA.close();
      await dbB.close();
      a = Vault(aDir);
      b = Vault(bDir);
      dbA = await openDatabaseWithFile(File('${root.path}/a.sqlite'));
      dbB = await openDatabaseWithFile(File('${root.path}/b.sqlite'));
      expect(await dbA.select(dbA.nodes).get(), rowsA);
      expect(await dbB.select(dbB.nodes).get(), rowsB);
      for (final (vault, db) in [(a, dbA), (b, dbB)]) {
        final result = await pass(vault, db);
        expect(result.uploaded, 0);
        expect(result.downloaded, 0);
        expect(result.conflicts, 0);
      }
      expect(await _manifest(a), stableA);
      expect(await _manifest(b), stableB);

      final bytes = await exportPortableSnapshot(
        database: dbB,
        storage: b.storage,
      );
      final cDir = await Directory('${root.path}/roundtrip').create();
      final c = Vault(cDir);
      final dbC = await openDatabaseWithFile(File('${root.path}/c.sqlite'));
      addTearDown(dbC.close);
      final imported = await importPortableSnapshot(
        database: dbC,
        storage: c.storage,
        bytes: bytes,
      );
      expect(imported.hasConflicts, isFalse);
      expect(imported.insertedRows, greaterThan(0));
      expect(await dbC.select(dbC.nodes).get(), unorderedEquals(rowsB));
      final snapshot = parsePortableSnapshot(bytes);
      for (final entry in snapshot.vaultFiles.entries) {
        expect(
          await c.storage.hash(entry.key),
          sha256.convert(entry.value).toString(),
        );
      }
      final again = await importPortableSnapshot(
        database: dbC,
        storage: c.storage,
        bytes: bytes,
      );
      expect(again.hasConflicts, isFalse);
      expect(again.insertedRows, 0);
      expect(again.insertedFiles, 0);
      expect(
        await exportPortableSnapshot(database: dbC, storage: c.storage),
        bytes,
      );
      expect(await _hashPaths(source, sample), sourceBefore);
      // ignore: avoid_print
      print(
        'P24 real-account: notes=${sample.where((s) => s.endsWith('.typ')).length}, '
        'attachments=${sample.where((s) => !s.endsWith('.typ')).length}, '
        'synced=${aManifest.length}, interrupted=${relay.dropped} '
        '(after $interruptedPuts PUTs), '
        'restored=${restored.downloaded}, conflicts=${conflicts.length}, '
        'restart=unchanged, imported=${imported.insertedRows}, repeat=0',
      );
    },
    skip: !_configured,
    timeout: const Timeout(Duration(minutes: 20)),
  );
}

Future<Map<String, String>> _hashPaths(
  Directory dir,
  Iterable<String> paths,
) async => {
  for (final path in paths)
    path: sha256
        .convert(await File('${dir.path}/$path').readAsBytes())
        .toString(),
};

// Keyed by NFC: an NFD local name and its NFC restore are the same note.
Future<Map<String, String>> _manifest(Vault vault) async => {
  for (final file in await vault.storage.list(recursive: true))
    if (!file.isDirectory && isSyncableVaultPath(file.path))
      unorm.nfc(file.path): await vault.storage.hash(file.path),
};

Future<List<String>> _copySample(Directory source, Directory target) async {
  final files = <String>[];
  await for (final entity in source.list(recursive: true, followLinks: false)) {
    if (entity is File) {
      files.add(entity.path.substring(source.path.length + 1));
    }
  }
  files.sort();
  final notes = files
      .where(
        (path) =>
            path.endsWith('.typ') &&
            isSyncableVaultPath(path) &&
            !path.startsWith('_system/'),
      )
      .take(300)
      .toList();
  expect(notes, isNotEmpty);
  final references = <String>{};
  for (final path in notes) {
    final text = await File('${source.path}/$path').readAsString();
    for (final match in RegExp(r'''["']([^"'\r\n]+)["']''').allMatches(text)) {
      final raw = match[1]!;
      for (final candidate in [
        Uri(path: path).resolveUri(Uri(path: raw)).normalizePath().path,
        Uri(
          path: raw.startsWith('/') ? raw.substring(1) : raw,
        ).normalizePath().path,
      ]) {
        if (files.contains(candidate) &&
            !candidate.endsWith('.typ') &&
            isSyncableVaultPath(candidate)) {
          references.add(candidate);
        }
      }
    }
  }
  var size = 0;
  final selected = <String>[];
  for (final path in [...notes, ...(references.toList()..sort()).take(20)]) {
    final file = File('${source.path}/$path');
    final length = await file.length();
    if (size + length > 50 * 1024 * 1024) {
      if (path.endsWith('.typ')) {
        fail('First 300 notes exceed 50 MiB sample cap');
      }
      continue;
    }
    size += length;
    final destination = File('${target.path}/$path');
    await destination.parent.create(recursive: true);
    await file.copy(destination.path);
    selected.add(path);
  }
  return selected;
}

class _FaultRelay {
  _FaultRelay(this.server, this.upstream);
  final HttpServer server;
  final Uri upstream;
  // Pass bodies through untouched; their Content-Encoding header is relayed.
  final client = HttpClient()..autoUncompress = false;
  bool interrupt = false;
  int completedPuts = 0;
  int dropped = 0;
  int _puts = 0;
  String get url => 'http://127.0.0.1:${server.port}';
  static Future<_FaultRelay> start(String url) async {
    final relay = _FaultRelay(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
      Uri.parse(url.replaceAll(RegExp(r'/+$'), '')),
    );
    relay.server.listen(relay.handle);
    return relay;
  }

  Future<void> handle(HttpRequest request) async {
    try {
      if (interrupt && request.method == 'PUT' && ++_puts > 2) {
        dropped++;
        final socket = await request.response.detachSocket(writeHeaders: false);
        socket.destroy();
        return;
      }
      final uri = upstream.replace(
        path: '${upstream.path}${request.uri.path}',
        query: request.uri.hasQuery ? request.uri.query : null,
      );
      final outgoing = await client.openUrl(request.method, uri);
      request.headers.forEach((key, values) {
        if (key != HttpHeaders.hostHeader) outgoing.headers.set(key, values);
      });
      await outgoing.addStream(request);
      final response = await outgoing.close();
      request.response.statusCode = response.statusCode;
      response.headers.forEach(
        (key, values) => request.response.headers.set(key, values),
      );
      await request.response.addStream(response);
      await request.response.close();
      if (interrupt && request.method == 'PUT' && response.statusCode < 300) {
        completedPuts++;
      }
    } catch (_) {
      // Do not expose URLs, user names or authorization in host-test output.
      request.response.statusCode = HttpStatus.badGateway;
      await request.response.close();
    }
  }

  Future<void> close() async {
    client.close(force: true);
    await server.close(force: true);
  }
}

Future<void> _deleteRemote(NextcloudConfig config, String folder) async {
  final client = HttpClient();
  try {
    final base = config.serverUrl.replaceAll(RegExp(r'/+$'), '');
    final request = await client.deleteUrl(
      Uri.parse('$base/remote.php/dav/files/${config.username}/$folder'),
    );
    request.headers
      ..set(
        HttpHeaders.authorizationHeader,
        'Basic ${base64Encode(utf8.encode('${config.username}:${config.password}'))}',
      )
      ..set(HttpHeaders.userAgentHeader, 'Mozilla/5.0 (TyLog P19 test)');
    await (await request.close()).drain<void>();
  } finally {
    client.close(force: true);
  }
}
