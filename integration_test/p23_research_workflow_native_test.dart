import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:typst_flutter/src/rust/frb_generated.dart';
import 'package:tylog/app_mobile.dart';
import 'package:tylog/database/note_persistence.dart';
import 'package:tylog/database/tylog_database.dart';
import 'package:tylog/pdf/pdf_reader_screen.dart';
import 'package:tylog/report.dart';
import 'package:tylog/retrieval/semantic_model.dart';
import 'package:tylog/retrieval/semantic_search_controller.dart';
import 'package:tylog/scanner.dart';
import 'package:tylog/saved_searches.dart';
import 'package:tylog/vault.dart';
import 'package:tylog/vault_registry.dart';

import 'p21_inputs.dart';

const _modelEnv = 'P21_MODEL_DIR';
const _vaultEnv = 'P21_VAULT_ROOT';

Future<void> main() async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    try {
      await RustLib.init();
    } on StateError catch (error) {
      if (!error.message.contains('twice')) rethrow;
    }
  });

  testWidgets('P23 complete research workflow', (tester) async {
    final skipped = <String>[];
    void skip(String step, String reason) {
      skipped.add('$step: $reason');
      markTestSkipped('$step: $reason');
    }

    if (!Platform.isMacOS && !Platform.isAndroid) {
      skip('all', 'P23 native acceptance targets macOS and Android.');
      return;
    }
    final inputs = await awaitP21Inputs();
    final model = await _prepareModel(skip, inputs?.model);
    if (model == null) return;

    final root = await Directory.systemTemp.createTemp('tylog_p23_vault_');
    addTearDown(() => root.delete(recursive: true));
    final configured = inputs?.vault?.path ?? Platform.environment[_vaultEnv];
    if (configured == null || configured.isEmpty) {
      await _fixture(root);
    } else {
      await _copyDirectory(Directory(configured), root);
    }
    final vault = Vault(root);
    await vault.ensureCreated();
    await SavedSearchStore(vault.storage).save(const [
      SavedSearch(
        name: 'Research set',
        query: 'cited evidence',
        tag: 'research',
        status: 'ready',
      ),
    ]);
    final index = await scanVaultStorage(vault.storage, force: true);
    expect(index.notesByPath, isNotEmpty);
    final notePath = 'articles/evidence.typ';
    final stalePath = 'articles/stale.typ';
    final pdfPath = 'research/evidence.pdf';
    expect(index.notesByPath, contains(notePath));
    final sourceBefore = await vault.storage.readBytes(notePath);
    final pdfBefore = await vault.storage.readBytes(pdfPath);
    final pdfChanged = _textPdf('Evidence alpha Evidence beta Evidence gamma');

    final database = TyLogDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    for (final path in index.notesByPath.keys) {
      await persistNoteSource(
        database: database,
        path: path,
        source: await vault.storage.readText(path),
      );
    }
    final controller = SemanticSearchController(db: database, modelRoot: model);
    addTearDown(controller.dispose);
    await controller.init();
    await controller.refreshNotes();
    expect(controller.ready, isTrue);
    final hits = await controller.searchNotes('cited evidence', limit: 20);
    expect(hits.map((hit) => hit.id), contains(notePath));
    final citations = await controller.citations('cited evidence');
    final cited = citations.firstWhere(
      (item) => item.sourceLocator == notePath,
    );
    expect(cited.startOffset, greaterThanOrEqualTo(0));
    expect(cited.endOffset, greaterThan(cited.startOffset));

    final homeClosed = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          startup: () async {},
          databaseOpener: () async => database,
          databaseCloser: (value) async {
            if (!homeClosed.isCompleted) homeClosed.complete();
          },
        ),
      ),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await homeClosed.future;
    });
    final dynamic home = tester.state(find.byType(HomeScreen));
    final workspace = home.workspace;
    workspace
      ..entry = VaultEntry(id: 'p23', name: 'P23', path: root.path)
      ..vault = vault
      ..index = index
      ..searchReady = true
      ..note = notePath
      ..source = await vault.storage.readText(notePath);
    workspace.notifyListeners();
    await tester.pumpAndSettle();

    // 1. The saved-search chip exercises both tag and status filtering seams.
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Research set'), findsOneWidget);
    await tester.tap(find.text('Research set'));
    await tester.pumpAndSettle();
    expect(find.text('Evidence'), findsAtLeastNWidgets(1));
    expect(find.text('Unfiltered'), findsNothing);

    // 2. Hybrid search opens the cited note passage with its stored range.
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'cited evidence');
    await _waitFor(tester, () => find.text('Evidence').evaluate().isNotEmpty);
    final citationTile = find.byKey(ValueKey('citation-${cited.chunkId}'));
    expect(citationTile, findsOneWidget);
    await tester.tap(citationTile);
    await tester.pumpAndSettle();
    expect(workspace.note, notePath);
    expect(workspace.source, contains('cited evidence'));

    // 5. Delete a note after its row is rendered; the real open-note seam must
    // not fall through to another path.
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'old row');
    await _waitFor(tester, () => find.text('Stale').evaluate().isNotEmpty);
    await vault.storage.delete(stalePath);
    await tester.tap(find.text('Stale').last);
    await tester.pumpAndSettle();
    expect(workspace.note, notePath);

    // 3. Save, reassign, reopen and follow the persisted PDF source anchor.
    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderScreen(
          bytes: pdfBefore,
          path: pdfPath,
          database: database,
          initialStartOffset: 0,
          initialEndOffset: 8,
        ),
      ),
    );
    await _annotate(tester, database, 'Evidence', occurrence: 0);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderScreen(
          bytes: pdfChanged,
          path: pdfPath,
          database: database,
        ),
      ),
    );
    await _waitFor(tester, () => find.byType(PdfViewer).evaluate().isNotEmpty);
    await tester.tap(find.byTooltip('Highlights'));
    await tester.pumpAndSettle();
    await _waitFor(
      tester,
      () => find.textContaining('Needs review').evaluate().isNotEmpty,
    );
    await tester.tap(find.textContaining('Needs review'));
    await tester.pumpAndSettle();
    expect(find.text('Highlight needs review'), findsOneWidget);
    await tester.tap(find.text('Select replacement'));
    await tester.pumpAndSettle();
    await _selectPdfText(tester, 'Evidence', occurrence: 1);
    await tester.tap(find.byTooltip('Save highlight'));
    await _waitFor(
      tester,
      () async =>
          (await database.select(database.annotations).get()).isNotEmpty,
    );
    final annotation =
        (await database.select(database.annotations).get()).single;
    expect(annotation.quote, 'Evidence');
    expect(annotation.startOffset, greaterThanOrEqualTo(0));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderScreen(
          bytes: pdfChanged,
          path: pdfPath,
          database: database,
          initialSourceVersionId: annotation.sourceVersionId,
          initialStartOffset: annotation.startOffset,
          initialEndOffset: annotation.endOffset,
        ),
      ),
    );
    await _waitFor(tester, () => find.byType(PdfViewer).evaluate().isNotEmpty);
    await tester.tap(find.byTooltip('Highlights'));
    await tester.pumpAndSettle();
    expect(find.text('Evidence'), findsOneWidget);
    await tester.tap(find.text('Evidence'));

    // 4. Filtered report, bibliography, deterministic source and PDF bytes.
    final filtered = selectReportNotes(
      index,
      const ReportFilter(tags: {'research'}, articleStatus: 'ready'),
    );
    expect(filtered.map((note) => note.path), contains(notePath));
    expect(
      filtered.map((note) => note.path),
      isNot(contains('notes/personal.typ')),
    );
    final reportPath = await writeReportStorage(
      vault.storage,
      'P23 research',
      index,
      const ReportFilter(tags: {'research'}, articleStatus: 'ready'),
    );
    final reportSource = await vault.storage.readText(reportPath);
    expect(reportSource, contains('#include "/$notePath"'));
    expect(reportSource, contains('#bibliography'));
    final pdf1 = await exportReportPdf(root, File('${root.path}/$reportPath'));
    final bytes1 = await pdf1.readAsBytes();
    final hash1 = sha256.convert(bytes1).toString();
    final pdf2 = await exportReportPdf(root, File('${root.path}/$reportPath'));
    final bytes2 = await pdf2.readAsBytes();
    expect(sha256.convert(bytes2).toString(), hash1);
    expect(utf8.decode(bytes1.take(4).toList()), '%PDF');

    // 6. Only the database changed; copied source files remain byte-identical.
    expect(await vault.storage.readBytes(notePath), sourceBefore);
    expect(await vault.storage.readBytes(pdfPath), pdfBefore);
    final result = {
      'steps_covered': [1, 2, 3, 4, 5, 6],
      'steps_skipped': skipped,
      'selected_records': filtered.map((note) => note.path).toList(),
      'bibliography': reportSource.contains('#bibliography'),
      'report_sha256': hash1,
      'source_unchanged': true,
      'pdf_unchanged': true,
      'lib_bugs_suspected': <String>[],
    };
    // The app sandbox on Android has no writable ./build; the log line is the record.
    // ignore: avoid_print
    print('P23_RESULT ${jsonEncode(result)}');
    if (!Platform.isAndroid) {
      await Directory('build').create(recursive: true);
      await File(
        'build/p23_native_result.json',
      ).writeAsString(jsonEncode(result));
    }
    // ignore: avoid_print
    print('P23 steps covered: 1, 2, 3, 4, 5, 6');
    // ignore: avoid_print
    print(
      'P23 steps skipped with reasons: ${skipped.isEmpty ? 'none' : skipped.join('; ')}',
    );
    // ignore: avoid_print
    print('P23 lib bugs suspected: none');
  });
}

