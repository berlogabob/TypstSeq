import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/database/note_persistence.dart';
import 'package:tylog/database/tylog_database.dart';
import 'package:tylog/retrieval/semantic_model.dart';
import 'package:tylog/retrieval/semantic_search_controller.dart';

List<int> _vector(double x, double y) =>
    Float32List.fromList([x, y]).buffer.asUint8List().toList(growable: false);

void main() {
  test('not-installed models do not produce vector results', () async {
    final db = TyLogDatabase(NativeDatabase.memory());
    final root = await Directory.systemTemp.createTemp('semantic-test-');
    addTearDown(() async {
      await db.close();
      await root.delete(recursive: true);
    });
    final store = SemanticModelStore(
      root,
      manifest: const [
        SemanticModelFile('model_O4.onnx', 1, 'x'),
        SemanticModelFile('tokenizer.json', 1, 'y'),
      ],
    );
    final controller = SemanticSearchController(
      db: db,
      modelRoot: root,
      modelStore: store,
      passageEmbedderFactory: (_, _) =>
          (_) async => _vector(1, 0),
      queryEmbedderFactory: (_, _) =>
          (_) async => _vector(1, 0),
    );
    addTearDown(controller.dispose);
    await controller.init();
    expect(controller.ready, isFalse);
    expect(await controller.searchNotes('anything'), isEmpty);
  });

  test('indexes notes and maps vector hits to their paths', () async {
    final db = TyLogDatabase(NativeDatabase.memory());
    final root = await Directory.systemTemp.createTemp('semantic-test-');
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
    final controller = SemanticSearchController(
      db: db,
      modelRoot: root,
      modelStore: store,
      passageEmbedderFactory: (_, _) =>
          (text) async => _vector(text.contains('alpha') ? 1 : 0, 0),
      queryEmbedderFactory: (_, _) =>
          (_) async => _vector(1, 0),
    );
    addTearDown(controller.dispose);
    await controller.init();
    await controller.refreshNotes();
    expect(controller.ready, isTrue);
    expect(
      (await controller.searchNotes('alpha')).single.id,
      'notes/alpha.typ',
    );
  });

  test('resync reads only changed notes and drops deleted ones', () async {
    final db = TyLogDatabase(NativeDatabase.memory());
    final root = await Directory.systemTemp.createTemp('semantic-test-');
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
    for (final name in ['alpha', 'beta']) {
      await persistNoteSource(
        database: db,
        path: 'notes/$name.typ',
        source: '#show: tylog.note.with(id: "$name", title: "$name")\n$name',
        updatedAtMs: 1,
      );
    }
    final embedded = <String>[];
    final controller = SemanticSearchController(
      db: db,
      modelRoot: root,
      modelStore: store,
      passageEmbedderFactory: (_, _) => (text) async {
        embedded.add(text);
        return _vector(1, 0);
      },
      queryEmbedderFactory: (_, _) =>
          (_) async => _vector(1, 0),
    );
    addTearDown(controller.dispose);
    await controller.init();
    await controller.refreshNotes();
    expect(embedded, hasLength(2));

    embedded.clear();
    await controller.refreshNotes(); // nothing changed
    expect(embedded, isEmpty);

    await persistNoteSource(
      database: db,
      path: 'notes/alpha.typ',
      source: '#show: tylog.note.with(id: "alpha", title: "alpha")\nalpha v2',
      updatedAtMs: 2,
    );
    await controller.refreshNotes();
    expect(embedded.single, contains('alpha v2'));

    await db.customStatement(
      "DELETE FROM nodes WHERE json_extract(attributes_json, '\$.path') = 'notes/beta.typ'",
    );
    await controller.refreshNotes();
    final paths = (await controller.searchNotes('q')).map((hit) => hit.id);
    expect(paths, ['notes/alpha.typ']);
  });
}
