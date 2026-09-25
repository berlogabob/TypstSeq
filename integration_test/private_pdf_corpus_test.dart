import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:tylog/database/tylog_database.dart';
import 'package:tylog/pdf/annotation_reattach.dart';
import 'package:tylog/pdf/pdf_extraction.dart';
import 'package:tylog/pdf/pdf_reader_screen.dart';
import 'package:tylog/pdf/pdf_reader_store.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('opt-in redacted private PDF corpus check', (tester) async {
    final rootPath = Platform.environment['TYLOG_PRIVATE_PDF_ROOT'];
    if (rootPath == null || rootPath.isEmpty) {
      throw StateError(
        'Set TYLOG_PRIVATE_PDF_ROOT to the private corpus root.',
      );
    }
    final root = Directory(rootPath);
    if (!await root.exists()) {
      throw StateError('Private corpus root unavailable.');
    }
    final files = await root
        .list(recursive: true, followLinks: false)
        .where(
          (entry) => entry is File && entry.path.toLowerCase().endsWith('.pdf'),
        )
        .cast<File>()
        .toList();
    var opened = 0, failed = 0, pages = 0, textPages = 0, chars = 0;
    var exact = 0, ambiguous = 0, missing = 0, saved = 0, moved = 0;
    var noTextRasterized = 0;
    final scratch = await Directory.systemTemp.createTemp('tylog-pdf-check-');
    try {
      for (var i = 0; i < files.length; i++) {
        final bytes = await files[i].readAsBytes();
        final database = await openDatabaseWithFile(
          File('${scratch.path}/$i.sqlite'),
        );
        try {
          await tester.pumpWidget(
            MaterialApp(
              home: PdfReaderScreen(
                bytes: bytes,
                path: 'private-corpus/$i.pdf',
                database: database,
              ),
            ),
          );
          await _pumpUntil(tester, () async {
            final viewer = find.byType(PdfViewer);
            if (viewer.evaluate().isEmpty) return false;
            return tester.widget<PdfViewer>(viewer).controller?.isReady ??
                false;
          });
          SourceVersionData? version;
          for (var attempt = 0; attempt < 240 && version == null; attempt++) {
            await tester.pump(const Duration(milliseconds: 250));
            final rows = await database.select(database.sourceVersions).get();
            if (rows.isNotEmpty) version = rows.single;
          }
          if (version == null) {
            failed++;
          } else {
            final rows = (jsonDecode(version.pagesJson) as List)
                .cast<Map<String, dynamic>>();
            final extracted = rows
                .map(
                  (row) => PdfTextPage(
                    page: row['page'] as int,
                    text: row['text'] as String,
                    start: row['start'] as int,
                    end: row['end'] as int,
                  ),
                )
                .toList();
            pages += extracted.length;
            textPages += extracted
                .where((page) => page.text.trim().isNotEmpty)
                .length;
            chars += extracted.fold<int>(
              0,
              (sum, page) => sum + page.text.length,
            );
            opened++;
            final sourceStatus = PdfExtractionStatus.values.byName(
              version.status,
            );
            final pageIndex = extracted.indexWhere(
              (page) => page.text.length >= 24,
            );
            if (sourceStatus != PdfExtractionStatus.extracted ||
                pageIndex < 0) {
              missing++;
              final viewer = tester.widget<PdfViewer>(find.byType(PdfViewer));
              final image = await viewer.controller!.document.pages.first
                  .render(fullWidth: 256, fullHeight: 256);
              expect(image, isNotNull);
              try {
                final pixels = image!.pixels;
                var hasInk = false;
                for (var i = 0; i < pixels.length; i += 4) {
                  if (pixels[i] < 250 ||
                      pixels[i + 1] < 250 ||
                      pixels[i + 2] < 250) {
                    hasInk = true;
                    break;
                  }
                }
                expect(hasInk, isTrue);
                noTextRasterized++;
              } finally {
                image!.dispose();
              }
            } else {
              final page = extracted[pageIndex];
              const length = 12;
              final first = page.text.indexOf(RegExp(r'\S'));
              final start = first >= 0 && first + length <= page.text.length
                  ? first
                  : 0;
              final extraction = PdfExtraction(
                sourceVersionId: version.id,
                sha256: version.sha256,
                status: sourceStatus,
                pages: extracted,
              );
              await savePdfReaderSelection(
                database: database,
                extraction: extraction,
                page: pageIndex,
                localStart: start,
                localEnd: start + length,
              );
              final before =
                  (await database.select(database.annotations).get()).single;
              saved++;
              final attached = reattachAnnotation(
                quote: before.quote,
                oldStartOffset: before.startOffset,
                pages: extracted,
              );
              switch (attached.status) {
                case ReattachmentStatus.exact:
                  exact++;
                case ReattachmentStatus.ambiguous:
                  ambiguous++;
                case ReattachmentStatus.missing:
                  missing++;
              }
              final target = start == 0 ? 12 : 0;
              await reassignPdfReaderSelection(
                database: database,
                annotationId: before.id,
                extraction: extraction,
                page: pageIndex,
                localStart: target,
                localEnd: target + length,
              );
              final after =
                  (await database.select(database.annotations).get()).single;
              if (after.id == before.id &&
                  after.startOffset != before.startOffset) {
                moved++;
              }
            }
          }
        } catch (_) {
          failed++;
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 50));
          await database.close();
        }
      }
      // Aggregate counts only; no private paths, titles, text, or hashes.
      // ignore: avoid_print
      print(
        'PRIVATE_PDF_SUMMARY files=${files.length} opened=$opened failed=$failed '
        'pages=$pages text_pages=$textPages chars=$chars anchor_exact=$exact '
        'anchor_ambiguous=$ambiguous anchor_missing=$missing saved=$saved '
        'moved=$moved no_text_rasterized=$noTextRasterized',
      );
      expect(files, isNotEmpty);
      expect(failed, 0);
    } finally {
      await scratch.delete(recursive: true);
    }
  });
}

Future<void> _pumpUntil(
  WidgetTester tester,
  Future<bool> Function() condition,
) async {
  for (var attempt = 0; attempt < 240; attempt++) {
    if (await condition()) return;
    await tester.pump(const Duration(milliseconds: 250));
  }
  fail('Timed out waiting for PDF viewer readiness.');
}