Future<Directory?> _prepareModel(
  void Function(String, String) skip, [
  Directory? handshakeRoot,
]) async {
  final support = await getApplicationSupportDirectory();
  final installed = Directory(
    '${support.path}/models/multilingual-e5-small-ccc66d3',
  );
  final configured = handshakeRoot?.path ?? Platform.environment[_modelEnv];
  final source = configured == null || configured.isEmpty
      ? null
      : Directory(configured);
  if (source != null && await SemanticModelStore(source).installed() == null) {
    skip('model', 'P21_MODEL_DIR is not a verified semantic model.');
    return null;
  }
  if (source != null) {
    await installed.create(recursive: true);
    for (final item in kSemanticModelManifest) {
      final bytes = await File('${source.path}/${item.name}').readAsBytes();
      expect(bytes.length, item.bytes, reason: item.name);
      expect(sha256.convert(bytes).toString(), item.sha256, reason: item.name);
      await File(
        '${installed.path}/${item.name}',
      ).writeAsBytes(bytes, flush: true);
    }
    await File('${installed.path}/verified').writeAsString('verified\n');
  }
  if (await SemanticModelStore(installed).installed() == null) {
    skip('model', 'No verified P21 model found; set P21_MODEL_DIR.');
    return null;
  }
  return installed;
}

