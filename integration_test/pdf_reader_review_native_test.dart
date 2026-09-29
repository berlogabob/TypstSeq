import 'dart:typed_data';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:tylog/database/tylog_database.dart';
import 'package:tylog/pdf/pdf_reader_screen.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ambiguous highlight is reassigned through Needs review', (
    tester,
  ) async {
    final dir = await Directory.systemTemp.createTemp('tylog-review-');
    final database = await openDatabaseWithFile(
      File('${dir.path}/reader.sqlite'),
    );
    addTearDown(() async {
      await database.close();
      await dir.delete(recursive: true);
    });

    final bytes1 = _textPdf('Alpha beta');

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderScreen(
          bytes: bytes1,
          path: 'research/review.pdf',
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
    final start = pageText.fullText.indexOf('Alpha');
    expect(start, greaterThanOrEqualTo(0));
    await controller.textSelectionDelegate.setTextSelectionPointRange(
      PdfTextSelectionRange.fromPoints(
        PdfTextSelectionPoint(pageText, start),
        PdfTextSelectionPoint(pageText, start + 'Alpha'.length - 1),
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

    final first = (await database.select(database.annotations).get()).single;

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    final bytes2 = _textPdf('Alpha beta Alpha gamma');
    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderScreen(
          bytes: bytes2,
          path: 'research/review.pdf',
          database: database,
        ),
      ),
    );
    await _pumpUntil(
      tester,
      () async =>
          (await database.select(database.sourceVersions).get()).isNotEmpty,
    );

    final viewer2 = find.byType(PdfViewer);
    expect(viewer2, findsOneWidget);
    final controller2 = tester.widget<PdfViewer>(viewer2).controller!;
    await _pumpUntil(tester, () async => controller2.isReady);

    await tester.tap(find.byTooltip('Highlights'));
    await tester.pumpAndSettle();
    await _pumpUntil(
      tester,
      () async => find
          .text('Needs review: quote appears more than once')
          .evaluate()
          .isNotEmpty,
    );
    await tester.tap(find.text('Needs review: quote appears more than once'));
    await tester.pumpAndSettle();

    expect(find.text('Highlight needs review'), findsOneWidget);
    await tester.tap(find.text('Select replacement'));
    await tester.pumpAndSettle();
    expect(
      find.text('Select replacement text, then save highlight.'),
      findsOneWidget,
    );

    final pageText2 = await controller2.document.pages.first
        .loadStructuredText();
    final second = pageText2.fullText.indexOf(
      'Alpha',
      pageText2.fullText.indexOf('Alpha') + 1,
    );
    await controller2.textSelectionDelegate.setTextSelectionPointRange(
      PdfTextSelectionRange.fromPoints(
        PdfTextSelectionPoint(pageText2, second),
        PdfTextSelectionPoint(pageText2, second + 'Alpha'.length - 1),
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

    final rows = await database.select(database.annotations).get();
    expect(rows, hasLength(1));
    expect(rows.single.id, first.id);
    expect(rows.single.quote, 'Alpha');
    expect(rows.single.startOffset, greaterThan(first.startOffset));

    await tester.tap(find.byTooltip('Highlights'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Needs review'), findsNothing);
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

Uint8List _textPdf(String text) {
  final objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 100] '
        '/Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>',
    '<< /Length ${'BT /F1 18 Tf 30 50 Td ($text) Tj ET\n'.length} >>\nstream\nBT /F1 18 Tf 30 50 Td ($text) Tj ET\nendstream',
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
