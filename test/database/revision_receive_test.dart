import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/database/note_persistence.dart';
import 'package:tylog/database/tylog_database.dart';

void main() {
  test(
    'receive applies, deduplicates, and rejects divergent revisions',
    () async {
      final database = TyLogDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final first = await persistNoteSource(
        database: database,
        path: 'notes/a.typ',
        source: '#show: tylog.note.with(id: "a", title: "A")\nfirst',
        updatedAtMs: 1,
      );
      final incomingNode = first.node.copyWith(
        content: '#show: tylog.note.with(id: "a", title: "A")\nsecond',
        updatedAtMs: 2,
      );
      final incoming = RevisionData(
        id: 'remote-2',
        entityKind: 'node',
        entityId: 'a',
        parentRevisionId: first.revision.id,
        payloadJson: jsonEncode({'content': incomingNode.content}),
        createdAtMs: 2,
      );

      expect(
        await database.receiveRevision(node: incomingNode, revision: incoming),
        RevisionReceiveResult.applied,
      );
      expect(
        await database.receiveRevision(node: incomingNode, revision: incoming),
        RevisionReceiveResult.duplicate,
      );
      expect(await database.select(database.outboxEntries).get(), hasLength(1));

      final divergent = incoming.copyWith(
        id: 'remote-3',
        parentRevisionId: const Value('missing-parent'),
      );
      expect(
        await database.receiveRevision(node: incomingNode, revision: divergent),
        RevisionReceiveResult.conflict,
      );
      expect(await database.select(database.revisions).get(), hasLength(2));
    },
  );
}
