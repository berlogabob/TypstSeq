import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/nextcloud_sync.dart';
import 'package:tylog/nextcloud_sync/push_client.dart';

void main() {
  test('push authenticates, notifies, and reconnects after a drop', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <WebSocket>[];
    addTearDown(() async {
      for (final socket in sockets) {
        await socket.close();
      }
      await server.close(force: true);
    });
    var connections = 0;
    var notifications = 0;
    final done = Completer<void>();
    server.listen((request) async {
      if (request.uri.path == '/nextcloud/ocs/v2.php/cloud/capabilities') {
        expect(request.uri.queryParameters['format'], 'json');
        expect(request.headers.value('OCS-APIRequest'), 'true');
        expect(
          request.headers.value(HttpHeaders.authorizationHeader),
          'Basic ${base64Encode(utf8.encode('test-user:test-password'))}',
        );
        request.response.write(
          jsonEncode({
            'ocs': {
              'data': {
                'capabilities': {
                  'notify_push': {
                    'endpoints': {
                      'websocket': 'ws://127.0.0.1:${server.port}/push',
                    },
                  },
                },
              },
            },
          }),
        );
        await request.response.close();
        return;
      }
      final socket = await WebSocketTransformer.upgrade(request);
      sockets.add(socket);
      final connection = ++connections;
      final messages = <dynamic>[];
      socket.listen((message) async {
        messages.add(message);
        if (messages.length != 2) return;
        expect(messages, ['test-user', 'test-password']);
        socket.add('notify_file before-auth');
        socket.add('authenticated');
        socket.add('notify_activity');
        socket.add(connection == 1 ? 'notify_file 42' : 'notify_file');
        if (connection == 1) await socket.close();
      });
    });
    final client = NextcloudPushClient(
      NextcloudConfig(
        serverUrl: 'http://127.0.0.1:${server.port}/nextcloud',
        username: 'test-user',
        password: 'test-password',
      ),
      onFilesChanged: () {
        if (++notifications == 2) done.complete();
      },
    );
    addTearDown(client.close);
    client.start();
    await done.future.timeout(const Duration(seconds: 10));
    expect(connections, 2);
    expect(notifications, 2);
    client.close();
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    expect(connections, 2);
  });
}
