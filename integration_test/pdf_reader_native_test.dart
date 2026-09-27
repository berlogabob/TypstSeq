import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:tylog/database/tylog_database.dart';
import 'package:tylog/pdf/pdf_reader_screen.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('PDF reader persists and reopens a native text highlight', (
    tester,
  ) async {
    const reopen = bool.fromEnvironment('P24_REOPEN_ONLY');
    final directory = await getApplicationSupportDirectory();
    final file = File('${directory.path}/pdf-reader-native-restart.sqlite');
    if (!reopen) {
      for (final suffix in ['', '-wal', '-shm']) {
        final old = File('${file.path}$suffix');
        if (await old.exists()) await old.delete();
      }
    }
    final database = await openDatabaseWithFile(file);
    if (reopen) {
      expect(
        (await database.select(database.annotations).get()).single.quote,
        'Hello',
      );
      expect(
        await database.select(database.sourceVersions).get(),
        hasLength(1),
      );
      addTearDown(database.close);
    }
    // Seed run deliberately leaves the database open for external force-stop.

    final bytes = _helloPdf();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderScreen(
          bytes: bytes,
          path: 'research/hello.pdf',
          database: database,
        ),
      ),
    );
    await _pumpUntil(
      tester,
      () async =>
          (await database.select(database.sourceVersions).get()).isNotEmpty,
    );

    final viewer = find.byType(PdfViewer);
    expect(viewer, findsOneWidget);
    final controller = tester.widget<PdfViewer>(viewer).controller!;
    await _pumpUntil(tester, () async => controller.isReady);
    final pageText = await controller.document.pages.first.loadStructuredText();
    final start = pageText.fullText.indexOf('Hello');
    expect(start, greaterThanOrEqualTo(0));
    await controller.textSelectionDelegate.setTextSelectionPointRange(
      PdfTextSelectionRange.fromPoints(
        PdfTextSelectionPoint(pageText, start),
        PdfTextSelectionPoint(pageText, start + 'Hello'.length - 1),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Save highlight'), findsOneWidget);
    await _pumpUntil(
      tester,
      () async =>
          tester
              .widget<IconButton>(
                find.byWidgetPredicate(
                  (w) => w is IconButton && w.tooltip == 'Save highlight',
                ),
              )
              .onPressed !=
          null,
    );
    await tester.tap(find.byTooltip('Save highlight'));
    await _pumpUntil(
      tester,
      () async =>
          (await database.select(database.annotations).get()).isNotEmpty,
    );
    await tester.pumpAndSettle();

    final annotations = await database.select(database.annotations).get();
    expect(annotations, hasLength(1));
    expect(annotations.single.quote, contains('Hello'));
    expect(annotations.single.startOffset, greaterThanOrEqualTo(0));
    expect(
      annotations.single.endOffset,
      greaterThan(annotations.single.startOffset),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderScreen(
          bytes: bytes,
          path: 'research/hello.pdf',
          database: database,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _pumpUntil(tester, () async {
      await tester.pump(const Duration(milliseconds: 100));
      return find.byType(PdfViewer).evaluate().isNotEmpty;
    });
    await tester.tap(find.byTooltip('Highlights'));
    await tester.pumpAndSettle();
    await _pumpUntil(
      tester,
      () async => find.text(annotations.single.quote).evaluate().isNotEmpty,
    );
    expect(find.text(annotations.single.quote), findsOneWidget);
    await tester.tap(find.text(annotations.single.quote));
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsNothing);
  });

  testWidgets('PDF reader renders vector-only PDFs without selectable text', (
    tester,
  ) async {
    final directory = await getApplicationSupportDirectory();
    final file = File('${directory.path}/pdf-reader-native-vector.sqlite');
    for (final suffix in ['', '-wal', '-shm']) {
      final old = File('${file.path}$suffix');
      if (await old.exists()) await old.delete();
    }
    final database = await openDatabaseWithFile(file);
    addTearDown(() async {
      await database.close();
      for (final suffix in ['', '-wal', '-shm']) {
        final old = File('${file.path}$suffix');
        if (await old.exists()) await old.delete();
      }
    });

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderScreen(
          bytes: _vectorOnlyPdf(),
          path: 'research/vector-only.pdf',
          database: database,
        ),
      ),
    );
    await _pumpUntil(tester, () async {
      final viewer = find.byType(PdfViewer);
      if (viewer.evaluate().isEmpty) return false;
      return tester.widget<PdfViewer>(viewer).controller?.isReady ?? false;
    });
    await _pumpUntil(
      tester,
      () async => find
          .text('No selectable text. You can still read this PDF.')
          .evaluate()
          .isNotEmpty,
    );

    expect(find.byType(PdfViewer), findsOneWidget);
    final save = tester.widget<IconButton>(
      find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == 'Save highlight',
      ),
    );
    expect(save.onPressed, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('PDF reader opens a password-protected PDF after retries', (
    tester,
  ) async {
    final directory = await Directory.systemTemp.createTemp('tylog-password-');
    final database = await openDatabaseWithFile(
      File('${directory.path}/reader.sqlite'),
    );
    addTearDown(() async {
      await database.close();
      await directory.delete(recursive: true);
    });
    final bytes = _passwordPdf;
    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderScreen(
          bytes: bytes,
          path: 'research/password-protected.pdf',
          database: database,
        ),
      ),
    );
    await _pumpUntil(
      tester,
      () async =>
          find.byKey(const Key('pdf-password-field')).evaluate().isNotEmpty,
    );
    _typePassword(tester, 'wrong');
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Wrong password, try again'), findsOneWidget);
    _typePassword(tester, 'tylog');
    await tester.tap(find.text('Open'));
    await _pumpUntil(tester, () async {
      final viewer = find.byType(PdfViewer);
      return viewer.evaluate().isNotEmpty &&
          (tester.widget<PdfViewer>(viewer).controller?.isReady ?? false);
    });
    final text = await tester
        .widget<PdfViewer>(find.byType(PdfViewer))
        .controller!
        .document
        .pages
        .first
        .loadStructuredText();
    expect(text.fullText, contains('Password research'));
  });

  testWidgets('cancelling a password prompt does not write a source version', (
    tester,
  ) async {
    final directory = await Directory.systemTemp.createTemp(
      'tylog-password-cancel-',
    );
    final database = await openDatabaseWithFile(
      File('${directory.path}/reader.sqlite'),
    );
    addTearDown(() async {
      await database.close();
      await directory.delete(recursive: true);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderScreen(
          bytes: _passwordPdf,
          path: 'research/password-protected-cancel.pdf',
          database: database,
        ),
      ),
    );
    await _pumpUntil(
      tester,
      () async =>
          find.byKey(const Key('pdf-password-field')).evaluate().isNotEmpty,
    );
    await tester.tap(find.text('Cancel'));
    await _pumpUntil(
      tester,
      () async =>
          find.byKey(const Key('pdf-password-required')).evaluate().isNotEmpty,
    );
    expect(await database.select(database.sourceVersions).get(), isEmpty);
  });
}

