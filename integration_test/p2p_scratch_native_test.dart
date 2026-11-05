import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:typst_flutter/typst_flutter.dart' as p2p;
import 'package:tylog/widgets/settings/p2p_scratch_page.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('scratch text crosses the native iroh bridge', (tester) async {
    if (Platform.isAndroid) {
      expect(
        await const MethodChannel(
          'org.tylog.tylog/share',
        ).invokeMethod<bool>('isProfileTest'),
        isTrue,
      );
    }
    await p2p.initP2pHarness();
    await tester.pumpWidget(
      MaterialApp(
        home: P2pScratchPage(
          start: (text) => p2p.startP2pScratch(text),
          receive: (ticket) async => (await p2p.receiveP2pScratch(ticket)).text,
        ),
      ),
    );
    tester
            .widget<TextField>(find.byKey(const ValueKey('scratch-text')))
            .controller!
            .text =
        'scratch fixture';
    await tester.tap(find.text('Create ticket'));
    await tester.pump();
    await tester.runAsync(() async {
      for (
        var i = 0;
        i < 600 && find.byType(SelectableText).evaluate().isEmpty;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
      }
    });
    final ticket = tester
        .widget<SelectableText>(find.byType(SelectableText))
        .data!;
    expect(ticket, startsWith('{'));
    tester
            .widget<TextField>(find.byKey(const ValueKey('scratch-ticket')))
            .controller!
            .text =
        ticket;
    await tester.tap(find.text('Receive'));
    await tester.pump();
    await tester.runAsync(() async {
      for (
        var i = 0;
        i < 600 && find.byType(SelectableText).evaluate().isEmpty;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
      }
    });
    expect(
      tester.widget<SelectableText>(find.byType(SelectableText)).data,
      'scratch fixture',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));
}
