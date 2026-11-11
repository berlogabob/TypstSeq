import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/nextcloud_sync/login_flow.dart';

void main() {
  test(
    'pollLoginFlow throws TimeoutException when the poll endpoint never responds',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((_) {});

      final start = LoginFlowStart(
        Uri.parse('http://127.0.0.1:${server.port}/login'),
        Uri.parse('http://127.0.0.1:${server.port}/poll'),
        'tok',
      );

      expect(
        pollLoginFlow(
          start,
          requestTimeout: const Duration(milliseconds: 300),
          timeout: const Duration(seconds: 5),
        ),
        throwsA(isA<TimeoutException>()),
      );
    },
  );
}
