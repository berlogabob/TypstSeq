import 'dart:io';

import 'package:test/test.dart';
import 'package:tylog_core/maintenance.dart';
import 'package:tylog_core/scanner.dart';
import 'package:tylog_core/storage.dart';

class _CountingStorage extends LocalVaultStorage {
  _CountingStorage(super.root);

  int recursiveListCalls = 0;

  @override
  Future<List<VaultStorageEntry>> list({
    String path = '',
    bool recursive = false,
  }) {
    if (recursive) recursiveListCalls++;
    return super.list(path: path, recursive: recursive);
  }
}

class _Inspector implements TypstInspector {
  @override
  Future<List<TypstMetadataRecord>> inspect(TypstDocumentInput input) async => [
    const TypstMetadataRecord(
      label: '<tylog-note>',
      value: {
        'schema': 1,
        'entity': 'note',
        'id': 'a',
        'title': 'A',
        'kind': 'note',
      },
    ),
    const TypstMetadataRecord(
      label: '<tylog-attachment>',
      value: {'schema': 1, 'entity': 'attachment', 'path': 'assets/a.txt'},
    ),
  ];
}

void main() {
  test('one recursive listing is reused by every maintenance stage', () async {
    final root = await Directory.systemTemp.createTemp(
      'tylog-maintenance-listing-',
    );
    addTearDown(() => root.delete(recursive: true));
    final storage = _CountingStorage(root);
    await storage.writeText('notes/a.typ', '= A\n');
    await storage.writeText('assets/a.txt', 'attachment');
    final orphan = File('${root.path}/orphan.123.tmp')
      ..writeAsStringSync('orphan');
    orphan.setLastModifiedSync(
      DateTime.now().subtract(const Duration(hours: 2)),
    );

    final events = await VaultMaintenance(
      storage,
    ).run(inspector: _Inspector(), buildSearch: false).toList();

    final indexed = events.whereType<MaintenanceIndexed>().single.index;
    final validation = events.whereType<MaintenanceValidated>().single.report;
    final swept = events.whereType<MaintenanceSwept>().single;
    expect(storage.recursiveListCalls, 1);
    expect(indexed.notes.map((note) => note.path), ['notes/a.typ']);
    expect(validation.count('missing-attachment'), 0);
    expect(swept.deleted, 1);
    expect(await storage.exists('orphan.123.tmp'), isFalse);
  });
}