Future<void> _fixture(Directory root) async {
  final vault = Vault(root);
  await vault.ensureCreated();
  final evidencePath = await vault.page('evidence', kind: 'article');
  await vault.saveNote(
    evidencePath,
    '''${replaceNoteHeader(await vault.storage.readText(evidencePath), const NoteMetadataDraft(id: 'evidence', title: 'Evidence', kind: 'article', tags: ['research'], properties: {'status': 'ready'}))}

cited evidence passage for the native workflow.
@smith-2026
''',
  );
  final stalePath = await vault.page('stale', kind: 'article');
  await vault.saveNote(
    stalePath,
    '${replaceNoteHeader(await vault.storage.readText(stalePath), const NoteMetadataDraft(id: 'stale', title: 'Stale', kind: 'article'))}\nold row\n',
  );
  await vault.saveNote(
    'notes/personal.typ',
    '#show: tylog.note.with(id: "personal", title: "Personal")\nprivate\n',
  );
  await vault.storage.writeBytes(
    'research/evidence.pdf',
    _textPdf('Evidence alpha Evidence beta'),
  );
  await vault.storage.writeText(
    '_system/bibliography.yml',
    'smith-2026:\n  type: article\n  title: Smith 2026\n',
  );
}

Future<void> _copyDirectory(Directory source, Directory target) async {
  await target.create(recursive: true);
  await for (final entity in source.list(recursive: true, followLinks: false)) {
    final relative = entity.path.substring(source.path.length + 1);
    final destination = '${target.path}/$relative';
    if (entity is Directory) {
      await Directory(destination).create(recursive: true);
    } else if (entity is File) {
      await File(destination).parent.create(recursive: true);
      await entity.copy(destination);
    }
  }
}

