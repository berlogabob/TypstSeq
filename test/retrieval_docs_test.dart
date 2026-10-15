import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/database/note_persistence.dart';
import 'package:tylog/database/tylog_database.dart';
import 'package:tylog/retrieval/note_chunk_sync.dart';
import 'package:tylog/retrieval/semantic_model.dart';
import 'package:tylog/retrieval/semantic_search_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled docs embed once, are searchable, and never delete notes', () async {
    final db = TyLogDatabase(NativeDatabase.memory());
    final root = await Directory.systemTemp.createTemp('docs-retrieval-');
    addTearDown(() async {
      await db.close();
      await root.delete(recursive: true);
    });
    await File('${root.path}/model_O4.onnx').writeAsString('x');
    await File('${root.path}/tokenizer.json').writeAsString('y');
    await File('${root.path}/verified').writeAsString('verified');
    final store = SemanticModelStore(
      root,
      manifest: const [
        SemanticModelFile('model_O4.onnx', 1, 'x'),
        SemanticModelFile('tokenizer.json', 1, 'y'),
      ],
    );
    await persistNoteSource(
      database: db,
      path: 'notes/alpha.typ',
      source: '#show: tylog.note.with(id: "alpha", title: "Alpha")\nalpha',
      updatedAtMs: 1,
    );
    var embeddings = 0;
    SemanticSearchController controller() => SemanticSearchController(
      db: db,
      modelRoot: root,
      modelStore: store,
      passageEmbedderFactory: (_, _) => (text) async {
        embeddings++;
        return Float32List.fromList(
          text.startsWith('#show:') ? [0, 1] : [1, 0],
        ).buffer.asUint8List();
      },
      queryEmbedderFactory: (_, _) => (_) async =>
          Float32List.fromList([1, 0]).buffer.asUint8List(),
    );
    final first = controller();
    addTearDown(first.dispose);
    await first.init();
    await first.refreshNotes();
    expect(first.state, isA<SemanticReady>());
    final chunks = await db.select(db.chunks).get();
    expect(embeddings, chunks.length);
    expect(embeddings, greaterThan(1));
    final hits = await first.citations('TyLog format');
    expect(
      hits.where((hit) => hit.sourceKind == 'doc').map((hit) => hit.sourceId),
      containsAll([
        'doc:spec/tylog-format-v1.md',
        'doc:docs/modules/PACK-SPEC.md',
      ]),
    );
    expect(
      (await first.searchNotes('TyLog format')).map((hit) => hit.id),
      everyElement('notes/alpha.typ'),
    );
    await first.refreshNotes();
    // A new controller must also reuse the persisted content hashes/vectors.
    final second = controller();
    addTearDown(second.dispose);
    await second.init();
    await second.refreshNotes();
    expect(second.state, isA<SemanticReady>());
    expect(embeddings, chunks.length);
    expect((await db.select(db.chunks).get()).map((c) => c.id),
        chunks.map((c) => c.id));

    final edited = await syncDocChunks(db, {
      'spec/tylog-format-v1.md': (title: 'Format', text: 'changed documentation'),
    });
    expect(edited.added, 1);
    expect(edited.removed, greaterThanOrEqualTo(1));
    expect((await db.pendingChunks()).single.content, 'changed documentation');
    await syncDocChunks(db, {});
    expect((await db.select(db.sources).get()).map((s) => (s.kind, s.id)),
        [('note', 'note:notes/alpha.typ')]);
    expect((await db.select(db.chunks).get()).single.content, contains('alpha'));
  });
}
