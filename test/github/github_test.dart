import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/github/github_auth.dart';
import 'package:tylog/github/github_client.dart';

class RealHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HttpServer server;
  late Uri base;
  late HttpClient http;
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    http = HttpOverrides.runWithHttpOverrides(
      () => HttpClient(),
      RealHttpOverrides(),
    );
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = Uri.parse('http://${server.address.address}:${server.port}');
  });
  tearDown(() {
    http.close(force: true);
    return server.close(force: true);
  });

  test(
    'repository issues include all pages and exclude pull requests',
    () async {
      server.listen((request) async {
        expect(request.uri.path, '/repos/a/b/issues');
        expect(request.uri.queryParameters['state'], 'all');
        final page = request.uri.queryParameters['page'];
        final rows = page == '1'
            ? List.generate(100, (i) => {'number': i + 1, 'title': 'Issue $i'})
            : [
                {'number': 101, 'pull_request': {}},
              ];
        request.response.write(jsonEncode(rows));
        await request.response.close();
      });
      final issues = await GitHubClient(
        null,
        http,
        base,
      ).repositoryIssues('a/b');
      expect(issues, hasLength(100));
    },
  );

  test('issue search encodes spaces in the query', () async {
    server.listen((request) async {
      expect(request.uri.path, '/search/issues');
      expect(
        request.uri.queryParameters['q'],
        'repo:a/b "tylog-issue: path#hash" in:body',
      );
      expect(request.uri.query, contains('%20'));
      expect(request.uri.query, isNot(contains('%2B')));
      request.response.write('{"items":[]}');
      await request.response.close();
    });
    await GitHubClient(
      null,
      http,
      base,
    ).searchIssues('a/b', 'tylog-issue: path#hash');
  });

  test('device flow handles pending, slow down and saves token', () async {
    var polls = 0;
    final delays = <Duration>[];
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path.endsWith('/code')) {
        expect(body, contains('scope=repo'));
        request.response.write(
          jsonEncode({
            'device_code': 'd',
            'user_code': 'u',
            'verification_uri': 'https://github.com',
            'expires_in': 600,
            'interval': 1,
          }),
        );
      } else {
        polls++;
        request.response.write(
          jsonEncode(
            polls == 1
                ? {'error': 'authorization_pending'}
                : polls == 2
                ? {'error': 'slow_down'}
                : {'access_token': 'secret'},
          ),
        );
      }
      await request.response.close();
    });
    final auth = GitHubAuth(
      client: http,
      baseUri: base,
      clientId: 'id',
      delay: (d) async => delays.add(d),
    );
    final code = await auth.requestDeviceCode();
    expect(await auth.pollForToken(code), 'secret');
    expect(await auth.token(), 'secret');
    expect(delays.map((d) => d.inSeconds), [1, 1, 6]);
  });

  test('expired device code is reported', () async {
    server.listen((request) async {
      request.response.write('{"error":"expired_token"}');
      await request.response.close();
    });
    final auth = GitHubAuth(
      client: http,
      baseUri: base,
      clientId: 'id',
      delay: (_) async {},
    );
    expect(
      () => auth.pollForToken(
        const DeviceCodeResponse(
          deviceCode: 'd',
          userCode: 'u',
          verificationUri: 'v',
          expiresIn: 60,
          interval: 1,
        ),
      ),
      throwsA(
        isA<GitHubDeviceFlowError>().having(
          (e) => e.code,
          'code',
          'expired_token',
        ),
      ),
    );
  });

  test('conflict and rate limit are distinguished', () async {
    server.listen((request) async {
      await request.drain<void>();
      if (request.method == 'PUT') {
        request.response.statusCode = 422;
        request.response.write('{"message":"sha does not match"}');
      } else {
        request.response.statusCode = 403;
        request.response.headers.set('x-ratelimit-remaining', '0');
        request.response.headers.set('x-ratelimit-reset', '1234');
      }
      await request.response.close();
    });
    final client = GitHubClient(null, http, base);
    expect(
      () => client.putContent('a/b', 'x', [1], 'm', branch: 'main'),
      throwsA(isA<GitHubConflict>()),
    );
    expect(
      () => client.commitSha('a/b', 'main'),
      throwsA(
        isA<GitHubRateLimit>().having(
          (e) => e.resetTime!.millisecondsSinceEpoch,
          'reset',
          1234000,
        ),
      ),
    );
  });

  test('zipball follows redirect and rejects oversized response', () async {
    var large = false;
    server.listen((request) async {
      if (request.uri.path.contains('zipball')) {
        request.response.statusCode = 302;
        request.response.headers.set('location', '/archive');
      } else if (large) {
        request.response.headers.contentLength = GitHubClient.maxZipBytes + 1;
        request.response.add([0]);
        await request.response.flush();
      } else {
        request.response.add([1, 2, 3]);
      }
      await request.response.close().catchError((_) {});
    });
    final client = GitHubClient(null, http, base);
    expect(await client.downloadZipball('a/b', 'main'), [1, 2, 3]);
    large = true;
    expect(() => client.downloadZipball('a/b', 'main'), throwsStateError);
  });
}
