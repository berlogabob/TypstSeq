@Tags(['real-account'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/nextcloud_sync/chunked_upload.dart';

final _env = Platform.environment;
final _configured = [
  'NC_URL',
  'NC_USER',
  'NC_PW',
].every((key) => (_env[key] ?? '').isNotEmpty);

void main() {
  test(
    'chunked upload round-trips 12 MB against the real server',
    () async {
      {
        final user = _env['NC_USER']!;
        final auth =
            'Basic ${base64.encode(utf8.encode('$user:${_env['NC_PW']}'))}';
        final dav = Uri.parse('${_env['NC_URL']}/remote.php/dav');
        final name =
            'tylog-chunk-probe-${DateTime.now().millisecondsSinceEpoch}.bin';
        final random = Random(1);
        final bytes = List<int>.generate(
          12 * 1024 * 1024,
          (_) => random.nextInt(256),
        );
        final client = HttpClient();
        final target = Uri.parse('$dav/files/$user/$name');
        Future<HttpClientResponse> send(String method) async {
          final request = await client.openUrl(method, target);
          request.headers.set('Authorization', auth);
          return request.close();
        }

        try {
          final etag = await chunkedUpload(
            client: client,
            davBase: dav,
            user: user,
            authHeader: auth,
            destinationPath: name,
            openRange: (start, end) => Stream.value(bytes.sublist(start, end)),
            length: bytes.length,
            uploadId: 'tylog-$name',
          );
          expect(etag, isNotNull);
          final response = await send('GET');
          expect(response.statusCode, 200);
          final digest = await sha256.bind(response).first;
          expect(digest, sha256.convert(bytes));
          // Conditions must test the destination (If-Match on a MOVE tests
          // the upload source and answers 412 even for a correct ETag).
          Future<int> attempt(
            String id, {
            String? match,
            bool none = false,
          }) async {
            try {
              await chunkedUpload(
                client: client,
                davBase: dav,
                user: user,
                authHeader: auth,
                destinationPath: name,
                openRange: (start, end) =>
                    Stream.value(bytes.sublist(start, end)),
                length: bytes.length,
                uploadId: 'tylog-$id-$name',
                ifMatch: match,
                ifNoneMatch: none,
              );
              return 200;
            } on ChunkUploadException catch (e) {
              return e.statusCode;
            }
          }

          expect(await attempt('stale', match: '"0000000000000"'), 412);
          expect(await attempt('new', none: true), 412);
          expect(await attempt('current', match: etag), 200);
        } finally {
          await (await send('DELETE')).drain<void>();
          client.close();
        }
      }
    },
    skip: !_configured,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
