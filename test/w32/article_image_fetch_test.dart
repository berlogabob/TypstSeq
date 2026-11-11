import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/markdown_article_import.dart';
import 'package:tylog_core/storage.dart';
import '../support/temp_dir.dart';

void main() {
  test('downloadArticleImages leaves the link and reports a diagnostic '
      'when the image hangs or is oversize', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (request.uri.path == '/hang') {
        return;
      }
      request.response.headers.contentType = ContentType('image', 'png');
      request.response.add(Uint8List(5000));
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));
    final base = 'http://${server.address.host}:${server.port}';

    final root = await Directory.systemTemp.createTemp('tylog-md-fetch-');
    addTearDown(() => deleteTempDir(root));
    final storage = LocalVaultStorage(root);

    final result = await downloadArticleImages(
      typst:
          'a #link("$base/hang")[Image: h] b '
          '#link("$base/big.png")[Image: b] c',
      articleId: 'md-x',
      storage: storage,
      fetchTimeout: const Duration(milliseconds: 300),
      maxImageBytes: 1000,
    );

    expect(result.typst, contains('#link("$base/hang")[Image: h]'));
    expect(result.typst, contains('#link("$base/big.png")[Image: b]'));
    expect(result.typst, isNot(contains('#image(')));
    expect(result.diagnostics.length, 2);
    expect(
      result.diagnostics.every((d) => d.code == 'remote-image-failed'),
      isTrue,
    );
  });
}
