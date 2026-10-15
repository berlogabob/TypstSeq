// ignore_for_file: depend_on_referenced_packages
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tylog/widgets/app_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:tylog/app_mobile.dart';
import 'package:tylog/models.dart';
import 'package:tylog/vault.dart';
import 'package:tylog/vault_storage.dart';

Future<void> _emptyStartup() async {}

void main() {
  FlutterLocalNotificationsPlatform.instance = _FakeNotificationsPlatform();

  testWidgets(
    'share sheet follows content type and dismissal consumes the queue',
    (tester) async {
      final root = Directory.systemTemp.createTempSync('tylog_share_');
      addTearDown(() => root.deleteSync(recursive: true));
      const channel = MethodChannel('org.tylog.tylog/share');
      final messenger = tester.binding.defaultBinaryMessenger;
      Map<String, String>? pending;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'getPendingShare');
        final next = pending;
        pending = null;
        return next;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await tester.pumpWidget(
        const MaterialApp(home: HomeScreen(startup: _emptyStartup)),
      );
      await tester.pumpAndSettle();
      final dynamic home = tester.state(find.byType(HomeScreen));
      home.workspace.vault = Vault.withStorage(LocalVaultStorage(root));
      home.workspace.index = const VaultIndex(
        notesByPath: {},
        backlinksByTarget: {},
      );

      for (final scenario in [
        ({'text': 'A plain note'}, 'Add to today', AppIcons.today),
        (
          {'text': 'https://example.org/page'},
          'Save as article',
          Icons.article_outlined,
        ),
        (
          {
            'path': '/cache/photo.png',
            'name': 'photo.png',
            'mime': 'image/png',
            'text': 'https://example.org',
          },
          'Attach to today',
          Icons.image_outlined,
        ),
        (
          {
            'path': '/cache/voice.m4a',
            'name': 'voice.m4a',
            'mime': 'audio/mp4',
          },
          'Save as audio note',
          Icons.audiotrack,
        ),
        (
          {
            'path': '/cache/file.pdf',
            'name': 'file.pdf',
            'mime': 'application/pdf',
          },
          'Attach to today',
          Icons.attach_file,
        ),
      ]) {
        pending = scenario.$1;
        // Exercise the native-to-Dart notification, including the real queue loop.
        final delivered = messenger.handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('shareAvailable'),
          ),
          (_) {},
        );
        await tester.pumpAndSettle();
        final sheet = find.byType(BottomSheet);
        expect(sheet, findsOneWidget);
        expect(
          find.descendant(of: sheet, matching: find.text(scenario.$2)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: sheet, matching: find.byIcon(scenario.$3)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: sheet, matching: find.text('Default')),
          findsOneWidget,
        );
        final fileName = scenario.$1['name'];
        if (fileName != null) {
          expect(find.text(fileName), findsOneWidget);
          expect(find.text('Save as article'), findsNothing);
          expect(find.text('Add link to today'), findsNothing);
        } else if (scenario.$2 == 'Save as article') {
          expect(
            find.text('Fetch and convert the page to text'),
            findsOneWidget,
          );
          expect(find.text('Add link to today'), findsOneWidget);
        } else {
          expect(find.text('Save as article'), findsNothing);
        }
        Navigator.of(tester.element(sheet)).pop();
        await tester.pumpAndSettle();
        await delivered;
        expect(pending, isNull);
        expect(find.byType(BottomSheet), findsNothing);
      }
      expect(root.listSync(), isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

class _FakeNotificationsPlatform extends FlutterLocalNotificationsPlatform
    with MockPlatformInterfaceMixin {
  @override
  Future<void> cancelAll() async {}
}