// Android keyboards ignore tester.enterText in this harness (see the P12
// frame test), so write the dialog field's controller, which Open reads.
void _typePassword(WidgetTester tester, String password) =>
    tester
            .widget<TextField>(find.byKey(const Key('pdf-password-field')))
            .controller!
            .text =
        password;

Future<void> _pumpUntil(
  WidgetTester tester,
  Future<bool> Function() condition,
) async {
  for (var i = 0; i < 120; i++) {
    if (await condition()) return;
    await tester.pump(const Duration(milliseconds: 250));
  }
  fail('Timed out waiting for PDF extraction');
}

Uint8List _helloPdf() {
  final objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 100] '
        '/Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>',
    '<< /Length ${'BT /F1 18 Tf 30 50 Td (Hello research) Tj ET\n'.length} >>\nstream\nBT /F1 18 Tf 30 50 Td (Hello research) Tj ET\nendstream',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ];
  final output = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(output.length);
    output
      ..writeln('${i + 1} 0 obj')
      ..writeln(objects[i])
      ..writeln('endobj');
  }
  final xref = output.length;
  output
    ..writeln('xref')
    ..writeln('0 ${objects.length + 1}')
    ..writeln('0000000000 65535 f ');
  for (final offset in offsets) {
    output.writeln('${offset.toString().padLeft(10, '0')} 00000 n ');
  }
  output
    ..writeln('trailer')
    ..writeln('<< /Size ${objects.length + 1} /Root 1 0 R >>')
    ..writeln('startxref')
    ..writeln(xref)
    ..write('%%EOF\n');
  return Uint8List.fromList(output.toString().codeUnits);
}

