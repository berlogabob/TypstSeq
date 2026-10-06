import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/nextcloud_sync/chunked_upload.dart';

void main() {
  late HttpServer server;
  late Uri davBase;
  late HttpClient client;
  final requests = <String>[];
  final headers = <String, HttpHeaders>{};
  final chunks = <String, List<int>>{};
  List<int>? assembled;
  var failChunk2Once = false;
  var moveStatus = 201;
  var dirExists = false;

  setUp(() async {
    requests.clear();
    headers.clear();
    chunks.clear();
    assembled = null;
    failChunk2Once = false;
    moveStatus = 201;
    dirExists = false;
    client = HttpClient();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    davBase = Uri.parse('http://127.0.0.1:${server.port}/remote.php/dav');
    server.listen((request) async {
      final name = request.uri.pathSegments.last;
      requests.add('${request.method} $name');
      headers['${request.method} $name'] = request.headers;
      final body = await request.fold<List<int>>(
        [],
        (all, b) => all..addAll(b),
      );
      final response = request.response;
      switch (request.method) {
        case 'MKCOL':
          response.statusCode = dirExists ? 405 : 201;
          dirExists = true;
        case 'PUT' when name == '00002' && failChunk2Once:
          failChunk2Once = false;
          response.statusCode = 500;
        case 'PUT':
          chunks[name] = body;
          response.statusCode = 201;
        case 'MOVE':
          response.statusCode = moveStatus;
          if (moveStatus == 201) {
            assembled = [
              for (final k in chunks.keys.toList()..sort()) ...chunks[k]!,
            ];
            response.headers.set('ETag', '"abc"');
          }
      }
      await response.close();
    });
  });

  tearDown(() async {
    client.close(force: true);
    await server.close(force: true);
  });

  final payload = List.generate(12, (i) => i + 1);
  Future<String?> upload({Set<int> done = const {}, String? ifMatch}) =>
      chunkedUpload(
        client: client,
        davBase: davBase,
        user: 'admin',
        authHeader: 'Basic x',
        destinationPath: 'assets/фото 1.png',
        openRange: (start, end) => Stream.value(payload.sublist(start, end)),
        length: payload.length,
        uploadId: 'up1',
        chunkSize: 5,
        ifMatch: ifMatch,
        alreadyUploaded: done,
      );

  test('uploads three chunks, assembles them and returns the etag', () async {
    expect(await upload(), '"abc"');
    expect(requests, [
      'MKCOL up1',
      'PUT 00001',
      'PUT 00002',
      'PUT 00003',
      'MOVE .file',
    ]);
    expect(assembled, payload);
    final put = headers['PUT 00001']!;
    expect(put.value('oc-total-length'), '12');
    expect(
      put.value('destination'),
      '$davBase/files/admin/assets/'
      '${Uri.encodeComponent('фото 1.png')}',
    );
  });

  test('a failed chunk reports its number and the upload resumes', () async {
    failChunk2Once = true;
    await expectLater(
      upload(),
      throwsA(
        isA<ChunkUploadException>()
            .having((e) => e.chunkNumber, 'chunkNumber', 2)
            .having((e) => e.statusCode, 'statusCode', 500),
      ),
    );
    requests.clear();
    expect(await upload(done: {1}), '"abc"');
    expect(requests, ['MKCOL up1', 'PUT 00002', 'PUT 00003', 'MOVE .file']);
    expect(assembled, payload);
  });

  test('the MOVE conditions the destination and 412 is reported', () async {
    moveStatus = 412;
    await expectLater(
      upload(ifMatch: '"old"'),
      throwsA(
        isA<ChunkUploadException>()
            .having((e) => e.chunkNumber, 'chunkNumber', 0)
            .having((e) => e.statusCode, 'statusCode', 412),
      ),
    );
    final move = headers['MOVE .file']!;
    expect(move.value('if-match'), isNull);
    expect(move.value('if'), '<${move.value('destination')}> (["old"])');
  });
}
