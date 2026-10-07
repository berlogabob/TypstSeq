import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/controlled_editor.dart';
import 'package:tylog/image_crop.dart';
import 'package:tylog/rich_editor.dart';
import 'package:tylog/tylog_assets.dart';
import 'package:tylog_core/storage.dart';

Future<Uint8List> _png({int width = 120, int height = 60}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(const Color(0xffff0000), BlendMode.src);
  canvas.drawRect(
    Rect.fromLTWH(width / 2, 0, width / 2, height.toDouble()),
    Paint()..color = const Color(0xff0000ff),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}

TyLogEditingController _controller(
  String source, {
  Future<Uint8List?> Function(String)? read,
  Future<String> Function(String, Uint8List)? write,
  ValueChanged<Object>? onError,
}) {
  final controller = TyLogEditingController(
    source: source,
    onSourceChanged: (_) {},
    onProtectedTap: (_) {},
    onError: onError ?? (error) => fail('$error'),
    imageResolver: read,
    imageWriter: write,
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
        onError: (_, _) {},
      ),
    );
  }
  await tester.pumpAndSettle();
}

Future<void> _openCrop(WidgetTester tester) async {
  await tester.tap(find.byType(Image));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Crop'));
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await tester.pumpAndSettle();
  expect(find.text('Crop image'), findsOneWidget);
}

