import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/retrieval/semantic_model.dart';

void main() {
  late HttpServer server;
  late Directory root;
  final files = {
    'model_O4.onnx': [1, 2, 3],
    'tokenizer.json': [4, 5, 6],
  };
  late List<SemanticModelFile> manifest;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    root = await Directory.systemTemp.createTemp('semantic-model-test-');
    manifest = [
      for (final entry in files.entries)
        SemanticModelFile(
          entry.key,
          entry.value.length,
          sha256.convert(entry.value).toString(),
        ),
    ];
    server.listen((request) async {
      final name = request.uri.pathSegments.last;
      final bytes = files[name]!;
      request.response.add(bytes.sublist(0, 1));
      await request.response.flush();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      request.response.add(bytes.sublist(1));
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    if (await root.exists()) await root.delete(recursive: true);
  });

  SemanticModelStore store() => SemanticModelStore(
    root,
    manifest: manifest,
    baseUrl: 'http://${server.address.host}:${server.port}',
  );

  test('downloads and verifies the pinned files', () async {
    await store().download();
    final installed = await store().installed();
    expect(installed?.model, endsWith('model_O4.onnx'));
    expect(installed?.tokenizer, endsWith('tokenizer.json'));
    expect(await File('${root.path}/verified').exists(), isTrue);
  });

  test('sha mismatch leaves no install or part files', () async {
    manifest = [SemanticModelFile('model_O4.onnx', 3, 'wrong')];
    await expectLater(store().download(), throwsStateError);
    expect(await store().installed(), isNull);
    expect(await File('${root.path}/model_O4.onnx.part').exists(), isFalse);
    expect(await File('${root.path}/model_O4.onnx').exists(), isFalse);
  });

  test('cancellation removes partial files', () async {
    var cancel = false;
    await expectLater(
      store().download(
        onProgress: (received, _) {
          if (received >= 1) cancel = true;
        },
        cancelled: () => cancel,
      ),
      throwsA(isA<Exception>()),
    );
    expect(await store().installed(), isNull);
    expect(await File('${root.path}/model_O4.onnx.part').exists(), isFalse);
  });

  test('marker is required for installed', () async {
    await File(
      '${root.path}/model_O4.onnx',
    ).writeAsBytes(files['model_O4.onnx']!);
    await File(
      '${root.path}/tokenizer.json',
    ).writeAsBytes(files['tokenizer.json']!);
    expect(await store().installed(), isNull);
  });
}
