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
}

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
