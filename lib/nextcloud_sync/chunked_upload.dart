import 'dart:io';
import 'dart:async';

class ChunkUploadException implements Exception {
  final int chunkNumber;
  final int statusCode;

  ChunkUploadException(this.chunkNumber, this.statusCode);

  @override
  String toString() {
    return 'ChunkUploadException(chunkNumber: $chunkNumber, statusCode: $statusCode)';
  }
}

Future<String?> chunkedUpload({
  required HttpClient client,
  required Uri davBase,
  required String user,
  required String authHeader,
  required String destinationPath,
  required Stream<List<int>> Function(int start, int end) openRange,
  required int length,
  required String uploadId,
  int chunkSize = 5 * 1024 * 1024,
  String? ifMatch,
  Set<int> alreadyUploaded = const {},
}) async {
  final destination =
      '$davBase/files/${Uri.encodeComponent(user)}/'
      '${destinationPath.split('/').map(Uri.encodeComponent).join('/')}';
  final uploadDir = '$davBase/uploads/${Uri.encodeComponent(user)}/$uploadId';

  Future<HttpClientResponse> send(
    String method,
    String url, {
    Stream<List<int>>? body,
    int? bodyLength,
    bool total = true,
  }) async {
    final request = await client.openUrl(method, Uri.parse(url));
    request.headers.set('Authorization', authHeader);
    request.headers.set('Destination', destination);
    if (total) request.headers.set('OC-Total-Length', '$length');
    if (method == 'MOVE' && ifMatch != null) {
      request.headers.set('If-Match', ifMatch);
    }
    if (body != null) {
      request.contentLength = bodyLength!;
      await request.addStream(body);
    }
    final response = await request.close();
    await response.drain<void>();
    return response;
  }

  // 405 = the upload directory already exists: a resumed upload.
  final mkcol = await send('MKCOL', uploadDir, total: false);
  if (mkcol.statusCode != 201 && mkcol.statusCode != 405) {
    throw ChunkUploadException(0, mkcol.statusCode);
  }

  final chunks = (length / chunkSize).ceil();
  for (var n = 1; n <= chunks; n++) {
    if (alreadyUploaded.contains(n)) continue;
    final start = (n - 1) * chunkSize;
    final end = start + chunkSize < length ? start + chunkSize : length;
    final put = await send(
      'PUT',
      '$uploadDir/${n.toString().padLeft(5, '0')}',
      body: openRange(start, end),
      bodyLength: end - start,
    );
    if (put.statusCode != 201 && put.statusCode != 204) {
      throw ChunkUploadException(n, put.statusCode);
    }
  }

  final move = await send('MOVE', '$uploadDir/.file');
  if (move.statusCode != 201 && move.statusCode != 204) {
    throw ChunkUploadException(0, move.statusCode);
  }
  return move.headers.value('oc-etag') ?? move.headers.value('etag');
}
