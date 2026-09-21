import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/widgets/virtual_plain_editor.dart';

void main() {
  testWidgets('builds visible rows and keeps undo working', (tester) async {
    final source = List.generate(220, (i) => 'paragraph $i').join('\n\n');
    var changed = source;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            child: VirtualPlainEditor(
              source: source,
              onChanged: (value) => changed = value,
            ),
          ),
        ),
      ),
    );

    expect(find.byType(TextField), findsAtLeastNWidgets(1));
    expect(find.byType(TextField).evaluate().length, lessThan(220));
    await tester.enterText(find.byType(TextField).first, 'edited');
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 120));
    expect(changed, startsWith('edited'));
    await tester.tap(find.byTooltip('Undo'));
    await tester.pump();
    expect(changed, source);
  });
}
