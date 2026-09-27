import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../database/tylog_database.dart';
import 'chunking.dart';

class NoteChunkSyncResult {
  const NoteChunkSyncResult({
    required this.added,
    required this.unchanged,
    required this.removed,
    required this.chunks,
  });

  final int added;
  final int unchanged;
  final int removed;
  final int chunks;
}

Future<NoteChunkSyncResult> syncNoteChunks(
  TyLogDatabase db,
  Map<String, ({String title, String text})> notes,
) async {
  var added = 0;
  var unchanged = 0;
  var removed = 0;
  var chunks = 0;
  final now = DateTime.now().millisecondsSinceEpoch;
  await db.transaction(() async {
    for (final entry in notes.entries) {
      final path = entry.key;
      final note = entry.value;
      final sourceId = 'note:$path';
      final digest = sha256.convert(utf8.encode(note.text)).toString();
      final versionId = '$sourceId:$digest';
      final source = await (db.select(
        db.sources,
      )..where((row) => row.id.equals(sourceId))).getSingleOrNull();
      if (source == null) {
        await db
            .into(db.sources)
            .insert(
              SourcesCompanion.insert(
                id: sourceId,
                kind: 'note',
                title: Value(note.title),
                locator: Value(path),
                createdAtMs: now,
                updatedAtMs: now,
              ),
            );
      } else if (source.title != note.title) {
        // Unchanged notes must not write: an idle resync is a no-op.
        await (db.update(
          db.sources,
        )..where((row) => row.id.equals(sourceId))).write(
          SourcesCompanion(title: Value(note.title), updatedAtMs: Value(now)),
        );
      }
      final existing = await (db.select(
        db.sourceVersions,
      )..where((row) => row.id.equals(versionId))).getSingleOrNull();
      if (existing != null) {
        unchanged++;
        continue;
      }
      await db
          .into(db.sourceVersions)
          .insert(
            SourceVersionsCompanion.insert(
              id: versionId,
              sourceId: sourceId,
              sha256: digest,
              status: 'extracted',
              pagesJson: '[]',
              createdAtMs: now,
            ),
          );
      final noteChunks = chunkText(sourceVersionId: versionId, text: note.text);
      await db.batch(
        (batch) => batch.insertAll(
          db.chunks,
          noteChunks
              .map(
                (chunk) => ChunksCompanion.insert(
                  id: chunk.id,
                  sourceVersionId: chunk.sourceVersionId,
                  startOffset: chunk.start,
                  endOffset: chunk.end,
                  content: chunk.text,
                  sha256: chunk.sha256,
                ),
              )
              .toList(),
        ),
      );
      await _deleteVersions(
        db,
        (row) => row.sourceId.equals(sourceId) & row.id.isNotIn([versionId]),
      );
      added++;
      chunks += noteChunks.length;
    }
    final existingNotes = await (db.select(
      db.sources,
    )..where((row) => row.kind.equals('note'))).get();
    for (final source in existingNotes) {
      if (!notes.containsKey(source.locator)) {
        await _deleteVersions(db, (row) => row.sourceId.equals(source.id));
        await (db.delete(
          db.sources,
        )..where((row) => row.id.equals(source.id))).go();
        removed++;
      }
    }
  });
  return NoteChunkSyncResult(
    added: added,
    unchanged: unchanged,
    removed: removed,
    chunks: chunks,
  );
}

/// Deletes matching source versions and their chunks explicitly, so stale text
/// cannot be retrieved even on a connection without foreign-key enforcement.
Future<void> _deleteVersions(
  TyLogDatabase db,
  Expression<bool> Function($SourceVersionsTable row) filter,
) async {
  final ids =
      await (db.selectOnly(db.sourceVersions)
            ..addColumns([db.sourceVersions.id])
            ..where(filter(db.sourceVersions)))
          .map((row) => row.read(db.sourceVersions.id)!)
          .get();
  if (ids.isEmpty) return;
  await (db.delete(
    db.chunks,
  )..where((row) => row.sourceVersionId.isIn(ids))).go();
  await (db.delete(db.sourceVersions)..where((row) => row.id.isIn(ids))).go();
}
