import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/rich_editor.dart';
import 'package:tylog/widgets/constants.dart';
import 'package:tylog/widgets/fold_store.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

/// A 100x400 picture, tall enough that collapsing it is measurable.
Future<Uint8List> _tallPng() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    const Rect.fromLTWH(0, 0, 100, 400),
    Paint()..color = const Color(0xFF336699),
  );
  final image = await recorder.endRecording().toImage(100, 400);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}

void main() {
  tearDown(() => FoldStore.instance = null);

  test('fold state persists across reopen and stays out of notes', () async {
    final dir = await Directory.systemTemp.createTemp('fold-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/fold_state.json');
    final store = await FoldStore.open(file);
    expect(store.isFolded('asset:/assets/a.png'), isFalse);
    await store.toggle('asset:/assets/a.png');
    expect(
      (await FoldStore.open(file)).isFolded('asset:/assets/a.png'),
      isTrue,
    );
    await store.toggle('asset:/assets/a.png');
    expect(
      (await FoldStore.open(file)).isFolded('asset:/assets/a.png'),
      isFalse,
    );

    // Rapid toggles without awaiting: disk ends equal to memory.
    unawaited(store.toggle('asset:/assets/b.png'));
    unawaited(store.toggle('asset:/assets/b.png'));
    await store.toggle('asset:/assets/b.png');
    expect(store.isFolded('asset:/assets/b.png'), isTrue);
    expect(
      (await FoldStore.open(file)).isFolded('asset:/assets/b.png'),
      isTrue,
    );
  });

  testWidgets('pictures built before the store loads pick it up', (
    tester,
  ) async {
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('fold-late-'),
    ))!;
    addTearDown(() => dir.delete(recursive: true));
    final tall = (await tester.runAsync(_tallPng))!;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TyLogReadView(
            source: '#image("/assets/x.png", width: 100%)',
            imageResolver: (_) async => tall,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Collapse image'), findsNothing);
    FoldStore.instance = (await tester.runAsync(
      () => FoldStore.open(File('${dir.path}/fold_state.json')),
    ))!;
    await tester.pumpAndSettle();
    expect(find.byTooltip('Collapse image'), findsOneWidget);
  });

  testWidgets(
    'editor: an image collapses to a strip and back; source unchanged',
    (tester) async {
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('fold-ui-'),
      ))!;
      addTearDown(() => dir.delete(recursive: true));
      FoldStore.instance = (await tester.runAsync(
        () => FoldStore.open(File('${dir.path}/fold_state.json')),
      ))!;
      const source = 'Run\n\n#image("/assets/x.png", width: 100%)\n\nПробежка';
      final controller = TyLogEditingController(
        source: source,
        onSourceChanged: (_) {},
        onError: (_) {},
        onProtectedTap: (_) {},
        imageResolver: (path) async => _png,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TyLogRichEditor(
              controller: controller,
              onInsert: () async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => precacheImage(
          tester.widget<Image>(find.byType(Image)).image,
          tester.element(find.byType(Image)),
        ),
      );
      await tester.pumpAndSettle();
  
      await tester.tap(find.byType(Image));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Collapse image'));
      await tester.pumpAndSettle();
      expect(FoldStore.instance!.isFolded('asset:/assets/x.png'), isTrue);
      expect(find.byKey(const ValueKey('image-folded')), findsOneWidget);
      expect(controller.document.toSource(), source);

      await tester.tap(find.byType(Image));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Show image'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('image-folded')), findsNothing);
      expect(controller.document.toSource(), source);
    },
  );

  testWidgets('reading view: the fold button collapses an image', (
    tester,
  ) async {
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('fold-read-'),
    ))!;
    addTearDown(() => dir.delete(recursive: true));
    FoldStore.instance = (await tester.runAsync(
      () => FoldStore.open(File('${dir.path}/fold_state.json')),
    ))!;
    final tall = (await tester.runAsync(_tallPng))!;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TyLogReadView(
            source: '#image("/assets/x.png", width: 100%)\n\nПробежка',
            imageResolver: (_) async => tall,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => precacheImage(
        tester.widget<Image>(find.byType(Image)).image,
        tester.element(find.byType(Image)),
      ),
    );
    await tester.pumpAndSettle();
    final full = tester.getSize(find.byType(Image)).height;
    await tester.tap(find.byTooltip('Collapse image'));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('image-folded'))).height,
      allOf(kImageFoldHeight, lessThan(full)),
    );
    await tester.tap(find.byTooltip('Show image'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('image-folded')), findsNothing);
  });
}
