import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/nextcloud_sync.dart';
import 'package:tylog/nextcloud_sync/login_flow.dart';
import 'package:tylog/widgets/nextcloud_connect_dialog.dart';

void main() {
  for (final outcome in ['approve', 'cancel', 'error']) {
    testWidgets('browser login $outcome uses the manual config result', (
      tester,
    ) async {
      final approval = Completer<LoginFlowResult>();
      final login = LoginFlowStart(
        Uri.parse('https://cloud.example/login'),
        Uri.parse('https://cloud.example/poll'),
        'token',
      );
      Uri? opened;
      Uri? started;
      HttpClient? active;
      NextcloudConfig? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              child: const Text('Connect'),
              onPressed: () async {
                saved = await showDialog<NextcloudConfig>(
                  context: context,
                  builder: (_) => NextcloudConnectDialog(
                    start: (server, {client}) async {
                      started = server;
                      active = client;
                      return login;
                    },
                    poll:
                        (
                          start, {
                          client,
                          interval = const Duration(seconds: 2),
                          timeout = const Duration(minutes: 5),
                        }) {
                          expect(start, same(login));
                          expect(client, same(active));
                          return approval.future;
                        },
                    openBrowser: (uri) async {
                      opened = uri;
                      return true;
                    },
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Server URL'),
        'https://cloud.example/',
      );
      await tester.tap(find.text('Sign in with browser'));
      await tester.pumpAndSettle();
      expect(started, Uri.parse('https://cloud.example'));
      expect(opened, login.loginUrl);
      expect(find.text('Waiting for approval…'), findsOneWidget);
      if (outcome == 'cancel') {
        await tester.tap(find.text('Cancel').first);
        await tester.pumpAndSettle();
        approval.complete(
          const LoginFlowResult('https://approved.example', 'alice', 'secret'),
        );
        await tester.pumpAndSettle();
        expect(saved, isNull);
        expect(find.text('Sign in with browser'), findsOneWidget);
      } else if (outcome == 'error') {
        approval.completeError(const HttpException('approval failed'));
        await tester.pumpAndSettle();
        expect(find.textContaining('approval failed'), findsOneWidget);
        expect(saved, isNull);
      } else {
        approval.complete(
          const LoginFlowResult('https://approved.example', 'alice', 'secret'),
        );
        await tester.pumpAndSettle();
        expect(saved?.serverUrl, 'https://approved.example');
        expect(saved?.username, 'alice');
        expect(saved?.password, 'secret');
        expect(saved?.remoteFolder, 'TyLogVault');
        expect(find.text('Connect Nextcloud'), findsNothing);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
}
