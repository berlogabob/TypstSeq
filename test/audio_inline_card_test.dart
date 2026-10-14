import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/rich_editor.dart';

void main() {
  tearDown(() => TyLogEditingController.audioBuilder = null);

  testWidgets('audio attachment renders through audioBuilder, with or without /',
      (tester) async {
    final seen = <String>[];
    TyLogEditingController.audioBuilder = (path, label) {
      seen.add(path);
      return Text('CARD $label');
    };
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TyLogReadView(
            source:
                '#tylog.attachment("/assets/audio/a.m4a", kind: "audio")[a.m4a]\n\n'
                '#tylog.attachment("assets/audio/b.mp3", kind: "audio")[b.mp3]',
          ),
        ),
      ),
    );
    expect(find.text('CARD a.m4a'), findsOneWidget);
    expect(find.text('CARD b.mp3'), findsOneWidget);
    expect(seen, ['assets/audio/a.m4a', 'assets/audio/b.mp3']);
  });
}
