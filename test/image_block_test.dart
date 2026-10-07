import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/controlled_editor.dart';
import 'package:tylog/rich_editor.dart';
import 'package:tylog/tylog_assets.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAHgAAAA8CAYAAACtrX6oAAAApUlEQVR4nO3RMQ0AIADAMKQgFWk4Axkko0f/JRtz7UPXeB2AwRiMwZ8yOM7gOIPjDI4zOM7gOIPjDI4zOM7gOIPjDI4zOM7gOIPjDI4zOM7gOIPjDI4zOM7gOIPjDI4zOM7gOIPjDI4zOM7gOIPjDI4zOM7gOIPjDI4zOM7gOIPjDI4zOM7gOIPjDI4zOM7gOIPjDI4zOM7gOIPjDI4zOM7gOIPjLgwis787iIn5AAAAAElFTkSuQmCC',
);
const _path = '/assets/x.png';
const _request = MagicRequest(
  action: MagicAction.attachment,
  kind: 'image',
  value: _path,
);
const _old =
    '#tylog.attachment("/assets/x.png", kind: "image")[#image("/assets/x.png")]';

TyLogEditingController _controller(String source, {VoidCallback? open}) {
  final controller = TyLogEditingController(
    source: source,
    onSourceChanged: (_) {},
    onError: (error) => fail('$error'),
    onProtectedTap: (_) => open?.call(),
    imageResolver: (_) async => _png,
  );
  addTearDown(controller.dispose);
  return controller;
}

Future<void> _editor(
  WidgetTester tester,
  TyLogEditingController controller,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: TyLogRichEditor(controller: controller, onInsert: () async {}),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (find.byType(Image).evaluate().isNotEmpty) {
    await tester.runAsync(
      () => precacheImage(
        tester.widget<Image>(find.byType(Image)).image,
        tester.element(find.byType(Image)),
      ),
    );
  }
  await tester.pumpAndSettle();
}

