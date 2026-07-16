import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tylog/nextcloud_sync.dart';
import 'package:tylog/vault.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'native 1602-file ZIP restore and bidirectional renames',
    (_) async {
      final fixture = _fixture();
      final fixtureCount = fixture.length;
      final archiveServer = await _NativeWebDavServer.start(
        fixture,
        serveArchive: true,
      );
      final archiveRoot = await Directory.systemTemp.createTemp(
        'tylog_native_archive_',
      );
      final archiveVault = Vault(archiveRoot);
      addTearDown(() async {
        await archiveServer.close();
        await archiveRoot.delete(recursive: true);
      });
      await archiveVault.ensureCreated();

      final archiveWatch = Stopwatch()..start();
      final restored = await NextcloudSync(
        archiveServer.config,
      ).sync(archiveVault, initialMode: InitialSyncMode.downloadRemote);
      archiveWatch.stop();

      expect(restored.downloaded, fixtureCount);
      expect(archiveServer.propfinds, 2);
      expect(archiveServer.archiveGets, 1);
      expect(archiveServer.individualGets, 0);

      const localOld = 'articles/0000.typ';
      const localNew = 'articles/local-renamed.typ';
      await archiveVault.storage.writeBytes(
        localNew,
        await archiveVault.storage.readBytes(localOld),
      );
      await archiveVault.storage.delete(localOld);
      final localRename = await NextcloudSync(
        archiveServer.config,
      ).sync(archiveVault);
      expect(localRename.renamed, 1);
      expect(archiveServer.files, isNot(contains(localOld)));
      expect(archiveServer.files, contains(localNew));

      const remoteOld = 'articles/0001.typ';
      const remoteNew = 'articles/remote-renamed.typ';
      archiveServer.files[remoteNew] = archiveServer.files.remove(remoteOld)!;
      final remoteRename = await NextcloudSync(
        archiveServer.config,
      ).sync(archiveVault);
      expect(remoteRename.renamed, 1);
      expect(await archiveVault.storage.exists(remoteOld), isFalse);
      expect(await archiveVault.storage.exists(remoteNew), isTrue);

      final fallbackFixture = _fixture();
      final fallbackCount = fallbackFixture.length;
      final fallbackServer = await _NativeWebDavServer.start(
        fallbackFixture,
        serveArchive: false,
        individualDelay: const Duration(milliseconds: 80),
      );
      final fallbackRoot = await Directory.systemTemp.createTemp(
        'tylog_native_fallback_',
      );
      final fallbackVault = Vault(fallbackRoot);
      addTearDown(() async {
        await fallbackServer.close();
        await fallbackRoot.delete(recursive: true);
      });
      await fallbackVault.ensureCreated();

      final fallbackWatch = Stopwatch()..start();
      await NextcloudSync(
        fallbackServer.config,
      ).sync(fallbackVault, initialMode: InitialSyncMode.downloadRemote);
      fallbackWatch.stop();

      expect(fallbackServer.archiveGets, 1);
      expect(fallbackServer.individualGets, fallbackCount);
      expect(
        fallbackWatch.elapsedMilliseconds,
        greaterThanOrEqualTo(archiveWatch.elapsedMilliseconds * 4),
        reason:
            'ZIP ${archiveWatch.elapsedMilliseconds}ms; '
            'four-worker fallback ${fallbackWatch.elapsedMilliseconds}ms',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

Map<String, _NativeRemoteFile> _fixture() {
  final filler = List.filled(12 * 1024, 'x').join();
  return {
    '_system/tylog.typ': _NativeRemoteFile.fromText('helper'),
    for (var i = 0; i < 1602; i++)
      'articles/${i.toString().padLeft(4, '0')}.typ':
          _NativeRemoteFile.fromText('article $i\n$filler'),
  };
}

class _NativeRemoteFile {
  const _NativeRemoteFile({required this.bytes, required this.etag});

  factory _NativeRemoteFile.fromText(String source) {
    final bytes = utf8.encode(source);
    return _NativeRemoteFile(bytes: bytes, etag: '"${sha256.convert(bytes)}"');
  }

  final List<int> bytes;
  final String etag;
}

class _NativeWebDavServer {
  _NativeWebDavServer._(
    this.server,
    this.files, {
    required this.serveArchive,
    required this.individualDelay,
  });

  static const _root = '/remote.php/dav/files/native/TyLogVault/';

  static Future<_NativeWebDavServer> start(
    Map<String, _NativeRemoteFile> files, {
    required bool serveArchive,
    Duration individualDelay = Duration.zero,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fixture = _NativeWebDavServer._(
      server,
      files,
      serveArchive: serveArchive,
      individualDelay: individualDelay,
    );
    server.listen(fixture._handle);
    return fixture;
  }

  final HttpServer server;
  final Map<String, _NativeRemoteFile> files;
  final bool serveArchive;
  final Duration individualDelay;
  int propfinds = 0;
  int archiveGets = 0;
  int individualGets = 0;

  NextcloudConfig get config => NextcloudConfig(
    serverUrl:
        'http://${server.address.address}:${server.port}'
        '/remote.php/dav/files/native/TyLogVault',
    username: 'native',
    password: 'test',
  );

  Future<void> close() => server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path.startsWith(_root)
        ? request.uri.path.substring(_root.length)
        : '';
    try {
      switch (request.method) {
        case 'MKCOL':
          request.response.statusCode = HttpStatus.methodNotAllowed;
          break;
        case 'PROPFIND':
          propfinds++;
          request.response.statusCode = 207;
          request.response.write(
            '<d:multistatus xmlns:d="DAV:" '
            'xmlns:oc="http://owncloud.org/ns">',
          );
          for (final entry in files.entries) {
            final hash = sha256.convert(entry.value.bytes);
            request.response.write(
              '<d:response><d:href>$_root${entry.key}</d:href>'
              '<d:propstat><d:prop>'
              '<d:getlastmodified>Wed, 01 Jan 2030 00:00:00 GMT</d:getlastmodified>'
              '<d:getetag>${entry.value.etag}</d:getetag>'
              '<d:getcontentlength>${entry.value.bytes.length}</d:getcontentlength>'
              '<oc:checksums><oc:checksum>SHA256:$hash</oc:checksum>'
              '</oc:checksums></d:prop></d:propstat></d:response>',
            );
          }
          request.response.write('</d:multistatus>');
          break;
        case 'GET':
          if (path.isEmpty) {
            archiveGets++;
            if (!serveArchive) {
              request.response.statusCode = HttpStatus.notFound;
              break;
            }
            final archive = Archive();
            for (final entry in files.entries) {
              archive.addFile(
                ArchiveFile.bytes('TyLogVault/${entry.key}', entry.value.bytes),
              );
            }
            final bytes = ZipEncoder().encodeBytes(archive);
            request.response.contentLength = bytes.length;
            request.response.add(bytes);
            break;
          }
          individualGets++;
          if (individualDelay != Duration.zero) {
            await Future<void>.delayed(individualDelay);
          }
          final file = files[path];
          if (file == null) {
            request.response.statusCode = HttpStatus.notFound;
          } else {
            request.response.contentLength = file.bytes.length;
            request.response.headers.set(HttpHeaders.etagHeader, file.etag);
            request.response.add(file.bytes);
          }
          break;
        case 'PUT':
          final bytes = await request.fold<List<int>>(
            [],
            (all, chunk) => all..addAll(chunk),
          );
          final file = _NativeRemoteFile(
            bytes: bytes,
            etag: '"${sha256.convert(bytes)}"',
          );
          files[path] = file;
          request.response.statusCode = HttpStatus.created;
          request.response.headers.set('OC-Etag', file.etag);
          request.response.headers.set('X-Hash-SHA256', sha256.convert(bytes));
          break;
        case 'MOVE':
          final source = files[path];
          final destination = request.headers.value('destination');
          final destinationPath = destination == null
              ? null
              : Uri.parse(destination).path;
          final target =
              destinationPath != null && destinationPath.startsWith(_root)
              ? destinationPath.substring(_root.length)
              : null;
          if (source == null ||
              target == null ||
              files.containsKey(target) ||
              request.headers.value(HttpHeaders.ifMatchHeader) != source.etag) {
            request.response.statusCode = HttpStatus.preconditionFailed;
          } else {
            files.remove(path);
            files[target] = source;
            request.response.statusCode = HttpStatus.created;
            request.response.headers.set('OC-Etag', source.etag);
          }
          break;
        case 'DELETE':
          files.remove(path);
          request.response.statusCode = HttpStatus.noContent;
          break;
        default:
          request.response.statusCode = HttpStatus.methodNotAllowed;
      }
    } finally {
      await request.response.close();
    }
  }
}
