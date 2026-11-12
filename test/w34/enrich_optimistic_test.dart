import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/widgets/enrich_review.dart';
import 'package:tylog_core/tylog_core.dart';

void main() {
  testWidgets(
    'accept hides immediately and a declined loan restores the card',
    (tester) async {
      final result = Completer<bool>();
      const equipment = NoteRef(
        id: 'eq',
        path: 'eq.typ',
        title: 'Camera',
        kind: 'equipment',
        outgoingLinks: [],
      );
      const loan = EnrichLoanOffer(
        line: 1,
        text: 'Borrowed Camera',
        ledgerSurface: 'Camera',
        equipment: [equipment],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                EnrichReview(
                  source: 'Borrowed Camera',
                  decisions: const [],
                  loans: const [loan],
                  onAccept: (_, _) {},
                  onReject: (_, _) {},
                  onCreate: (_) {},
                  onIgnore: (_) {},
                  onAcceptLoan: (_) => result.future,
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.text('Borrowed Camera'), findsOneWidget);
      expect(find.byType(Scrollable), findsOneWidget);
      await tester.tap(find.text('Track loan'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Borrowed Camera'), findsNothing);
      result.complete(false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Borrowed Camera'), findsOneWidget);
    },
  );
}
