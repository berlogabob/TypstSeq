import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tylog/processing_jobs.dart';
import 'package:tylog/rich_editor.dart';
import 'package:tylog/vault.dart';
import 'package:tylog/widgets/failed_article_row.dart';

import 'support/temp_dir.dart';

void main() {
  LiveTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('failed bare article link offers retry without changing source', (
    tester,
  ) async {
    final root = await Directory.systemTemp.createTemp('editor_failed_links_');
    addTearDown(() => deleteTempDir(root));
    final vault = Vault(root);
    const path = 'daily/2026-10-08.typ';
    const jobPath = '_system/jobs/articles/one.json';
    const source = 'https://www.example.com/article\n\nNext line\n';
    Future<void> writeJob(
      String name,
      String status,
      String url,
      String origin,
    ) => vault.storage.writeText(
      '_system/jobs/articles/$name.json',
      jsonEncode({
        'status': status,
        'origin': origin,
        'url': url,
        'reason': 'timeout',
      }),
    );
    await writeJob('one', 'done', 'https://www.example.com/article', path);
    await writeJob('other', 'failed', 'https://other.example/', path);
    await writeJob(
      'origin',
      'failed',
      'https://www.example.com/article',
      'other.typ',
    );
    final jobs = ProcessingJobs();
    addTearDown(jobs.dispose);
    await jobs.refresh(vault.storage);
    final controller = TyLogEditingController(
      source: source,
      onSourceChanged: (_) {},
      onError: (e) => fail('$e'),
      onProtectedTap: (_) {},
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TyLogRichEditor(
            controller: controller,
            onInsert: () async {},
            processingJobs: jobs,
            notePath: path,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    double nextLineTop() {
      final editable = tester
          .state<EditableTextState>(find.byType(EditableText))
          .renderEditable;
      final caret = editable.getLocalRectForCaret(
        TextPosition(offset: controller.text.indexOf('Next line')),
      );
      return editable.localToGlobal(caret.topLeft).dy;
    }

    expect(find.textContaining("couldn't save"), findsNothing);
    expect(controller.document.toSource(), source);
    final originalNextLineTop = nextLineTop();
    final before = tester.getTopLeft(
      find.byKey(const Key('rich-journal-editor')),
    );
    await writeJob('one', 'failed', 'https://www.example.com/article', path);
    await jobs.refresh(vault.storage);
    await tester.pumpAndSettle();
    expect(
      find.text("couldn't save example.com: site timed out"),
      findsOneWidget,
    );
    expect(controller.document.toSource(), source);
    expect(
      nextLineTop(),
      greaterThanOrEqualTo(
        tester.getBottomLeft(find.byType(FailedArticleRow)).dy,
      ),
    );
    expect(
      tester.getTopLeft(find.byKey(const Key('rich-journal-editor'))),
      before,
    );
    await tester.tap(find.text('Retry'));
    for (
      var i = 0;
      i < 30 && jobs.jobs.firstWhere((j) => j.path == jobPath).failed;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
    expect(
      jsonDecode(await vault.storage.readText(jobPath))['status'],
      'queued',
    );
    expect(find.textContaining("couldn't save"), findsNothing);
    expect(controller.document.toSource(), source);
    expect(nextLineTop(), closeTo(originalNextLineTop, 0.01));
  });
}