Future<void> _done(WidgetTester tester) async {
  await tester.runAsync(() async {
    await tester.tap(find.text('Done'));
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });
  await tester.pump();
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('crop maths clamp movement, all corners and minimum size', () {
    const bounds = Rect.fromLTWH(20, 50, 300, 150);
    const rect = Rect.fromLTWH(100, 80, 100, 70);
    expect(
      cropMove(rect, bounds, const Offset(-500, 500)),
      const Rect.fromLTWH(20, 130, 100, 70),
    );
    for (var corner = 0; corner < 4; corner++) {
      final left = corner == 0 || corner == 3;
      final top = corner < 2;
      final small = cropResize(
        rect,
        bounds,
        corner,
        Offset(left ? 500 : -500, top ? 500 : -500),
        null,
      );
      expect(small.size, const Size(32, 32));
      final large = cropResize(
        rect,
        bounds,
        corner,
        Offset(left ? -500 : 500, top ? -500 : 500),
        null,
      );
      expect(bounds.contains(large.topLeft), isTrue);
      expect(large.right, lessThanOrEqualTo(bounds.right));
      expect(large.bottom, lessThanOrEqualTo(bounds.bottom));
    }
  });

  test('crop presets centre and lock ratios at every corner and boundary', () {
    const bounds = Rect.fromLTWH(10, 20, 300, 200);
    const rect = Rect.fromLTWH(60, 70, 100, 90);
    for (final ratio in [1.0, 4 / 3, 16 / 9]) {
      final preset = cropPreset(rect, bounds, ratio);
      expect(preset.center, rect.center);
      expect(preset.width / preset.height, closeTo(ratio, 1e-9));
      for (var corner = 0; corner < 4; corner++) {
        for (final delta in [
          const Offset(-1000, 1000),
          const Offset(1000, -1000),
          const Offset(9, 21),
        ]) {
          final next = cropResize(preset, bounds, corner, delta, ratio);
          expect(next.width / next.height, closeTo(ratio, 1e-9));
          expect(next.width, greaterThanOrEqualTo(32));
          expect(next.height, greaterThanOrEqualTo(32));
          expect(next.left, greaterThanOrEqualTo(bounds.left));
          expect(next.top, greaterThanOrEqualTo(bounds.top));
          expect(next.right, lessThanOrEqualTo(bounds.right));
          expect(next.bottom, lessThanOrEqualTo(bounds.bottom));
        }
      }
    }
  });

  test('crop maths tiny images and non-square letterboxed pixel mapping', () {
    const bounds = Rect.fromLTWH(50, 100, 240, 120);
    expect(
      cropPixels(
        const Rect.fromLTWH(110, 130, 120, 60),
        bounds,
        const Size(1200, 600),
      ),
      const Rect.fromLTWH(300, 150, 600, 300),
    );
    expect(
      cropPixels(
        const Rect.fromLTWH(50, 130, 240, 60),
        bounds,
        const Size(2, 1),
      ),
      const Rect.fromLTWH(0, 0, 2, 1),
    );
    const tiny = Rect.fromLTWH(0, 0, 12, 8);
    expect(cropResize(tiny, tiny, 0, const Offset(100, 100), null), tiny);
    for (final ratio in [1.0, 4 / 3, 16 / 9]) {
      final preset = cropPreset(tiny, tiny, ratio);
      final resized = cropResize(
        preset,
        tiny,
        2,
        const Offset(100, 100),
        ratio,
      );
      expect(resized.width / resized.height, closeTo(ratio, 1e-9));
      expect(resized.right, lessThanOrEqualTo(tiny.right));
      expect(resized.bottom, lessThanOrEqualTo(tiny.bottom));
    }
    expect(
      cropPixels(tiny, tiny, const Size(1, 1)),
      const Rect.fromLTWH(0, 0, 1, 1),
    );
  });

  test(
    'dart ui crop preserves original pixel dimensions and known colour',
    () async {
      final image = await decodeCropImage(await _png());
      final bytes = await encodeImageCrop(
        image,
        const Rect.fromLTWH(60, 10, 40, 30),
      );
      image.dispose();
      final output = await decodeCropImage(bytes);
      expect(output.width, 40);
      expect(output.height, 30);
      final rgba = await output.toByteData(format: ui.ImageByteFormat.rawRgba);
      expect(rgba!.buffer.asUint8List().take(4), [0, 0, 255, 255]);
      output.dispose();
    },
  );

  test('crop follows Flutter codec EXIF orientation', () async {
    // 120 x 60 JPEG, EXIF orientation 6 (clockwise): visible size is 60 x 120.
    final bytes = base64Decode(
      '/9j/4AAQSkZJRgABAQAAAQABAAD/4QAiRXhpZgAATU0AKgAAAAgAAQESAAMAAAABAAYAAAAAAAD/2wBDAAEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQH/2wBDAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQH/wAARCAA8AHgDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwD8X6KKK/ynP+/gKKKKACiiigAr5D/aq/5kP/uaP/ddr68r5D/aq/5kP/uaP/ddr/VT9iX/AMrOvozf95m/9h98Vz/Nf9r3/wAq7fpC/wDeJv8A1+PhmfIdFFFf9/h/xDhRRRQAUUUUAFFFFAH68UUUV/5V5/6UAUUUUAFFFFABXyH+1V/zIf8A3NH/ALrtfXlfIf7VX/Mh/wDc0f8Auu1/qp+xL/5WdfRm/wC8zf8AsPviuf5r/te/+Vdv0hf+8Tf+vx8Mz5Dooor/AL/D/iHCiiigAooooAKKKKAP14ooor/yrz/0oAooooAKKKKACvkP9qr/AJkP/uaP/ddr68r5D/aq/wCZD/7mj/3Xa/1U/Yl/8rOvozf95m/9h98Vz/Nf9r3/AMq7fpC/94m/9fj4ZnyHRRRX/f4f8Q4UUUUAFFFFABRRRQB+vFFFFf8AlXn/AKUAUUUUAFFFFABXyH+1V/zIf/c0f+67X15XyH+1V/zIf/c0f+67X+qn7Ev/AJWdfRm/7zN/7D74rn+a/wC17/5V2/SF/wC8Tf8Ar8fDM+Q6KKK/7/D/AIhwooooAKKKKACiiigD/9k=',
    );
    final codec = await ui.instantiateImageCodec(bytes);
    final visible = (await codec.getNextFrame()).image;
    codec.dispose();
    final image = await decodeCropImage(bytes);
    expect(image.width, 60);
    expect(image.height, 120);
    expect(image.width, visible.width);
    expect(image.height, visible.height);
    expect(
      (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List(),
      (await visible.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List(),
    );
    final output = await decodeCropImage(
      await encodeImageCrop(image, const Rect.fromLTWH(10, 70, 40, 40)),
    );
    final rgba = (await output.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!.buffer.asUint8List();
    expect(rgba[0], lessThan(10));
    expect(rgba[2], greaterThan(245));
    visible.dispose();
    image.dispose();
    output.dispose();
  });

  test('crop decoding caps long side at 4096', () async {
    final image = await decodeCropImage(await _png(width: 4100, height: 100));
    expect(image.width, 4096);
    expect(image.height, 100);
    image.dispose();
  });

  test(
    'cropped path edits round-trip byte-exactly, preserve legacy shape and clear IME',
    () {
      const path = '/assets/x.png';
      const next = '/assets/x-crop-12345678.png';
      for (final form in [
        imageAttachmentSource(path, width: 33, align: 'right'),
        '#tylog.attachment("$path", kind: "image")[#image("$path")]',
        '#image("$path")',
        '#image("$path", width: 41%)',
        '#Image("$path")',
      ]) {
        for (final source in [
          form,
          'До $form после\\!',
          '- $form конец',
          '$form\n\n$form\n',
        ]) {
          final controller = _controller(source);
          final atom = controller.document.blocks
              .expand((b) => b.parts)
              .firstWhere((p) => p.isAtom);
          controller.value = controller.value.copyWith(
            composing: const TextRange(start: 0, end: 1),
          );
          controller.editImage(atom.id!, path: next);
          final expected = source.replaceFirst(
            form,
            form.replaceAll(path, next),
          );
          expect(controller.document.toSource(), expected);
          expect(TyLogDocument.parse(expected).toSource(), expected);
          expect(controller.value.composing, TextRange.empty);
          controller.undo();
          expect(controller.document.toSource(), source);
          expect(controller.canUndo, isFalse);
        }
      }
    },
  );

  test(
    'crop changes only the selected duplicate image and escapes new paths',
    () {
      final form = imageAttachmentSource(
        '/assets/x.png',
        width: 100,
        align: 'left',
      );
      final controller = _controller('До $form между $form после');
      final atoms = controller.document.blocks.single.parts
          .where((p) => p.isAtom)
          .toList();
      const path = '/assets/quoted"-crop-deadbeef.png';
      controller.editImage(atoms.last.id!, path: path);
      final next = imageAttachmentSource(path, width: 100, align: 'left');
      expect(controller.document.toSource(), 'До $form между $next после');
      expect(
        controller.document.blocks.single.parts
            .where((p) => p.isAtom)
            .map((p) => p.id),
        atoms.map((p) => p.id),
      );
      controller.undo();
      expect(controller.document.toSource(), 'До $form между $form после');
    },
  );

  test(
    'cropped PNG asset is reused and rewritten source compiles with real Typst',
    () async {
      final dir = await Directory.systemTemp.createTemp('tylog_crop_');
      addTearDown(() => dir.delete(recursive: true));
      final storage = LocalVaultStorage(dir);
      final assets = await TylogAssets.load();
      for (final entry in assets.managedVaultFiles.entries) {
        await storage.writeBytes(entry.key, entry.value);
      }
      final original = await _png();
      await storage.writeBytes('assets/x.png', original);
      final image = await decodeCropImage(original);
      final cropped = await encodeImageCrop(
        image,
        const Rect.fromLTWH(60, 0, 60, 60),
      );
      image.dispose();
      final path = await saveImageCrop(storage, '/assets/x.png', cropped);
      expect(await saveImageCrop(storage, '/assets/x.png', cropped), path);
      expect(path, matches(r'^/assets/x-crop-[0-9a-f]{8}\.png$'));
      expect(await storage.readBytes('assets/x.png'), original);
      for (final form in [
        imageAttachmentSource('/assets/x.png', width: 60, align: 'right'),
        '#tylog.attachment("/assets/x.png", kind: "image")[#image("/assets/x.png")]',
        '#image("/assets/x.png")',
      ]) {
        final controller = _controller(form);
        controller.editImage(
          controller.document.blocks.single.parts.single.id!,
          path: path,
        );
        final source =
            '#import "/_system/tylog.typ" as tylog\n\n${controller.document.toSource()}';
        await storage.writeText('note.typ', source);
        final result = Process.runSync('typst', [
          'compile',
          '--root',
          dir.path,
          '${dir.path}/note.typ',
          '${dir.path}/out.pdf',
        ]);
        expect(result.exitCode, 0, reason: '${result.stderr}\n$source');
      }
    },
  );

  test(
    'crop chain saves beside original and rejects a content-prefix collision',
    () async {
      final dir = await Directory.systemTemp.createTemp('tylog_crop_chain_');
      addTearDown(() => dir.delete(recursive: true));
      final storage = LocalVaultStorage(dir);
      final original = await _png();
      await storage.writeBytes('assets/nested/x.png', original);
      final image = await decodeCropImage(original);
      final first = await encodeImageCrop(
        image,
        const Rect.fromLTWH(60, 0, 60, 60),
      );
      image.dispose();
      final path = await saveImageCrop(storage, '/assets/nested/x.png', first);
      final cropped = await decodeCropImage(
        await storage.readBytes(path.substring(1)),
      );
      final second = await encodeImageCrop(
        cropped,
        const Rect.fromLTWH(10, 10, 40, 40),
      );
      cropped.dispose();
      final next = await saveImageCrop(storage, path, second);
      expect(
        next,
        matches(r'^/assets/nested/x-crop-[0-9a-f]{8}-crop-[0-9a-f]{8}\.png$'),
      );
      expect(await storage.readBytes('assets/nested/x.png'), original);
      expect(await storage.readBytes(path.substring(1)), first);
      await storage.writeBytes(next.substring(1), [1, 2, 3]);
      await expectLater(saveImageCrop(storage, path, second), throwsStateError);
      expect(await storage.readBytes(next.substring(1)), [1, 2, 3]);
    },
  );

  for (final action in ['Done', 'Cancel', 'Full Done', 'Reset']) {
    testWidgets(
      'toolbar crop $action keeps original safe and undo restores source',
      (tester) async {
        final dir = await tester.runAsync(
          () => Directory.systemTemp.createTemp('tylog_crop_widget_'),
        );
        addTearDown(() => dir!.delete(recursive: true));
        final storage = LocalVaultStorage(dir!);
        final original = (await tester.runAsync(_png))!;
        await tester.runAsync(
          () => storage.writeBytes('assets/x.png', original),
        );
        final source =
            'До\n\n${imageAttachmentSource('/assets/x.png', width: 33, align: 'right')}\n\nпосле';
        var writes = 0;
        final data = <String, Uint8List>{'/assets/x.png': original};
        final controller = _controller(
          source,
          read: (path) async => data[path],
          write: (path, bytes) async {
            writes++;
            final next = await saveImageCrop(storage, path, bytes);
            data[next] = bytes;
            return next;
          },
        );
        await _editor(tester, controller);
        final editorRect = tester.getRect(find.byType(Image));
        await _openCrop(tester);
        if (action != 'Full Done') {
          await tester.tap(find.text('1:1'));
          await tester.pumpAndSettle();
        }
        if (action == 'Cancel') {
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
        } else {
          if (action == 'Reset') {
            await tester.tap(find.text('Reset'));
            await tester.pumpAndSettle();
          }
          await _done(tester);
        }
        expect(find.text('Crop image'), findsNothing);
        expect(writes, action == 'Done' ? 1 : 0);
        final files = await tester.runAsync(() => storage.list(path: 'assets'));
        expect(files!.length, action == 'Done' ? 2 : 1);
        expect(
          await tester.runAsync(() => storage.readBytes('assets/x.png')),
          original,
        );
        if (action == 'Done') {
          final cropped = files
              .singleWhere((f) => f.path != 'assets/x.png')
              .path;
          expect(
            controller.document.toSource(),
            source.replaceAll('/assets/x.png', '/$cropped'),
          );
          controller.undo();
          await tester.pumpAndSettle();
          expect(controller.canUndo, isFalse);
        } else {
          expect(controller.canUndo, isFalse);
        }
        expect(controller.document.toSource(), source);
        expect(tester.getRect(find.byType(Image)), editorRect);
      },
    );
  }

  testWidgets(
    'crop write failure leaves source unchanged and reports usual error',
    (tester) async {
      final bytes = (await tester.runAsync(_png))!;
      final errors = <Object>[];
      final source = imageAttachmentSource('/assets/x.png');
      final controller = _controller(
        source,
        read: (_) async => bytes,
        write: (_, _) async => throw const FileSystemException('write failed'),
        onError: errors.add,
      );
      await _editor(tester, controller);
      await _openCrop(tester);
      await tester.tap(find.text('1:1'));
      await tester.pumpAndSettle();
      await _done(tester);
      expect(errors.single, isA<FileSystemException>());
      expect(controller.document.toSource(), source);
      expect(controller.canUndo, isFalse);
      expect(find.text('Crop image'), findsOneWidget);
    },
  );

  for (final kind in [PointerDeviceKind.touch, PointerDeviceKind.mouse]) {
    testWidgets('crop corners and interior drag with $kind', (tester) async {
      final bytes = (await tester.runAsync(_png))!;
      final outputs = <Uint8List>[];
      await tester.pumpWidget(
        MaterialApp(
          home: ImageCropPage(
            bytes: bytes,
            onDone: (bytes) async => outputs.add(bytes),
            onError: (error) => fail('$error'),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      final surface = tester.getRect(find.byKey(const Key('crop-surface')));
      final leftTop = Offset(
        surface.left,
        surface.center.dy - surface.width / 4,
      );
      {
        final gesture = await tester.startGesture(
          leftTop + const Offset(5, 5),
          kind: kind,
        );
        await gesture.moveBy(const Offset(60, 40));
        await gesture.moveBy(const Offset(20, 10));
        await gesture.up();
        await tester.pumpAndSettle();
      }
      await tester.dragFrom(surface.center, const Offset(-30, -20));
      await tester.pumpAndSettle();
      await _done(tester);
      expect(outputs, hasLength(1));
      final image = await tester.runAsync(
        () => decodeCropImage(outputs.single),
      );
      expect(image!.width, lessThan(120));
      expect(image.height, lessThan(60));
      image.dispose();
    });
  }

  testWidgets('tiny image full-pixel crop is a no-op', (tester) async {
    final bytes = (await tester.runAsync(() => _png(width: 1, height: 1)))!;
    var writes = 0;
    final source = imageAttachmentSource('/assets/tiny.png');
    final controller = _controller(
      source,
      read: (_) async => bytes,
      write: (_, _) async {
        writes++;
        return '/assets/tiny-crop-deadbeef.png';
      },
    );
    await _editor(tester, controller);
    await _openCrop(tester);
    await tester.tap(find.text('16:9'));
    await tester.pumpAndSettle();
    await _done(tester);
    expect(writes, 0);
    expect(controller.document.toSource(), source);
    expect(controller.canUndo, isFalse);
  });

  testWidgets('crop decode failure reports error and closes without an edit', (
    tester,
  ) async {
    final errors = <Object>[];
    final bytes = Uint8List.fromList([1, 2, 3]);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => ImageCropPage(
                  bytes: bytes,
                  onDone: (_) async => fail('must not save'),
                  onError: errors.add,
                ),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(errors, hasLength(1));
    expect(find.text('Crop image'), findsNothing);
  });

  for (final bytes in <Uint8List?>[
    null,
    Uint8List.fromList([1, 2, 3]),
  ]) {
    testWidgets('missing or undecodable image has no Crop action ($bytes)', (
      tester,
    ) async {
      final controller = _controller(
        imageAttachmentSource('/assets/x.png'),
        read: (_) async => bytes,
        write: (_, _) async => fail('must not write'),
      );
      await _editor(tester, controller);
      await tester.tap(find.byIcon(Icons.attach_file));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Crop'), findsNothing);
    });
  }
}
