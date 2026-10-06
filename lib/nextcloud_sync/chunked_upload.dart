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
  bool ifNoneMatch = false,
  String? localHash,
  Set<int> alreadyUploaded = const {},
  void Function(int)? onChunkUploaded,
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
    if (method == 'MOVE') {
      // If-Match/If-None-Match on a MOVE test the upload source, not the
      // destination (verified against Nextcloud: a correct destination ETag
      // answers 412). Condition the destination explicitly instead.
      if (ifMatch != null) {
        request.headers.set('If', '<$destination> ([$ifMatch])');
      }
      if (ifNoneMatch) request.headers.set('Overwrite', 'F');
      if (localHash != null) {
        request.headers.set('OC-Checksum', 'SHA256:$localHash');
      }
    }
    if (body != null) {
      request.contentLength = bodyLength!;
      await request.addStream(body).timeout(const Duration(minutes: 5));
    }
    final response = await request.close().timeout(const Duration(seconds: 60));
    await response.drain<void>().timeout(const Duration(seconds: 60));
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
    HttpClientResponse put;
    try {
      put = await send(
        'PUT',
        '$uploadDir/${n.toString().padLeft(5, '0')}',
        body: openRange(start, end),
        bodyLength: end - start,
      );
    } on IOException {
      throw ChunkUploadException(n, 503);
    } on TimeoutException {
      throw ChunkUploadException(n, 503);
    }
    if (put.statusCode != 201 && put.statusCode != 204) {
      throw ChunkUploadException(n, put.statusCode);
    }
    onChunkUploaded?.call(n);
  }

  final move = await send('MOVE', '$uploadDir/.file');
  if (move.statusCode != 201 && move.statusCode != 204) {
    throw ChunkUploadException(0, move.statusCode);
  }
  final remoteHash = move.headers.value('x-hash-sha256');
  if (remoteHash != null &&
      localHash != null &&
      remoteHash.toLowerCase() != localHash) {
    throw const HttpException('Chunked upload checksum mismatch');
  }
  return move.headers.value('oc-etag') ?? move.headers.value('etag');
}
