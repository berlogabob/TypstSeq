import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/models.dart';
import 'package:tylog/widgets/share_from_sheet.dart';
import 'support/temp_dir.dart';

void main() {
  const person = NoteRef(
    id: 'a"b',
    path: 'notes/a.typ',
    title: 'Ann [A]',
    kind: 'person',
    outgoingLinks: [],
  );
  const source =
      '#import "/_system/tylog.typ" as tylog\n\n= Audio\n\nFrom: #tylog.ref-note("day")[Today]\n\n== Comments\n';
  testWidgets(
    'sender chooser explains empty recents and search results on a phone',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ShareFromSheet(notes: [person], recent: []),
          ),
        ),
      );
      expect(find.text('Search for a person or page'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'nobody');
      await tester.pump();
      expect(find.text('No matching people or pages'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Ann');
      await tester.pump();
      expect(find.text('Ann [A]'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  for (final choose in [true, false]) {
    testWidgets(
      choose
          ? 'choosing a sender adds one compiling link'
          : 'skipping leaves the note unchanged',
      (tester) async {
        var saved = source;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    final selected = await showModalBottomSheet<NoteRef>(
                      context: context,
                      builder: (_) => const ShareFromSheet(
                        notes: [person],
                        recent: ['a"b'],
                      ),
                    );
                    if (selected != null) {
                      saved = addShareSender(saved, selected);
                    }
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(choose ? 'Ann [A]' : 'Skip'));
        await tester.pumpAndSettle();
        if (!choose) {
          expect(saved, source);
          return;
        }
        expect(RegExp(r'#tylog\.ref-note\(').allMatches(saved).length, 2);
        expect(saved, contains(r'From: #tylog.ref-note("a\"b")[Ann \[A\]]'));
        expect(saved, contains('From: #tylog.ref-note("day")[Today]'));
        await tester.runAsync(() async {
          final dir = await Directory.systemTemp.createTemp('share_from_');
          addTearDown(() => deleteTempDir(dir));
          await Directory('${dir.path}/_system').create();
          await File(
            'typst/tylog/lib.typ',
          ).copy('${dir.path}/_system/tylog.typ');
          await File('${dir.path}/a.typ').writeAsString(saved);
          final result = await Process.run('typst', [
            'compile',
            '--root',
            dir.path,
            '${dir.path}/a.typ',
            '${dir.path}/a.pdf',
          ]);
          expect(result.exitCode, 0, reason: result.stderr.toString());
        });
      },
    );
  }
}
