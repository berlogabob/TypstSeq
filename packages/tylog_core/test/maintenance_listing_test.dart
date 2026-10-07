import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tylog_core/maintenance.dart';
import 'package:tylog_core/scanner.dart';
import 'package:tylog_core/storage.dart';
import 'package:tylog_core/vault.dart';

class _CountingStorage extends LocalVaultStorage {
  _CountingStorage(super.root);

  int recursiveListCalls = 0;

  @override
  Future<List<VaultStorageEntry>> list({
    String path = '',
    bool recursive = false,
  }) async {
    if (recursive) {
      recursiveListCalls++;
      await Future<void>.delayed(const Duration(milliseconds: 110));
    }
    return super.list(path: path, recursive: recursive);
  }

  @override
  Future<Uint8List> readBytes(String path) async {
    if (path == 'assets/a.txt') {
      await Future<void>.delayed(const Duration(milliseconds: 110));
    }
    return super.readBytes(path);
  }

  @override
  Future<void> writeBytes(String path, List<int> bytes) async {
    if (path == TylogVaultPaths.index) {
      await Future<void>.delayed(const Duration(milliseconds: 115));
    }
    return super.writeBytes(path, bytes);
  }
}

class _Inspector implements TypstInspector, BaseFilesInspector {
  @override
  Future<void> setBaseFiles(Map<String, Uint8List> files) async {
    await Future<void>.delayed(const Duration(milliseconds: 105));
  }

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

    final maintenance = VaultMaintenance(storage);
    final events = await maintenance
        .run(inspector: _Inspector(), buildSearch: false)
        .toList();
    final scanStages = Map.of(maintenance.stageMillis)
      ..remove('validate')
      ..remove('load-search')
      ..remove('build-search')
      ..remove('write-search');
    expect(
      scanStages.keys,
      containsAll([
        'list-stat',
        'dirty-markers',
        'sync-receipts',
        'load-index',
        'donor-load',
        'support-files',
        'scan',
        'index-check',
        'encode-index',
        'write-index',
        'delete-markers',
        'donor-publish',
        'other',
      ]),
    );
    expect(scanStages.values.every((ms) => ms >= 0), isTrue);
    expect(scanStages['list-stat'], greaterThanOrEqualTo(100));
    expect(scanStages['support-files'], greaterThanOrEqualTo(100));
    expect(scanStages['support-publish'], greaterThanOrEqualTo(100));
    expect(scanStages['write-index'], greaterThanOrEqualTo(100));
    expect(
      scanStages.values.fold<int>(0, (sum, ms) => sum + ms),
      events.whereType<MaintenanceIndexed>().single.durationMs,
    );

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
