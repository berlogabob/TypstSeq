import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/database/note_persistence.dart';
import 'package:tylog/database/revision_publisher.dart';
import 'package:tylog/database/tylog_database.dart';

void main() {
  late TyLogDatabase database;
  setUp(() => database = TyLogDatabase(NativeDatabase.memory()));
  tearDown(() => database.close());

  Future<NotePersistenceResult> save(int second, {String? body}) =>
      persistNoteSource(
        database: database,
        path: 'notes/a.typ',
        source:
            '#show: tylog.note.with(id: "a", title: "A")\n${body ?? second}',
        updatedAtMs: 100000 + second * 1000,
      );

  test(
    '120 one-second saves retain minute checkpoints and latest content',
    () async {
      for (var i = 0; i < 120; i++) {
        await save(i);
      }
      final revisions = await (database.select(
        database.revisions,
      )..orderBy([(t) => OrderingTerm.asc(t.createdAtMs)])).get();
      expect(revisions.length, lessThanOrEqualTo(3));
      expect(revisions.length, greaterThanOrEqualTo(2));
      expect(revisions.first.createdAtMs, 159000);
      expect(revisions.last.createdAtMs, 219000);
      expect(revisions.last.parentRevisionId, revisions.first.id);
      expect(
        await database.select(database.outboxEntries).get(),
        hasLength(revisions.length),
      );
      expect(
        await database.select(database.derivedInvalidations).get(),
        hasLength(revisions.length),
      );
      expect(await database.searchNodeIds('119'), ['a']);
    },
  );

  test(
    'unpublished head is replaced with the same parent and new hash',
    () async {
      final first = await save(0);
      final second = await save(1);
      expect(second.revision.id, isNot(first.revision.id));
      expect(second.revision.parentRevisionId, first.revision.parentRevisionId);
      expect(await database.select(database.revisions).get(), hasLength(1));
      expect(
        jsonDecode(second.node.attributesJson)['contentHash'],
        isNot(jsonDecode(first.node.attributesJson)['contentHash']),
      );
    },
  );

  for (final fail in [false, true]) {
    test(
      'materialized head stays immutable even when upload fails=$fail',
      () async {
        final first = await save(0);
        final publisher = RevisionPublisher(database);
        final operation = publisher.publish(
          upload: (_, _) async {
            final second = await save(1);
            expect(second.revision.parentRevisionId, first.revision.id);
            if (fail) throw StateError('upload failed');
          },
        );
        if (fail) {
          await expectLater(operation, throwsStateError);
        } else {
          await operation;
        }
        expect(
          await (database.select(
            database.revisions,
          )..where((t) => t.id.equals(first.revision.id))).getSingle(),
          first.revision,
        );
      },
    );
  }

  test(
    'draft survives restart and the old immutable guard is upgraded',
    () async {
      final directory = await Directory.systemTemp.createTemp('tylog-draft-');
      addTearDown(() => directory.delete(recursive: true));
      await database.close();
      final file = File('${directory.path}/vault.db');
      database = TyLogDatabase(NativeDatabase(file));
      await save(0);
      await database.customStatement('DROP TRIGGER revisions_no_delete');
      await database.customStatement(
        "CREATE TRIGGER revisions_no_delete BEFORE DELETE ON revisions BEGIN SELECT RAISE(ABORT, 'revisions are immutable'); END",
      );
      await database.close();
      database = TyLogDatabase(NativeDatabase(file));
      await save(1);
      expect(await database.select(database.revisions).get(), hasLength(1));
      await RevisionPublisher(database).publish(upload: (_, _) async {});
      await database.close();
      database = TyLogDatabase(NativeDatabase(file));
      await save(2);
      expect(await database.select(database.revisions).get(), hasLength(2));
    },
  );

  test('a head referenced by another revision is never replaced', () async {
    final first = await save(0);
    await database.commitNodeEdit(
      node: first.node,
      revision: first.revision.copyWith(
        id: 'branch',
        parentRevisionId: Value(first.revision.id),
        createdAtMs: 1,
      ),
    );
    final next = await save(1);
    expect(next.revision.parentRevisionId, first.revision.id);
    expect(await database.select(database.revisions).get(), hasLength(3));
  });

  test('received head is never replaced', () async {
    final donor = TyLogDatabase(NativeDatabase.memory());
    addTearDown(donor.close);
    final remote = await persistNoteSource(
      database: donor,
      path: 'notes/a.typ',
      source: '#show: tylog.note.with(id: "a", title: "A")\nremote',
      updatedAtMs: 100000,
    );
    expect(
      await database.receiveRevision(
        node: remote.node,
        revision: remote.revision,
      ),
      RevisionReceiveResult.applied,
    );
    final local = await save(1);
    expect(local.revision.parentRevisionId, remote.revision.id);
    expect(await database.select(database.revisions).get(), hasLength(2));
  });

  test(
    'head used as a rejected incoming conflict base is never replaced',
    () async {
      final first = await save(0);
      final local = await save(60);
      final divergent = first.revision.copyWith(
        id: 'remote-branch',
        parentRevisionId: Value(first.revision.id),
        createdAtMs: 161000,
      );
      expect(
        await database.receiveRevision(node: first.node, revision: divergent),
        RevisionReceiveResult.conflict,
      );
      final next = await save(61);
      expect(next.revision.parentRevisionId, local.revision.id);
      expect(
        await (database.select(
          database.revisions,
        )..where((t) => t.id.equals(local.revision.id))).getSingle(),
        local.revision,
      );
    },
  );

  test(
    'existing reader accepts coalesced envelope and receives the whole chain',
    () async {
      for (var i = 0; i < 120; i++) {
        await save(i);
      }
      final receiver = TyLogDatabase(NativeDatabase.memory());
      addTearDown(receiver.close);
      await RevisionPublisher(database).publish(
        upload: (_, bytes) async {
          expect(
            RevisionPublisher.decodeEnvelope(bytes).node!.content,
            endsWith('119'),
          );
          for (final envelope in RevisionPublisher.decodeEnvelopes(bytes)) {
            expect(
              await receiver.receiveRevision(
                node: envelope.node!,
                revision: envelope.revision,
              ),
              RevisionReceiveResult.applied,
            );
          }
        },
      );
      expect(await receiver.select(receiver.revisions).get(), hasLength(2));
      final restored = await save(120, body: '59');
      expect(restored.node.content, endsWith('59'));
      expect(await database.select(database.revisions).get(), hasLength(3));
    },
  );
}
