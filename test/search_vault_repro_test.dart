import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/database/note_persistence.dart';
import 'package:tylog/database/tylog_database.dart';
import 'package:tylog/scanner.dart';
import 'package:tylog/retrieval/hybrid_search.dart';
import 'package:tylog/vault_storage.dart';
import 'package:tylog_core/search_index.dart';

void main() {
  test('real copied vault screenshot keyword paths', () async {
    final root = await Directory.systemTemp.createTemp('tylog_ocr_search_');
    addTearDown(() => root.delete(recursive: true));
    final storage = LocalVaultStorage(root);
    final sample = Platform.environment['TYLOG_SEARCH_SAMPLE'];
    if (sample != null) {
      for (final file in Directory(
        sample,
      ).listSync(recursive: true).whereType<File>()) {
        final path = file.path.substring(sample.length + 1);
        await storage.writeText(path, await file.readAsString());
      }
    } else {
      await storage.writeText(
        'screenshots/2025/04/shot-7f61352333c11c52.typ',
        '#show: tylog.note.with(id: "shot-7f61352333c11c52", title: "Screenshot", kind: "screenshot")\n'
            '#image("/assets/shot.webp")\n== Description\nA concert\n== Text\nMONSANTOS',
      );
    }
    final index = await scanVaultStorage(storage, force: true);
    final search = await PkmsSearchIndex.buildStorage(storage, index);
    final db = TyLogDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    for (final note in index.notes) {
      await persistNoteSource(
        database: db,
        path: note.path,
        source: await storage.readText(note.path),
      );
    }
    for (final query in ['MONSANTOS', 'monsant']) {
      expect(await db.searchNodeIds(query), contains('shot-7f61352333c11c52'));
      expect(
        mergeKeywordResults([], search.search(query)).map((e) => e.id),
        contains('shot-7f61352333c11c52'),
      );
      expect(
        search.search(query).map((e) => e.id),
        contains('shot-7f61352333c11c52'),
      );
    }
    await db.markNodeProjectionComplete(1);
    await db.customStatement('DELETE FROM node_search_fts WHERE node_id = ?', [
      'shot-7f61352333c11c52',
    ]);
    expect(await db.nodeProjectionComplete(), isTrue);
    expect(await db.searchNodeIds('MONSANTOS'), isEmpty);
    expect(
      mergeKeywordResults([], search.search('MONSANTOS')).single.id,
      'shot-7f61352333c11c52',
    );
  });
}