Future<void> _annotate(
  WidgetTester tester,
  TyLogDatabase db,
  String text, {
  required int occurrence,
}) async {
  await _waitFor(tester, () => find.byType(PdfViewer).evaluate().isNotEmpty);
  final viewer = tester.widget<PdfViewer>(find.byType(PdfViewer));
  final controller = viewer.controller!;
  await _waitFor(tester, () async => controller.isReady);
  final page = await controller.document.pages.first.loadStructuredText();
  final start = _occurrence(page.fullText, text, occurrence);
  await controller.textSelectionDelegate.setTextSelectionPointRange(
    PdfTextSelectionRange.fromPoints(
      PdfTextSelectionPoint(page, start),
      PdfTextSelectionPoint(page, start + text.length - 1),
    ),
  );
  await tester.pumpAndSettle();
  await _waitFor(tester, () {
    final save = find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.tooltip == 'Save highlight',
    );
    return save.evaluate().isNotEmpty &&
        tester.widget<IconButton>(save).onPressed != null;
  });
  await tester.tap(find.byTooltip('Save highlight'));
  await _waitFor(
    tester,
    () async => (await db.select(db.annotations).get()).isNotEmpty,
  );
}

Future<void> _selectPdfText(
  WidgetTester tester,
  String text, {
  required int occurrence,
}) async {
  final viewer = tester.widget<PdfViewer>(find.byType(PdfViewer));
  final controller = viewer.controller!;
  await _waitFor(tester, () async => controller.isReady);
  final page = await controller.document.pages.first.loadStructuredText();
  final start = _occurrence(page.fullText, text, occurrence);
  await controller.textSelectionDelegate.setTextSelectionPointRange(
    PdfTextSelectionRange.fromPoints(
      PdfTextSelectionPoint(page, start),
      PdfTextSelectionPoint(page, start + text.length - 1),
    ),
  );
  await tester.pumpAndSettle();
}

int _occurrence(String text, String needle, int occurrence) {
  var at = -1;
  for (var i = 0; i <= occurrence; i++) {
    at = text.indexOf(needle, at + 1);
    expect(at, greaterThanOrEqualTo(0));
  }
  return at;
}

Future<void> _waitFor(
  WidgetTester tester,
  FutureOr<bool> Function() condition,
) async {
  for (var i = 0; i < 160; i++) {
    if (await condition()) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail('Timed out waiting for P23 app state');
}

Uint8List _textPdf(String text) {
  final stream = 'BT /F1 18 Tf 30 50 Td ($text) Tj ET\n';
  final objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 500 100] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>',
    '<< /Length ${stream.length} >>\nstream\n$stream\nendstream',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ];
  final output = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(output.length);
    output.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xref = output.length;
  output.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final offset in offsets) {
    output.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  output.write(
    'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF',
  );
  return Uint8List.fromList(latin1.encode(output.toString()));
}
