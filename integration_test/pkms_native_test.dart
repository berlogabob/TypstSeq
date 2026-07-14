import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tylog_core/cli_typst_inspector.dart';
import 'package:tylog/models.dart';
import 'package:tylog/report.dart';
import 'package:tylog/scanner.dart';
import 'package:tylog/tylog_assets.dart';
import 'package:tylog/vault.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native v5 metadata query and report PDF export', (_) async {
    final root = await Directory.systemTemp.createTemp('tylog_export_');
    addTearDown(() => root.delete(recursive: true));
    final vault = Vault(root);
    await vault.ensureCreated();

    const source = '''#import "/_system/tylog.typ" as tylog
#show: tylog.note.with(id: "root", title: "Root", kind: "project", tags: ("pkms",))
#tylog.ref-note("child")[Child]
#tylog.tag("pkms")
#tylog.date-ref("2026-07-13")[Delivery]
#tylog.attachment("assets/manual.pdf", kind: "pdf")[Manual]
#tylog.task(id: "task-1", text: "Write", due: "2026-07-13")
''';
    await vault.saveNote('projects/Root.typ', source);

    final inspector = await FlutterTypstInspector.create();
    late VaultIndex index;
    try {
      final input = TypstDocumentInput(
        path: 'projects/Root.typ',
        source: source,
        files: (await TylogAssets.load()).compilerFiles,
      );
      final embeddedRecords = await inspector.inspect(input);
      final cliRecords = await CliTypstInspector(root).inspect(input);
      expect(
        _normalizedMetadata(embeddedRecords),
        _normalizedMetadata(cliRecords),
      );

      final metadata = decodeTylogMetadataRecords(embeddedRecords);
      expect(metadata.note?['id'], 'root');
      expect(metadata.note?['kind'], 'project');
      expect(metadata.links, ['child']);
      expect(metadata.tags, ['pkms']);
      expect(metadata.dates.single['date'], '2026-07-13');
      expect(metadata.attachments.single['path'], 'assets/manual.pdf');
      expect(metadata.tasks.single['id'], 'task-1');

      final embeddedIndex = await scanVaultStorage(
        vault.storage,
        inspector: inspector,
        force: true,
      );
      final cliIndex = await scanVaultStorage(
        vault.storage,
        inspector: CliTypstInspector(root),
        force: true,
      );
      expect(_stableIndex(embeddedIndex), _stableIndex(cliIndex));

      await vault.saveNote(
        'notes/Broken.typ',
        '''#import "/_system/tylog.typ" as tylog
#show: tylog.note.with(id: "broken", title: "Broken")
#tylog.ref-note("root")[Root]
#does-not-exist()
''',
      );
      index = await scanVaultStorage(
        vault.storage,
        inspector: inspector,
        force: true,
      );
      expect(
        index.notesByPath['projects/Root.typ']?.metadataSource,
        'typst-query',
      );
      expect(index.notesByPath['notes/Broken.typ']?.metadataSource, 'fallback');
      expect(index.backlinksByTarget['projects/Root.typ'], [
        'notes/Broken.typ',
      ]);
      expect(
        index.problems.map((problem) => problem.code),
        contains('metadata-query-failed'),
      );
    } finally {
      inspector.dispose();
    }

    final reportPath = await writeReportStorage(
      vault.storage,
      'Book',
      index,
      const ReportFilter(kinds: {'project'}),
    );
    final report = File('${root.path}/$reportPath');
    final pdf = await exportReportPdf(root, report);

    expect(
      await report.readAsString(),
      contains('#include "/projects/Root.typ"'),
    );
    expect(await pdf.length(), greaterThan(100));
    expect(String.fromCharCodes((await pdf.readAsBytes()).take(4)), '%PDF');
  });
}

List<String> _normalizedMetadata(Iterable<TypstMetadataRecord> records) {
  final normalized = records
      .where((record) => record.label.startsWith('<tylog-'))
      .map(
        (record) => jsonEncode({
          'label': record.label,
          'value': _normalizedValue(record.value),
        }),
      )
      .toList();
  normalized.sort();
  return normalized;
}

Object? _normalizedValue(Object? value) {
  if (value is List) return value.map(_normalizedValue).toList();
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return {for (final key in keys) key: _normalizedValue(value[key])};
  }
  return value;
}

Map<String, Object?> _stableIndex(VaultIndex index) {
  final json = (jsonDecode(jsonEncode(index.toJson())) as Map)
      .cast<String, Object?>();
  for (final note in (json['notes'] as List).cast<Map>()) {
    note.remove('fingerprint');
    note.remove('modifiedMillis');
  }
  return json;
}
