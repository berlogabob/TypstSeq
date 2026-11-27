import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tylog/widgets/ds/ds.dart';
import 'package:tylog/widgets/text_note_widgets.dart';

Future<void> _open(WidgetTester tester, String? current) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: tyLogTheme(Brightness.light),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => chooseNoteText(
              context,
              originalAvailable: true,
              languages: const ['en', 'ru'],
              target: 'en',
              current: current,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

// The first match is the row's own title; "English" also appears as the
// Side by side subtitle.
ListTile _row(WidgetTester tester, String title) => tester.widget<ListTile>(
  find
      .ancestor(of: find.text(title).first, matching: find.byType(ListTile))
      .first,
);

void main() {
  testWidgets('marks the text on screen', (tester) async {
    await _open(tester, 'ru');
    expect(_row(tester, 'Русский').selected, isTrue);
    expect(_row(tester, 'Original').selected, isFalse);
    expect(_row(tester, 'English').selected, isFalse);
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('marks the original', (tester) async {
    await _open(tester, 'original');
    expect(_row(tester, 'Original').selected, isTrue);
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('marks nothing when the caller does not say', (tester) async {
    await _open(tester, null);
    expect(find.byIcon(Icons.check), findsNothing);
  });
}
