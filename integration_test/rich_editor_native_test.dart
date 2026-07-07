import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tylog/rich_editor.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android rich editor keeps Cyrillic input and live formatting', (
    tester,
  ) async {
    String? source;
    final errors = <Object>[];
    final controller = TyLogEditingController(
      source: '''#show: tylog.note.with(id: "test", title: "Test", kind: "note")
= Test

начало
''',
      onSourceChanged: (value) => source = value,
      onError: errors.add,
      onProtectedTap: (_) {},
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TyLogRichEditor(
            controller: controller,
            readOnly: false,
            onInsert: () {},
          ),
        ),
      ),
    );
    final field = find.byKey(const Key('rich-journal-editor'));
    await tester.tap(field);
    await tester.enterText(field, 'привет, как дела?');
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 6);
    await tester.tap(find.byTooltip('Bold'));
    await tester.pump();

    expect(controller.text, 'привет, как дела?');
    expect(source, contains('#strong[привет], как дела?'));
    expect(errors, isEmpty);
  });
}
