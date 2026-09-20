import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/database/note_persistence.dart';
import 'package:tylog/database/tylog_database.dart';

void main() {
  test('revision upload stays pending until acknowledged', () async {
    final database = TyLogDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final saved = await persistNoteSource(
      database: database,
      path: 'notes/upload.typ',
      source: '#show: tylog.note.with(id: "upload", title: "Upload")\nbody',
      updatedAtMs: 1,
    );

    final pending = await database.pendingRevisionUploads();
    expect(pending, hasLength(1));
    expect(pending.single.revision.id, saved.revision.id);
    expect(pending.single.node?.content, contains('body'));

    // A failed network attempt performs no acknowledgement, so retry sees it.
    expect(await database.pendingRevisionUploads(), hasLength(1));
    await database.acknowledgeRevisionUpload(saved.revision.id);
    expect(await database.pendingRevisionUploads(), isEmpty);
  });
}
