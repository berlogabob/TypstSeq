import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:tylog_core/scanner.dart';
import 'package:tylog_core/storage.dart';

import 'tylog_database.dart';

// Publication grouping is device-local metadata; received revisions have no
// mapping. Keep it durable so an offline outbox still coalesces after restart.
Future<List<RevisionData>> noteRevisionEnvelope(
  TyLogDatabase database,
  RevisionData revision,
) async {
  final mapping =
      await (database.select(database.databaseMetadata)
            ..where((t) => t.key.equals('note-envelope:${revision.id}')))
          .getSingleOrNull();
  if (mapping == null) return [revision];
  final rows = await database
      .customSelect(
        'SELECT revisions.* FROM revisions JOIN database_metadata m '
        "ON m.key = 'note-envelope:' || revisions.id WHERE m.value = ? "
        'ORDER BY revisions.created_at_ms, revisions.id',
        variables: [Variable.withString(mapping.value)],
      )
      .get();
  return rows.map((row) => database.revisions.map(row.data)).toList();
}

/// The rows created by [persistNoteSource].
typedef NotePersistenceResult = ({NodeData node, RevisionData revision});

Future<String?> persistedNoteSourceForPath(
  TyLogDatabase database,
  String path,
) async {
  validateVaultPath(path);
  final row = await database
      .customSelect(
        '''
        SELECT content
        FROM nodes
        WHERE content <> ''
          AND json_extract(attributes_json, '\$.path') = ?
        LIMIT 1
        ''',
        variables: [Variable.withString(path)],
      )
      .getSingleOrNull();
  return row?.read<String>('content');
}

/// Persists one vault-relative Typst note as the current graph node.
///
/// The import table is the durable bridge from a source path to a node id. A
/// mapped id wins over the id in the note header, which lets an imported file
/// keep its identity when its header changed. Revisions are immutable and the
/// revision id is stable for a given node, parent, and source bytes, so a
/// retry after a failed transaction is safe.
Future<NotePersistenceResult> persistNoteSource({
  required TyLogDatabase database,
  required String path,
  required String source,
  int? updatedAtMs,
  String? fingerprint,
  int? modifiedMillis,
  bool deleted = false,
}) async {
  validateVaultPath(path);
  final note = scanNote(path, source, fingerprint: fingerprint);
  final content = deleted ? '' : source;
  final contentHash = sha256.convert(utf8.encode(content)).toString();
  return database.transaction(() async {
    final mapped =
        await (database.select(database.importItems)
              ..where(
                (table) =>
                    table.targetPath.equals(path) &
                    table.targetNodeId.isNotNull(),
              )
              ..orderBy([
                (table) => OrderingTerm.desc(table.updatedAtMs),
                (table) => OrderingTerm.desc(table.targetNodeId),
              ])
              ..limit(1))
            .getSingleOrNull();
    final nodeId = mapped?.targetNodeId ?? note.id;
    if (nodeId.isEmpty) {
      throw StateError('note has no stable node id: $path');
    }

    final existing = await (database.select(
      database.nodes,
    )..where((table) => table.id.equals(nodeId))).getSingleOrNull();
    final parent =
        await (database.select(database.revisions)
              ..where(
                (table) =>
                    table.entityKind.equals('node') &
                    table.entityId.equals(nodeId),
              )
              ..orderBy([
                (table) => OrderingTerm.desc(table.createdAtMs),
                (table) => OrderingTerm.desc(table.id),
              ])
              ..limit(1))
            .getSingleOrNull();
    final parentRevisionId = parent?.id;
    final requestedNow = updatedAtMs ?? DateTime.now().millisecondsSinceEpoch;
    final now = existing == null || requestedNow > existing.updatedAtMs
        ? requestedNow
        : existing.updatedAtMs + 1;
    final revisionId = _noteRevisionId(
      nodeId: nodeId,
      parentRevisionId: parentRevisionId,
      contentHash: contentHash,
    );
    final attributes = <String, Object?>{
      ...note.toJson(),
      'contentHash': contentHash,
      if (modifiedMillis case final stamp) 'modifiedMillis': stamp,
      if (deleted) 'deletedAtMs': now,
    };
    final attributesJson = jsonEncode(attributes);
    final node = NodeData(
      id: nodeId,
      type: note.kind,
      title: note.title,
      content: content,
      attributesJson: attributesJson,
      eventStartMs: null,
      eventEndMs: null,
      createdAtMs: existing?.createdAtMs ?? now,
      updatedAtMs: now,
    );
    final revision = RevisionData(
      id: revisionId,
      entityKind: 'node',
      entityId: nodeId,
      parentRevisionId: parentRevisionId,
      payloadJson: jsonEncode({
        'content': content,
        'attributesJson': attributesJson,
      }),
      createdAtMs: now,
    );
    await database.commitNodeEdit(node: node, revision: revision);
    final parentEnvelope = parent == null
        ? null
        : await (database.select(database.databaseMetadata)
                ..where((t) => t.key.equals('note-envelope:${parent.id}')))
              .getSingleOrNull();
    final continues =
        !deleted &&
        parentEnvelope != null &&
        now - parent!.createdAtMs < const Duration(minutes: 10).inMilliseconds;
    await database
        .into(database.databaseMetadata)
        .insertOnConflictUpdate(
          DatabaseMetadataData(
            key: 'note-envelope:$revisionId',
            value: continues ? parentEnvelope.value : revisionId,
            updatedAtMs: now,
          ),
        );
    return (node: node, revision: revision);
  });
}

String _noteRevisionId({
  required String nodeId,
  required String? parentRevisionId,
  required String contentHash,
}) {
  final seed = [
    nodeId,
    parentRevisionId ?? '',
    contentHash,
  ].map((part) => '${part.length}:$part').join();
  return 'note-${sha256.convert(utf8.encode(seed))}';
}
