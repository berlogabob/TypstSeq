import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/widgets/settings/p2p_scratch_page.dart';

void main() {
  testWidgets('scratch transfer copies a ticket and displays received text', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: P2pScratchPage(
          start: (text) async => 'ticket:$text',
          receive: (ticket) async => 'received:$ticket',
        ),
      ),
    );
    await tester.enterText(find.byKey(const ValueKey('scratch-text')), 'hello');
    await tester.tap(find.text('Create ticket'));
    await tester.pumpAndSettle();
    expect(find.text('ticket:hello'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('scratch-ticket')),
      'peer',
    );
    await tester.tap(find.text('Receive'));
    await tester.pumpAndSettle();
    expect(find.text('received:peer'), findsOneWidget);
  });
}
