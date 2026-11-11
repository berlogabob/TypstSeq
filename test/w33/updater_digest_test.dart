import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/desktop_updater.dart';

void main() {
  const stableDigestUrl =
      'https://github.com/berlogabob/TypstSeq/releases/latest/download/'
      'TyLog-macos.zip.sha256';
  final digest = sha256.convert(utf8.encode('downloaded bytes')).toString();

  test('parses the selected asset digest and ignores malformed values', () {
    UpdateInfo? parse(Object? value) => parseLatestRelease(
      jsonEncode({
        'tag_name': 'v2.0.0',
        'assets': [
          {'name': 'other.zip', 'digest': 'sha256:${'a' * 64}'},
          {'name': 'TyLog-macos.zip', 'digest': value},
        ],
      }),
      currentVersion: '1.0.0',
    );

    expect(parse('sha256:${digest.toUpperCase()}')!.digest, digest);
    for (final invalid in [null, 123, 'sha256:abc', 'md5:$digest']) {
      expect(parse(invalid)!.digest, isNull);
    }
  });

  group('verifyDownloadedZip', () {
    late Directory temp;
    late File zip;
    late HttpClient client;
    HttpServer? server;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('updater-digest-test-');
      zip = File('${temp.path}/update.zip');
      await zip.writeAsString('downloaded bytes');
      client = HttpClient();
    });

    tearDown(() async {
      client.close(force: true);
      await server?.close(force: true);
      await temp.delete(recursive: true);
    });

    UpdateInfo info(String url, {String? inlineDigest}) => UpdateInfo(
      version: '2.0.0',
      notes: '',
      zipUrl: 'https://example.com/update.zip',
      digestUrl: url,
      htmlUrl: 'https://example.com',
      digest: inlineDigest,
    );

    Future<String> serve(int status, String body) async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server!.listen((request) {
        request.response.statusCode = status;
        request.response.write(body);
        request.response.close();
      });
      return 'http://127.0.0.1:${server!.port}/update.sha256';
    }

    test('accepts the published digest', () async {
      final url = await serve(200, '$digest  update.zip\n');
      await verifyDownloadedZip(zip, info(url), client);
    });

    test(
      'rejects a wrong published digest even with a correct inline digest',
      () async {
        final wrong = 'a' * 64;
        final url = await serve(200, wrong);
        await expectLater(
          verifyDownloadedZip(zip, info(url, inlineDigest: digest), client),
          throwsA(
            isA<UpdateNotVerified>()
                .having((e) => e.expected, 'expected', wrong)
                .having((e) => e.actual, 'actual', digest),
          ),
        );
      },
    );

    test('rejects a missing digest file', () async {
      final url = await serve(404, '');
      await expectLater(
        verifyDownloadedZip(zip, info(url), client),
        throwsA(
          isA<UpdateNotVerified>()
              .having((e) => e.expected, 'expected', isNull)
              .having((e) => e.actual, 'actual', digest),
        ),
      );
    });

    test('accepts the inline digest without fetching the stable URL', () async {
      await verifyDownloadedZip(
        zip,
        info(stableDigestUrl, inlineDigest: digest),
        client,
      );
    });
  });
}
