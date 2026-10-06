import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/database/note_persistence.dart';
import 'package:tylog/database/revision_publisher.dart';
import 'package:tylog/database/tylog_database.dart';

void main() {
  test(
    'offline session grouping survives database reopen and upload retry',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'tylog-session-reopen-',
      );
      addTearDown(() => root.delete(recursive: true));
      final file = File('${root.path}/vault.sqlite');
      var database = TyLogDatabase(NativeDatabase(file));
      for (var i = 0; i < 20; i++) {
        await persistNoteSource(
          database: database,
          path: 'notes/a.typ',
          source: '#show: tylog.note.with(id: "a", title: "A")\n$i',
          updatedAtMs: i + 1,
        );
      }
      await database.close();
      database = TyLogDatabase(NativeDatabase(file));
      addTearDown(database.close);
      var attempts = 0;
      await expectLater(
        RevisionPublisher(database).publish(
          upload: (_, _) async {
            attempts++;
            throw StateError('offline');
          },
        ),
        throwsStateError,
      );
      expect(attempts, 1);
      expect(await database.pendingRevisionUploads(), hasLength(20));
      final files = <String, List<int>>{};
      await RevisionPublisher(
        database,
      ).publish(upload: (path, bytes) async => files[path] = bytes);
      expect(files, hasLength(1));
      expect(
        RevisionPublisher.decodeEnvelopes(files.values.single),
        hasLength(20),
      );
      expect(await database.pendingRevisionUploads(), isEmpty);
    },
  );

  test(
    'session gaps and peer edits start envelopes without changing IDs',
    () async {
      final database = TyLogDatabase(NativeDatabase.memory());
      final peer = TyLogDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      addTearDown(peer.close);
      Future<NotePersistenceResult> save(
        TyLogDatabase db,
        String text,
        int time,
      ) => persistNoteSource(
        database: db,
        path: 'notes/a.typ',
        source: '#show: tylog.note.with(id: "a", title: "A")\n$text',
        updatedAtMs: time,
      );
      final first = await save(database, 'first', 1);
      await save(database, 'second', 2);
      final files = <String, List<int>>{};
      await RevisionPublisher(
        database,
      ).publish(upload: (path, bytes) async => files[path] = bytes);
      expect(files.keys, ['_system/revisions/${first.revision.id}.json']);
      for (final envelope in RevisionPublisher.decodeEnvelopes(
        files.values.single,
      )) {
        expect(
          await peer.receiveRevision(
            node: envelope.node!,
            revision: envelope.revision,
          ),
          RevisionReceiveResult.applied,
        );
      }
      expect(
        (await peer.select(peer.nodes).get()).single.content,
        endsWith('second'),
      );
      final third = await save(peer, 'peer', 3);
      final peerFiles = <String, List<int>>{};
      await RevisionPublisher(
        peer,
      ).publish(upload: (path, bytes) async => peerFiles[path] = bytes);
      expect(peerFiles.keys, ['_system/revisions/${third.revision.id}.json']);
      final incoming = RevisionPublisher.decodeEnvelope(
        peerFiles.values.single,
      );
      expect(
        await database.receiveRevision(
          node: incoming.node!,
          revision: incoming.revision,
        ),
        RevisionReceiveResult.applied,
      );
      final afterPeer = await save(database, 'after peer', 4);
      await RevisionPublisher(
        database,
      ).publish(upload: (path, bytes) async => files[path] = bytes);
      expect(files, hasLength(2));
      expect(
        files,
        contains('_system/revisions/${afterPeer.revision.id}.json'),
      );
      final afterGap = await save(database, 'after gap', 600004);
      await RevisionPublisher(
        database,
      ).publish(upload: (path, bytes) async => files[path] = bytes);
      expect(files, hasLength(3));
      expect(files, contains('_system/revisions/${afterGap.revision.id}.json'));
    },
  );

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

  test('materialize can be decoded before acknowledgement', () async {
    final database = TyLogDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final saved = await persistNoteSource(
      database: database,
      path: 'notes/a.typ',
      source: '#show: tylog.note.with(id: "a", title: "A")\nbody',
      updatedAtMs: 1,
    );
    late List<int> bytes;
    final ids = await RevisionPublisher(
      database,
    ).materialize(write: (_, value) async => bytes = value);
    expect(ids, [saved.revision.id]);
    expect(await database.pendingRevisionUploads(), hasLength(1));
    expect(
      RevisionPublisher.decodeEnvelope(bytes).revision.id,
      saved.revision.id,
    );
  });
}
