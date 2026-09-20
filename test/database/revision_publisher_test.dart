import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/database/note_persistence.dart';
import 'package:tylog/database/revision_publisher.dart';
import 'package:tylog/database/tylog_database.dart';

void main() {
  test('failed file upload leaves the revision pending for retry', () async {
    final database = TyLogDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final saved = await persistNoteSource(
      database: database,
      path: 'notes/a.typ',
      source: '#show: tylog.note.with(id: "a", title: "A")\nbody',
      updatedAtMs: 1,
    );
    final publisher = RevisionPublisher(database);
    var attempts = 0;
    await expectLater(
      publisher.publish(
        upload: (path, bytes) async {
          attempts++;
          expect(path, '_system/revisions/${saved.revision.id}.json');
          expect(jsonDecode(utf8.decode(bytes)), contains('revision'));
          throw StateError('offline');
        },
      ),
      throwsStateError,
    );
    expect(attempts, 1);
    expect(await database.pendingRevisionUploads(), hasLength(1));
  });

  test('successful publish acknowledges each envelope', () async {
    final database = TyLogDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await persistNoteSource(
      database: database,
      path: 'notes/a.typ',
      source: '#show: tylog.note.with(id: "a", title: "A")\nbody',
      updatedAtMs: 1,
    );
    final paths = <String>[];
    final count = await RevisionPublisher(
      database,
    ).publish(upload: (path, _) async => paths.add(path));
    expect(count, 1);
    expect(paths.single, startsWith('_system/revisions/'));
    expect(await database.pendingRevisionUploads(), isEmpty);
  });
}
