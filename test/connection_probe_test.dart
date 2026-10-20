import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/ai/connection_probe.dart';

void main() {
  late HttpServer server;
  late String url;
  late HttpClient client;
  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    url = 'http://127.0.0.1:${server.port}/v1';
    client = HttpClient();
  });
  tearDown(() async {
    client.close(force: true);
    await server.close(force: true);
  });

  test('models tolerate optional fields and send the key', () async {
    server.listen((request) async {
      expect(request.uri.path, '/v1/models');
      expect(request.headers.value('authorization'), 'Bearer secret');
      request.response.write(
        jsonEncode({
          'data': [
            {'id': 'loaded', 'loaded': true, 'context_length': 4096},
            {'id': 'unloaded', 'loaded': false, 'max_model_len': 8192},
            {'id': 'unknown', 'loaded': 'yes', 'context_length': '2048'},
            null,
            {'id': 7},
            {'id': ''},
          ],
        }),
      );
      await request.response.close();
    });
    var factories = 0;
    final probe = ConnectionProbe(
      clientFactory: () {
        factories++;
        return HttpClient();
      },
    );
    final result = await probe.probeServer('$url/', key: 'secret');
    expect(factories, 1);
    expect(result.ok, isTrue);
    expect(result.models.map((m) => m.id), ['loaded', 'unloaded', 'unknown']);
    expect(result.models.map((m) => m.loaded), [true, false, null]);
    expect(result.models.map((m) => m.contextLength), [4096, 8192, 2048]);
    expect(result.latencyMs, greaterThanOrEqualTo(0));
  });

  test('provider-specific model headers are sent', () async {
    var seen = <String, String?>{};
    server.listen((request) async {
      seen = {
        'authorization': request.headers.value('authorization'),
        'x-api-key': request.headers.value('x-api-key'),
        'anthropic-version': request.headers.value('anthropic-version'),
      };
      request.response.write('{"data":[]}');
      await request.response.close();
    });
    expect((await probeServer(url, key: 'openai-key')).ok, isTrue);
    expect(seen['authorization'], 'Bearer openai-key');
    expect(seen['x-api-key'], isNull);

    await server.close(force: true);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    url = 'http://127.0.0.1:${server.port}/v1';
    server.listen((request) async {
      seen = {
        'authorization': request.headers.value('authorization'),
        'x-api-key': request.headers.value('x-api-key'),
        'anthropic-version': request.headers.value('anthropic-version'),
      };
      request.response.write('{"data":[]}');
      await request.response.close();
    });
    expect(
      (await probeServer(url, key: 'anthropic-key', kind: 'anthropic')).ok,
      isTrue,
    );
    expect(seen['authorization'], isNull);
    expect(seen['x-api-key'], 'anthropic-key');
    expect(seen['anthropic-version'], '2023-06-01');
  });

  test('401 produces a useful error', () async {
    server.listen((request) async {
      request.response.statusCode = 401;
      await request.response.close();
    });
    final result = await probeServer(url, client: client);
    expect(result.ok, isFalse);
    expect(result.error, 'HTTP 401: key rejected');
  });

  test('non JSON and wrong envelopes are incompatible', () async {
    var count = 0;
    server.listen((request) async {
      request.response.write(
        count++ == 0 ? '<html>hello</html>' : '{"models":[]}',
      );
      await request.response.close();
    });
    for (var i = 0; i < 2; i++) {
      final result = await probeServer(url, client: client);
      expect(result.ok, isFalse);
      expect(result.error, 'Not an OpenAI-compatible server');
    }
  });

  test('chat request, trimmed reply and empty reply failure', () async {
    var count = 0;
    server.listen((request) async {
      expect(request.method, 'POST');
      expect(request.uri.path, '/v1/chat/completions');
      expect(jsonDecode(await utf8.decoder.bind(request).join()), {
        'model': 'llm',
        'temperature': 0,
        'max_tokens': 48,
        'messages': [
          {'role': 'user', 'content': 'Translate to Portuguese: Good morning'},
        ],
      });
      request.response.write(
        jsonEncode({
          'choices': [
            {
              'message': {'content': count++ == 0 ? '  Bom dia  ' : '  '},
            },
          ],
        }),
      );
      await request.response.close();
    });
    final result = await testModel(url, 'llm', client: client);
    expect(result.ok, isTrue);
    expect(result.reply, 'Bom dia');
    final empty = await testModel(url, 'llm', client: client);
    expect(empty.ok, isFalse);
    expect(
      empty.error,
      "Empty reply: the model's context window may be too small or the model is not loaded",
    );
  });

  test('closed port and invalid URL never throw', () async {
    await server.close(force: true);
    expect((await probeServer(url, client: client)).error, 'Cannot connect');
    expect((await testModel('not a URL', 'llm', client: client)).ok, isFalse);
  });
}