Uint8List _vectorOnlyPdf() {
  const content = '0 0 300 100 re f\n';
  final objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 100] '
        '/Contents 4 0 R >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
  ];
  final output = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(output.length);
    output
      ..writeln('${i + 1} 0 obj')
      ..writeln(objects[i])
      ..writeln('endobj');
  }
  final xref = output.length;
  output
    ..writeln('xref')
    ..writeln('0 ${objects.length + 1}')
    ..writeln('0000000000 65535 f ');
  for (final offset in offsets) {
    output.writeln('${offset.toString().padLeft(10, '0')} 00000 n ');
  }
  output
    ..writeln('trailer')
    ..writeln('<< /Size ${objects.length + 1} /Root 1 0 R >>')
    ..writeln('startxref')
    ..writeln(xref)
    ..write('%%EOF\n');
  return Uint8List.fromList(output.toString().codeUnits);
}

// RC4-128 PDF, user password 'tylog'; regenerate with tool/generate_password_pdf.py.
final _passwordPdf = base64Decode(
  'JVBERi0xLjQKMSAwIG9iago8PCAvVHlwZSAvQ2F0YWxvZyAvUGFnZXMgMiAwIFIgPj4KZW5kb2JqCjIgMCBvYmoKPDwgL1R5cGUgL1BhZ2VzIC9LaWRzIFszIDAgUl0gL0NvdW50IDEgPj4KZW5kb2JqCjMgMCBvYmoKPDwgL1R5cGUgL1BhZ2UgL1BhcmVudCAyIDAgUiAvTWVkaWFCb3ggWzAgMCAzMDAgMTAwXSAvQ29udGVudHMgNCAwIFIgL1Jlc291cmNlcyA8PCAvRm9udCA8PCAvRjEgNSAwIFIgPj4gPj4gPj4KZW5kb2JqCjQgMCBvYmoKPDwgL0xlbmd0aCA0OCA+PgpzdHJlYW0K8seEpZzQGAGFh4mkYRiavY1OzpFucv/tXorPa07ufi/qHdXL627I5RSLv1yL7EyRCmVuZHN0cmVhbQplbmRvYmoKNSAwIG9iago8PCAvVHlwZSAvRm9udCAvU3VidHlwZSAvVHlwZTEgL0Jhc2VGb250IC9IZWx2ZXRpY2EgPj4KZW5kb2JqCjYgMCBvYmoKPDwgL0ZpbHRlciAvU3RhbmRhcmQgL1YgMiAvTGVuZ3RoIDEyOCAvUiAzIC9PIDwwNjMzYTllY2UyNTkxZjk3NzkxOTE2ZWJlYTI1YmM4OGM5M2NlZTJiYmZlNjYyMTExMDBiYjc5Y2Y2Yzc2NDU3PiAvVSA8ZjJhMDAyYWU2YzE3MzVjMGM2ZjljYzM5YjJjYWZjZmMwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMD4gL1AgLTQgPj4KZW5kb2JqCnhyZWYKMCA3CjAwMDAwMDAwMDAgNjU1MzUgZiAKMDAwMDAwMDAwOSAwMDAwMCBuIAowMDAwMDAwMDU4IDAwMDAwIG4gCjAwMDAwMDAxMTUgMDAwMDAgbiAKMDAwMDAwMDI0MSAwMDAwMCBuIAowMDAwMDAwMzM5IDAwMDAwIG4gCjAwMDAwMDA0MDkgMDAwMDAgbiAKdHJhaWxlcgo8PCAvU2l6ZSA3IC9Sb290IDEgMCBSIC9FbmNyeXB0IDYgMCBSIC9JRCBbPDAxNzVmYWU0ZWEwOTZjOTkzZjUwNGU2ZmE0MGI4ZTgyPjwwMTc1ZmFlNGVhMDk2Yzk5M2Y1MDRlNmZhNDBiOGU4Mj5dID4+CnN0YXJ0eHJlZgo2MTYKJSVFT0YK',
);
