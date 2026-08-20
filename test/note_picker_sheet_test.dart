import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/widgets/note_picker_sheet.dart';
import 'package:tylog_core/models.dart';

NoteRef _note(String id, String title, {List<String> aliases = const []}) =>
    NoteRef(
      id: id,
      path: 'notes/$id.typ',
      title: title,
      aliases: aliases,
      outgoingLinks: const [],
    );

void main() {
  final notes = [
    _note('esp32', 'ESP32'),
    _note('home', 'Home Assistant'),
    _note('godot', 'Godot', aliases: ['engine']),
  ];

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: NotePickerSheet(notes: notes, createLabel: 'Create note'),
      ),
    ),
  );

  testWidgets('filter narrows by substring across title and alias',
      (tester) async {
    await pump(tester);
    expect(find.text('ESP32'), findsOneWidget);
    expect(find.text('Home Assistant'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'assist');
    await tester.pump();
    expect(find.text('Home Assistant'), findsOneWidget);
    expect(find.text('ESP32'), findsNothing);

    await tester.enterText(find.byType(TextField), 'engine');
    await tester.pump();
    expect(find.text('Godot'), findsOneWidget, reason: 'alias must match');
  });

  testWidgets('create row survives filtering', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), 'zzz-no-match');
    await tester.pump();
    expect(find.text('Create note'), findsOneWidget);
  });
}
