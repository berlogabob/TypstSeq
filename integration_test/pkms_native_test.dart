import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tylog/report.dart';
import 'package:tylog/scanner.dart';
import 'package:tylog/vault.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native v5 metadata query and report PDF export', (_) async {
    final reader = await TypstMetadataReader.create();
    try {
      final metadata = await reader.read(
        '''#import "/_system/tylog.typ" as tylog
#show: tylog.note.with(id: "root", title: "Root", kind: "project", tags: ("pkms",))
#tylog.ref-note("child")[Child]
#tylog.tag("pkms")
#tylog.date-ref("2026-07-13")[Delivery]
#tylog.attachment("assets/manual.pdf", kind: "pdf")[Manual]
#tylog.task(id: "task-1", text: "Write", due: "2026-07-13")
''',
      );
      expect(metadata.note?['id'], 'root');
      expect(metadata.note?['kind'], 'project');
      expect(metadata.links, ['child']);
      expect(metadata.tags, ['pkms']);
      expect(metadata.dates.single['date'], '2026-07-13');
      expect(metadata.attachments.single['path'], 'assets/manual.pdf');
      expect(metadata.tasks.single['id'], 'task-1');
    } finally {
      reader.dispose();
    }

    final root = await Directory.systemTemp.createTemp('tylog_export_');
    addTearDown(() => root.delete(recursive: true));
    final vault = Vault(root);
    await vault.ensureCreated();
    await vault.saveNote(
      await vault.page('Root'),
      '''#import "/_system/tylog.typ" as tylog
#show: tylog.note.with(id: "root", title: "Root", kind: "note")
= Root

Visible report content.
''',
    );
    final index = await vault.rebuildIndex();
    final report = await writeReport(
      root,
      'Book',
      index,
      const ReportFilter(kinds: {'note'}),
    );
    final pdf = await exportReportPdf(root, report);

    expect(await report.readAsString(), contains('#include "/notes/Root.typ"'));
    expect(await pdf.length(), greaterThan(100));
    expect(String.fromCharCodes((await pdf.readAsBytes()).take(4)), '%PDF');
  });
}
