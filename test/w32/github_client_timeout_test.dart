import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/github/github_client.dart';

void main() {
  test(
    'GitHubClient request to a server that never responds throws TimeoutException',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((_) {});

      final client = GitHubClient(
        null,
        null,
        Uri.parse('http://127.0.0.1:${server.port}'),
      );
      client.timeout = const Duration(milliseconds: 300);

      expect(client.currentUser(), throwsA(isA<TimeoutException>()));
    },
  );
}
