import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tylog/widgets/dialogs.dart';
import 'package:tylog/widgets/ds/app_sheet.dart';

void main() {
  testWidgets(
    'destructive confirmation uses error fill and Cancel on the left',
    (tester) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showConfirmDialog(
                    context,
                    title: 'Delete saved search?',
                    message: 'Delete this search?',
                    confirmLabel: 'Delete',
                    destructive: true,
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      final scheme = Theme.of(
        tester.element(find.byType(AlertDialog)),
      ).colorScheme;
      expect(button.style!.backgroundColor!.resolve({}), scheme.error);
      expect(button.style!.foregroundColor!.resolve({}), scheme.onError);
      expect(
        tester.getCenter(find.text('Cancel')).dx,
        lessThan(tester.getCenter(find.text('Delete')).dx),
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
    },
  );

  testWidgets(
    'typed destructive confirmation stays disabled until exact match',
    (tester) async {
      final typed = TextEditingController();
      addTearDown(typed.dispose);
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showConfirmDialog(
                    context,
                    title: 'Confirm permanent deletion',
                    contentBuilder: (_) => TextField(controller: typed),
                    confirmChanges: typed,
                    canConfirm: () => typed.text == 'Vault',
                    confirmLabel: 'Delete permanently',
                    destructive: true,
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.enterText(find.byType(TextField), 'vault');
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.enterText(find.byType(TextField), 'Vault');
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
      await tester.tap(find.text('Delete permanently'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    },
  );

  testWidgets('AppSheet keeps long picker bodies bounded and scrollable', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 250,
            child: AppSheet.body(
              title: 'Choose note',
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const TextField(),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: 50,
                      itemBuilder: (_, i) => ListTile(title: Text('Note $i')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final list = find.descendant(
      of: find.byType(AppSheet),
      matching: find.byType(ListView),
    );
    expect(list, findsOneWidget);
    expect(
      tester.getSize(find.byType(AppSheet)).height,
      lessThanOrEqualTo(250),
    );
    await tester.scrollUntilVisible(
      find.text('Note 49'),
      200,
      scrollable: find.descendant(of: list, matching: find.byType(Scrollable)),
    );
    expect(find.text('Note 49'), findsOneWidget);
    expect(find.text('Note 49').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
