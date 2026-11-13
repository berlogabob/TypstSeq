import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tylog/models.dart';
import 'package:tylog/processing_jobs.dart';
import 'package:tylog/vault.dart';
import 'package:tylog/widgets/journal_feed.dart';

import 'support/temp_dir.dart';

void main() {
  LiveTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('failed article for the day can be retried', (tester) async {
    final root = await Directory.systemTemp.createTemp('journal_failed_links_');
    addTearDown(() => deleteTempDir(root));
    final vault = Vault(root);
    const day = 'daily/2026-10-08.typ';
    const jobPath = '_system/jobs/articles/one.json';
    await vault.storage.writeText(day, 'A bare link: https://www.example.com');
    await vault.storage.writeText(
      jobPath,
      jsonEncode({
        'status': 'failed',
        'origin': day,
        'url': 'https://www.example.com/article',
        'reason': 'timeout',
      }),
    );
    await vault.storage.writeText(
      '_system/jobs/articles/other.json',
      jsonEncode({
        'status': 'failed',
        'origin': 'daily/2026-10-07.typ',
        'url': 'https://other.example/article',
        'reason': 'blocked',
      }),
    );
    final jobs = ProcessingJobs();
    addTearDown(jobs.dispose);
    await jobs.refresh(vault.storage);
    const note = NoteRef(
      id: '2026-10-08',
      path: day,
      title: '2026-10-08',
      date: '2026-10-08',
      kind: 'daily',
      outgoingLinks: [],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: JournalFeed(
          vault: vault,
          index: VaultIndex(
            notesByPath: {day: note},
            backlinksByTarget: const {},
          ),
          onOpenPath: (_) {},
          processingJobs: jobs,
        ),
      ),
    );
    for (
      var i = 0;
      i < 30 &&
          find
              .text("couldn't save example.com: site timed out")
              .evaluate()
              .isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(
      find.text("couldn't save example.com: site timed out"),
      findsOneWidget,
    );
    expect(find.textContaining('other.example'), findsNothing);
    await tester.tap(find.text('Retry'));
    for (
      var i = 0;
      i < 30 && jobs.jobs.firstWhere((job) => job.path == jobPath).failed;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
    expect(
      jsonDecode(await vault.storage.readText(jobPath))['status'],
      'queued',
    );
    expect(
      find.text("couldn't save example.com: site timed out"),
      findsNothing,
    );
  });
}