Future<void> _select(WidgetTester tester) async {
  await tester.tap(find.byType(Image));
  await tester.pumpAndSettle();
  expect(find.text('Full'), findsOneWidget);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'image forms round-trip byte-exactly in paragraphs, boundaries, lists and Cyrillic',
    () {
      final forms = [
        for (final width in [33, 60, 100])
          for (final align in ['left', 'center', 'right'])
            imageAttachmentSource(_path, width: width, align: align),
        _old,
        '#image("/assets/x.png")',
      ];
      for (final form in forms) {
        for (final source in [
          form,
          '$form\n\nконец',
          'начало\n\n$form',
          'начало\n\n$form\n\nконец',
          '- начало $form конец',
          'начало $form конец',
          '$form\n\n',
        ]) {
          final document = TyLogDocument.parse(source);
          expect(document.toSource(), source);
          expect(
            document.blocks
                .expand((b) => b.parts)
                .where((p) => p.isAtom)
                .single
                .source,
            form,
          );
        }
      }
    },
  );

  for (final (name, offset, expected) in [
    ('start', 0, '${imageAttachmentSource(_path)}\n\nабвг'),
    ('middle', 2, 'аб\n\n${imageAttachmentSource(_path)}\n\nвг'),
    ('end', 4, 'абвг\n\n${imageAttachmentSource(_path)}'),
  ]) {
    testWidgets('insert image splits paragraph at $name with one undo', (
      tester,
    ) async {
      final controller = _controller('абвг');
      await _editor(tester, controller);
      controller.selection = TextSelection.collapsed(offset: offset);
      controller.applyMagic(_request);
      await tester.pumpAndSettle();
      expect(controller.document.toSource(), expected);
      expect(
        controller.document.blocks.any((b) => b.visibleText.isEmpty),
        isFalse,
      );
      expect(controller.value.composing, TextRange.empty);
      final imageIndex = controller.document.blocks.indexWhere(
        (b) => b.parts.any((p) => p.isAtom),
      );
      expect(
        controller.selection.baseOffset,
        imageIndex + 1 < controller.document.blocks.length
            ? controller.document.blockRanges[imageIndex + 1].start
            : controller.document.blockRanges[imageIndex].end,
      );
      controller.undo();
      expect(controller.document.toSource(), 'абвг');
      expect(controller.canUndo, isFalse);
      final edit = applyMagicEdit(
        'абвг',
        TextSelection.collapsed(offset: offset),
        _request,
      );
      expect(edit.text, expected);
    });
  }

  testWidgets(
    'empty insert and typing after an end image create no inline prose',
    (tester) async {
      final controller = _controller('');
      await _editor(tester, controller);
      controller.selection = const TextSelection.collapsed(offset: 0);
      controller.applyMagic(_request);
      expect(controller.document.toSource(), imageAttachmentSource(_path));
      expect(controller.document.blocks.length, 1);
      controller.value = TextEditingValue(
        text: '${controller.text}hello',
        selection: TextSelection.collapsed(offset: controller.text.length + 5),
      );
      expect(
        controller.document.toSource(),
        '${imageAttachmentSource(_path)}\n\nhello',
      );
    },
  );

  test('image insertion stays inline inside a list item', () {
    final controller = _controller('- абвг');
    controller.selection = const TextSelection.collapsed(offset: 4);
    controller.applyMagic(_request);
    expect(
      controller.document.toSource(),
      '- аб${imageAttachmentSource(_path)}вг',
    );
    expect(controller.document.blocks.length, 1);
    expect(
      applyMagicEdit(
        '- абвг',
        const TextSelection.collapsed(offset: 4),
        _request,
      ).text,
      '- аб${imageAttachmentSource(_path)}вг',
    );
  });

  for (final align in ['left', 'center', 'right']) {
    test(
      'written $align image compiles with the real Typst engine and tylog package',
      () async {
        final dir = await Directory.systemTemp.createTemp('tylog_image_');
        addTearDown(() => dir.delete(recursive: true));
        final assets = await TylogAssets.load();
        for (final entry in assets.managedVaultFiles.entries) {
          final file = File('${dir.path}/${entry.key}');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(entry.value);
        }
        final image = File('${dir.path}/assets/x.png');
        await image.parent.create(recursive: true);
        await image.writeAsBytes(_png);
        final controller = _controller('текст');
        controller.selection = const TextSelection.collapsed(offset: 5);
        controller.applyMagic(_request);
        final atom = controller.document.blocks.last.parts.single;
        controller.editImage(atom.id!, align: align);
        final source =
            '#import "/_system/tylog.typ" as tylog\n\n${controller.document.toSource()}';
        await File('${dir.path}/note.typ').writeAsString(source);
        final result = Process.runSync('typst', [
          'compile',
          '--root',
          dir.path,
          '${dir.path}/note.typ',
          '${dir.path}/out.pdf',
        ]);
        expect(result.exitCode, 0, reason: '${result.stderr}\n$source');
      },
    );
  }

  for (final (label, width) in [('S', 33), ('M', 60), ('Full', 100)]) {
    testWidgets(
      'toolbar size $label rewrites only image span and undoes once',
      (tester) async {
        const before = '  До #strong[жирный] ';
        const after = ' после\\!';
        const source = '$before$_old$after';
        final controller = _controller(source);
        await _editor(tester, controller);
        await _select(tester);
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(
          controller.document.toSource(),
          '$before${imageAttachmentSource(_path, width: width)}$after',
        );
        controller.undo();
        expect(controller.document.toSource(), source);
        expect(controller.canUndo, isFalse);
      },
    );
  }

  for (final align in ['left', 'center', 'right']) {
    testWidgets('toolbar alignment $align writes source and undoes once', (
      tester,
    ) async {
      final source = imageAttachmentSource(_path, width: 33);
      final controller = _controller(source);
      await _editor(tester, controller);
      await _select(tester);
      await tester.tap(find.byTooltip('Align $align'));
      await tester.pumpAndSettle();
      expect(
        controller.document.toSource(),
        imageAttachmentSource(_path, width: 33, align: align),
      );
      controller.undo();
      expect(controller.document.toSource(), source);
      expect(controller.canUndo, isFalse);
    });
  }

  for (final direction in ['up', 'down']) {
    testWidgets(
      'toolbar move image $direction swaps neighbouring block and undoes once',
      (tester) async {
        final image = imageAttachmentSource(_path);
        final source = 'до\n\n$image\n\nпосле';
        final controller = _controller(source);
        await _editor(tester, controller);
        await _select(tester);
        await tester.tap(find.byTooltip('Move image $direction'));
        await tester.pumpAndSettle();
        expect(
          controller.document.toSource(),
          direction == 'up' ? '$image\n\nдо\n\nпосле' : 'до\n\nпосле\n\n$image',
        );
        controller.undo();
        expect(controller.document.toSource(), source);
        expect(controller.canUndo, isFalse);
      },
    );
  }

  testWidgets('toolbar delete removes image block and undoes once', (
    tester,
  ) async {
    final source = 'до\n\n${imageAttachmentSource(_path)}\n\nпосле';
    final controller = _controller(source);
    await _editor(tester, controller);
    await _select(tester);
    await tester.tap(find.byTooltip('Delete image'));
    await tester.pumpAndSettle();
    expect(controller.document.toSource(), 'до\n\nпосле');
    controller.undo();
    expect(controller.document.toSource(), source);
    expect(controller.canUndo, isFalse);
  });

  testWidgets('old image stays untouched on selection, open and dismissal', (
    tester,
  ) async {
    var opened = 0;
    final controller = _controller(_old, open: () => opened++);
    await _editor(tester, controller);
    await _select(tester);
    expect(controller.document.toSource(), _old);
    expect(opened, 0);
    await tester.tap(find.byTooltip('Open image'));
    await tester.pumpAndSettle();
    expect(opened, 1);
    expect(controller.document.toSource(), _old);
    await _select(tester);
    controller.selection = TextSelection.collapsed(
      offset: controller.text.length,
    );
    await tester.pumpAndSettle();
    expect(find.text('Full'), findsNothing);
    expect(controller.document.toSource(), _old);
  });

  testWidgets(
    'block read view uses content width and alignment without controls',
    (tester) async {
      for (final (width, align) in [
        for (final width in [33, 60, 100])
          for (final align in ['left', 'center', 'right']) (width, align),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 400,
                child: TyLogReadView(
                  source: imageAttachmentSource(
                    _path,
                    width: width,
                    align: align,
                  ),
                  imageResolver: (_) async => _png,
                ),
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
        final rect = tester.getRect(find.byType(Image));
        expect(rect.width, closeTo(400 * width / 100, 0.01));
        expect(
          rect.left,
          closeTo(switch (align) {
            'left' => 0,
            'right' => 400 - 400 * width / 100,
            _ => (400 - 400 * width / 100) / 2,
          }, 0.01),
        );
        expect(rect.height, closeTo(200 * width / 100, 0.01));
        await tester.tap(find.byType(Image));
        await tester.pumpAndSettle();
        expect(find.text('Full'), findsNothing);
      }
    },
  );
  testWidgets(
    'selection floats without shifting layout and dismisses on outside tap or typing',
    (tester) async {
      final controller = _controller(
        'до\n\n${imageAttachmentSource(_path)}\n\nпосле',
      );
      await _editor(tester, controller);
      final rect = tester.getRect(find.byType(Image));
      await _select(tester);
      expect(tester.getRect(find.byType(Image)), rect);
      final outline = find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).border is Border &&
            ((widget.decoration as BoxDecoration).border! as Border)
                    .top
                    .color ==
                Theme.of(
                  tester.element(find.byType(Image)),
                ).colorScheme.primary,
      );
      expect(outline, findsOneWidget);
      await tester.tapAt(const Offset(750, 550));
      await tester.pumpAndSettle();
      expect(find.text('Full'), findsNothing);
      await _select(tester);
      final text = controller.text;
      controller.value = TextEditingValue(
        text: '$text!',
        selection: TextSelection.collapsed(offset: text.length + 1),
      );
      await tester.pumpAndSettle();
      expect(find.text('Full'), findsNothing);
    },
  );

  testWidgets(
    'programmatic image insertion clears composition and synchronizes the IME',
    (tester) async {
      final controller = _controller('абвг');
      await _editor(tester, controller);
      await tester.showKeyboard(find.byType(TextField));
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'абвг',
          selection: TextSelection.collapsed(offset: 2),
          composing: TextRange(start: 0, end: 4),
        ),
      );
      controller.applyMagic(_request);
      await tester.pumpAndSettle();
      expect(controller.value.composing, TextRange.empty);
      final updates = tester.testTextInput.log.where(
        (call) => call.method == 'TextInput.setEditingState',
      );
      expect((updates.last.arguments as Map)['text'], controller.text);
      final current = controller.value;
      tester.testTextInput.updateEditingValue(
        current.copyWith(
          text: current.text.replaceRange(
            current.selection.start,
            current.selection.end,
            'я',
          ),
          selection: TextSelection.collapsed(
            offset: current.selection.start + 1,
          ),
        ),
      );
      expect(
        controller.document.toSource(),
        'аб\n\n${imageAttachmentSource(_path)}\n\nявг',
      );
    },
  );

  test(
    'identical image atoms edit independently and bare legacy upgrade is surgical',
    () {
      const bare = '#image("/assets/x.png")';
      const source = '$bare\n\n$bare';
      final controller = _controller(source);
      final first = controller.document.blocks.first.parts.single.id!;
      final last = controller.document.blocks.last.parts.single.id!;
      expect(first, isNot(last));
      controller.editImage(last, width: 100, align: 'right');
      expect(
        controller.document.toSource(),
        '$bare\n\n${imageAttachmentSource(_path, width: 100, align: 'right')}',
      );
      controller.undo();
      expect(controller.document.toSource(), source);
    },
  );
  testWidgets('toolbar stays on the image through size and alignment changes', (
    tester,
  ) async {
    final controller = _controller(imageAttachmentSource(_path));
    await _editor(tester, controller);
    await _select(tester);
    await tester.tap(find.text('S'));
    await tester.pumpAndSettle();
    expect(find.text('Full'), findsOneWidget);
    await tester.tap(find.byTooltip('Align right'));
    await tester.pumpAndSettle();
    expect(
      controller.document.toSource(),
      imageAttachmentSource(_path, width: 33, align: 'right'),
    );
    expect(
      tester.getRect(find.byType(Image)).width,
      closeTo(controller.imageContentWidth! * 0.33, 0.01),
    );
    final toolbar = tester.getRect(find.byType(Wrap));
    expect(toolbar.left, greaterThanOrEqualTo(0));
    expect(toolbar.right, lessThanOrEqualTo(800));
    controller.undo();
    expect(
      controller.document.toSource(),
      imageAttachmentSource(_path, width: 33),
    );
    controller.undo();
    expect(controller.document.toSource(), imageAttachmentSource(_path));
  });

  test('inline image deletion keeps neighbouring source byte-exact', () {
    const source = '- До #strong[жирный] $_old после\\!';
    final controller = _controller(source);
    final id = controller.document.blocks.single.parts
        .firstWhere((part) => part.isAtom)
        .id!;
    controller.editImage(id, delete: true);
    expect(controller.document.toSource(), '- До #strong[жирный]  после\\!');
    controller.undo();
    expect(controller.document.toSource(), source);
  });
  testWidgets(
    'block height caps at sixty percent while legacy cap stays forty percent',
    (tester) async {
      final tall = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAB4AAAPoCAYAAADJE047AAABuUlEQVR4nO3NMQEAAAQAMFFEFU0zYnDs2L3I6rkQYrFYLBaLxWKxWCwWi8VisVgsFovFYrFYLBaLxWKxWCwWi8VisVgsFovFYrFYLBaLxWKxWCwWi8VisVgsFovFYrFYLBaLxWKxWCwWi8VisVgsFovFYrFYLBaLxWKxWCwWi8VisVgsFovFYrFYLBaLxWKxWCwWi8VisVgsFovFYrFYLBaLxWKxWCwWi8VisVgsFovFYrFYLBaLxWKxWCwWi8VisVgsFovFYrFYLBaLxWKxWCwWi8VisVgsFovFYrFYLBaLxWKxWCwWi8VisVgsFovFYrFYLBaLxWKxWCwWi8VisVgsFovFYrFYLBaLxWKxWCwWi8VisVgsFovFYrFYLBaLxWKxWCwWi8VisVgsFovFYrFYLBaLxWKxWCwWi8VisVgsFovFYrFYLBaLxWKxWCwWi8VisVgsFovFYrFYLBaLxWKxWCwWi8VisVgsFovFYrFYLBaLxWKxWCwWi8VisVgsFovFYrFYLBaLxWKxWCwWi8VisVgsFovFYrFYLBaLxWKxWCwWi8VisVgsFovFYrFYLBaLxWKxWPwjXshy7QzWDvpgAAAAAElFTkSuQmCC',
      );
      for (final (source, cap) in [
        (imageAttachmentSource(_path), 360.0),
        (_old, 240.0),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 400,
                child: TyLogReadView(
                  source: source,
                  imageResolver: (_) async => tall,
                ),
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
        expect(tester.getRect(find.byType(Image)).height, closeTo(cap, 0.01));
        final provider =
            tester.widget<Image>(find.byType(Image)).image as ResizeImage;
        expect(
          provider.width,
          ((source == _old ? 800 : 400) *
                  MediaQuery.devicePixelRatioOf(
                    tester.element(find.byType(Image)),
                  ))
              .round(),
        );
      }
    },
  );
  test('moving an EOF image keeps trailing whitespace at EOF', () {
    final image = imageAttachmentSource(_path);
    for (final source in ['до\n\n$image\n', '$image\n\nдо\n']) {
      final controller = _controller(source);
      final first = source.startsWith(image);
      final atom = controller.document.blocks[first ? 0 : 1].parts.firstWhere(
        (part) => part.isAtom,
      );
      controller.editImage(atom.id!, move: first ? 1 : -1);
      expect(
        controller.document.toSource(),
        first ? 'до\n\n$image\n' : '$image\n\nдо\n',
      );
      controller.undo();
      expect(controller.document.toSource(), source);
    }
  });
}
