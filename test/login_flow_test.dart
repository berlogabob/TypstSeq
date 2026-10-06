import 'dart:io';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/nextcloud_sync/login_flow.dart';

void main() {
  late HttpServer server;
  late int port;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    port = server.port;
  });

  tearDown(() async {
    await server.close();
  });

  group('startLoginFlow', () {
    test('returns loginUrl, pollEndpoint, and token', () async {
      server.listen((HttpRequest request) {
        if (request.uri.path == '/index.php/login/v2' &&
            request.method == 'POST') {
          request.response.statusCode = 200;
          request.response.write(
            '{"poll":{"token":"test-token","endpoint":"/poll/endpoint"},"login":"https://example.com/login"}',
          );
          request.response.close();
        } else {
          request.response.statusCode = 404;
          request.response.close();
        }
      });

      final Uri serverUri = Uri.parse('http://localhost:$port');
      final LoginFlowStart result = await startLoginFlow(serverUri);

      expect(result.loginUrl.toString(), 'https://example.com/login');
      expect(
        result.pollEndpoint.toString(),
        'http://localhost:$port/poll/endpoint',
      );
      expect(result.token, 'test-token');
    });

    test('throws FormatException on HTTP 500', () async {
      server.listen((HttpRequest request) {
        if (request.uri.path == '/index.php/login/v2' &&
            request.method == 'POST') {
          request.response.statusCode = 500;
          request.response.close();
        } else {
          request.response.statusCode = 404;
          request.response.close();
        }
      });

      final Uri serverUri = Uri.parse('http://localhost:$port');
      expect(() => startLoginFlow(serverUri), throwsA(isA<FormatException>()));
    });
  });

  group('pollLoginFlow', () {
    test('returns result after two 404s', () async {
      int requestCount = 0;
      server.listen((HttpRequest request) {
        if (request.uri.path == '/index.php/login/v2') {
          request.response.statusCode = 200;
          request.response.write(
            '{"poll":{"token":"test-token","endpoint":"/poll/endpoint"},"login":"https://example.com/login"}',
          );
          request.response.close();
        } else if (request.uri.path == '/poll/endpoint') {
          if (request.method == 'POST') {
            requestCount++;
            if (requestCount <= 2) {
              // Return 404 for first two requests
              request.response.statusCode = 404;
              request.response.close();
            } else {
              // Return success on third request
              request.response.statusCode = 200;
              request.response.write(
                '{"server":"test-server","loginName":"test-user","appPassword":"test-app-password"}',
              );
              request.response.close();
            }
          } else {
            request.response.statusCode = 404;
            request.response.close();
          }
        } else {
          request.response.statusCode = 404;
          request.response.close();
        }
      });

      final Uri serverUri = Uri.parse('http://localhost:$port');
      final LoginFlowStart start = await startLoginFlow(serverUri);

      final LoginFlowResult result = await pollLoginFlow(
        start,
        interval: const Duration(milliseconds: 10),
        timeout: const Duration(milliseconds: 100),
      );

      expect(result.server, 'test-server');
      expect(result.loginName, 'test-user');
      expect(result.appPassword, 'test-app-password');
    });

    test('throws TimeoutException when always 404', () async {
      server.listen((HttpRequest request) {
        if (request.uri.path == '/index.php/login/v2') {
          request.response.statusCode = 200;
          request.response.write(
            '{"poll":{"token":"test-token","endpoint":"/poll/endpoint"},"login":"https://example.com/login"}',
          );
          request.response.close();
        } else if (request.uri.path == '/poll/endpoint') {
          request.response.statusCode = 404;
          request.response.close();
        } else {
          request.response.statusCode = 404;
          request.response.close();
        }
      });

      final Uri serverUri = Uri.parse('http://localhost:$port');
      final LoginFlowStart start = await startLoginFlow(serverUri);

      expect(
        () => pollLoginFlow(
          start,
          interval: const Duration(milliseconds: 10),
          timeout: const Duration(milliseconds: 50),
        ),
        throwsA(isA<TimeoutException>()),
      );
    });
  });
}
