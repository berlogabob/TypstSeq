import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/database/tylog_database.dart';
import 'package:tylog/retrieval/vector_retrieval.dart';

void main() {
  test('stored vector search filters model and returns stable top-k', () async {
    final database = TyLogDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database.customStatement('''
      INSERT INTO sources (id, kind, locator, created_at_ms, updated_at_ms)
      VALUES ('source', 'pdf', 'paper.pdf', 1, 1)
    ''');
    await database.customStatement('''
      INSERT INTO source_versions
        (id, source_id, sha256, status, pages_json, created_at_ms)
      VALUES ('version', 'source', 'hash', 'extracted', '[]', 2)
    ''');
    await database.customStatement(
      '''
      INSERT INTO chunks
        (id, source_version_id, start_offset, end_offset, content, sha256, status,
         embedding_model, embedding)
      VALUES
        ('a', 'version', 0, 1, 'a', 'a', 'complete', 'model-v1', ?),
        ('b', 'version', 1, 2, 'b', 'b', 'complete', 'model-v1', ?),
        ('wrong-model', 'version', 2, 3, 'c', 'c', 'complete', 'other', ?)
    ''',
      [
        [0, 0, 128, 63],
        [0, 0, 0, 63],
        [0, 0, 128, 63],
      ],
    );
    final hits = await searchStoredChunks(
      database: database,
      model: 'model-v1',
      query: const [1],
      limit: 2,
    );
    expect(hits.map((hit) => hit.id), ['a', 'b']);
    expect(
      (await database.embeddedChunkCandidates(model: 'other')).single.id,
      'wrong-model',
    );
  });
}
