import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/models.dart';
import 'package:tylog/widgets/screenshot_view.dart';

const source =
    '#show: tylog.note.with(id: "shot-a", title: "Cervejaria", kind: "screenshot")\n\n'
    '#image("/assets/screenshots/2026/02/shot-a.webp", width: 100%)\n\n'
    '== Description\n\n'
    'An ad for a \\#bar.\n\n'
    '== Text\n\n'
    'CAMADA A CAMADA\n'
    'VAI\\-SE CURANDO';

final note = NoteRef(
  id: 'shot-a',
  path: 'screenshots/2026/02/shot-a.typ',
  title: 'Cervejaria',
  kind: 'screenshot',
  date: '2026-02-12',
  outgoingLinks: const [],
  properties: const {
    'source_app': 'Instagram',
    'keywords': ['bar', 'cake'],
    'captured_at': '2026-02-12T01:24:32',
  },
);

final Uint8List png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

void main() {
  test('screenshotSections splits and unescapes', () {
    expect(screenshotSections(source), {
      'Description': 'An ad for a #bar.',
      'Text': 'CAMADA A CAMADA\nVAI-SE CURANDO',
    });
  });

  testWidgets('wide layout shows picture left of details with meta and tags', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScreenshotView(
            note: note,
            source: source,
            imageResolver: (_) async => png,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final pictureLeft = tester
        .getTopLeft(find.byKey(const ValueKey('screenshot-picture')))
        .dx;
    final descLeft = tester.getTopLeft(find.text('An ad for a #bar.')).dx;
    expect(pictureLeft < descLeft, isTrue);

    final pictureHeight = tester
        .getRect(find.byKey(const ValueKey('screenshot-picture')))
        .height;
    expect(pictureHeight, greaterThanOrEqualTo(400));

    expect(find.textContaining('An ad for a #bar.'), findsOneWidget);
    expect(find.textContaining('Instagram'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'cake'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('screenshot-details-sheet')),
      findsNothing,
    );
  });

  testWidgets('narrow layout stacks picture under a draggable details sheet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScreenshotView(
            note: note,
            source: source,
            imageResolver: (_) async => png,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const ValueKey('screenshot-details-sheet')),
      findsOneWidget,
    );
    final pictureHeight = tester
        .getRect(find.byKey(const ValueKey('screenshot-picture')))
        .height;
    expect(pictureHeight, greaterThanOrEqualTo(600));

    // Drag the sheet by its visible title (its centre is over the picture).
    await tester.drag(find.text('Cervejaria'), const Offset(0, -500));
    await tester.pumpAndSettle();

    final ocr = find.textContaining('VAI-SE CURANDO', findRichText: true);
    expect(ocr, findsWidgets);
    expect(tester.getTopLeft(ocr.first).dy, lessThan(800));
  });

  testWidgets('onEdit callback fires when the edit button is tapped', (
    tester,
  ) async {
    var edited = false;
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScreenshotView(
            note: note,
            source: source,
            imageResolver: (_) async => png,
            onEdit: () => edited = true,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byTooltip('Edit'));
    await tester.pump();

    expect(edited, isTrue);
  });

  testWidgets('onBack shows a back arrow that fires', (tester) async {
    var back = false;
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScreenshotView(
            note: note,
            source: source,
            imageResolver: (_) async => png,
            onBack: () => back = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('screenshot-back')));
    expect(back, isTrue);
  });
}
