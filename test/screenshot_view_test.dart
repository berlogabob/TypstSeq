import 'dart:convert';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart' show SystemChannels;
import 'package:tylog/widgets/text_note_widgets.dart';
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
  const translatedSource =
      '$source\n\n== Translation en\n'
      '- 00:00 LAYER BY LAYER\n- 00:00 IT HEALS\n'
      '== Translation ru\n- 00:00 СЛОЙ ЗА СЛОЕМ\n- 00:00 ЗАЖИВАЕТ\n';

  Future<void> pumpText(
    WidgetTester tester, {
    String text = translatedSource,
    Future<String> Function()? readSource,
    Future<Map<String, Object?>?> Function(String)? job,
    Future<void> Function(String, String)? request,
    Future<void> Function(String, List<String>)? open,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ScreenshotTextView(
              source: text,
              readSource: readSource,
              translationJob:
                  job ?? (_) async => {'lang': 'pt', 'status': 'done'},
              requestTranslation: request,
              onOpenAsPage: open,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets(
    'OCR uses shared language controls and ordered rows without timestamps',
    (tester) async {
      await pumpText(tester);
      expect(find.byType(AudioLanguageBar), findsOneWidget);
      expect(find.text('PT'), findsOneWidget);
      expect(find.text('RU'), findsOneWidget);
      expect(find.text('EN'), findsOneWidget);
      expect(find.text('00:00'), findsNothing);
      expect(find.byType(AudioTranscriptRow), findsNWidgets(2));
      expect(
        tester.getTopLeft(find.text('LAYER BY LAYER')).dy,
        lessThan(tester.getTopLeft(find.text('IT HEALS')).dy),
      );
      await tester.tap(find.byTooltip('Side by side'));
      await tester.pump();
      expect(find.text('CAMADA A CAMADA'), findsNothing);
      expect(find.text('LAYER BY LAYER'), findsOneWidget);
      await tester.tap(find.text('RU'));
      await tester.pump();
      expect(find.text('СЛОЙ ЗА СЛОЕМ'), findsOneWidget);
      await tester.tap(find.byTooltip('Original'));
      await tester.pump();
      expect(find.text('CAMADA A CAMADA'), findsOneWidget);
      expect(find.text('СЛОЙ ЗА СЛОЕМ'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('long press, Copy all and Open as page use timestamp-free text', (
    tester,
  ) async {
    final copied = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    String? language;
    List<String>? page;
    await pumpText(
      tester,
      open: (lang, lines) async {
        language = lang;
        page = lines;
      },
    );
    await tester.longPress(find.text('CAMADA A CAMADA'));
    await tester.pumpAndSettle();
    expect(copied.last, 'CAMADA A CAMADA');
    await tester.longPress(find.text('LAYER BY LAYER'));
    await tester.pumpAndSettle();
    expect(copied.last, 'LAYER BY LAYER');
    await tester.tap(find.byTooltip('Text menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy all'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Side by side'));
    await tester.pumpAndSettle();
    expect(
      copied.last,
      'CAMADA A CAMADA\nLAYER BY LAYER\nVAI-SE CURANDO\nIT HEALS',
    );
    await tester.tap(find.byTooltip('Text menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open as page'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English').first);
    await tester.pumpAndSettle();
    expect(language, 'en');
    expect(page, ['LAYER BY LAYER', 'IT HEALS']);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'missing languages request, show progress, retry and reload worker output',
    (tester) async {
      final statuses = <String, String>{};
      final requested = <String>[];
      var currentSource = source;
      await pumpText(
        tester,
        text: source,
        readSource: () async => currentSource,
        job: (target) async => {'lang': 'pt', 'status': statuses[target]},
        request: (target, lang) async {
          expect(lang, 'pt');
          requested.add(target);
          statuses[target] = 'queued';
        },
      );
      await tester.tap(find.byTooltip('Translate to EN'));
      await tester.pump();
      await tester.pump();
      expect(requested, ['en']);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byTooltip('Translate to EN'), findsNothing);
      statuses['en'] = 'failed';
      await tester.pump(const Duration(seconds: 8));
      await tester.pump();
      await tester.tap(find.byTooltip('Retry EN'));
      await tester.pump();
      await tester.pump();
      expect(requested, ['en', 'en']);
      statuses['en'] = 'done';
      currentSource = translatedSource;
      await tester.pump(const Duration(seconds: 8));
      await tester.pumpAndSettle();
      expect(find.text('LAYER BY LAYER'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'unknown OCR language has a source chip and requests automatic source',
    (tester) async {
      String? requestedLanguage;
      await pumpText(
        tester,
        text: source,
        job: (_) async => null,
        request: (_, language) async => requestedLanguage = language,
      );
      expect(find.text('SOURCE'), findsOneWidget);
      await tester.tap(find.byTooltip('Translate to RU'));
      await tester.pump();
      expect(requestedLanguage, 'auto');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

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
