import 'dart:convert';

import 'tylog_database.dart';

typedef RevisionFileUpload =
    Future<void> Function(String path, List<int> bytes);

/// Publishes durable revision envelopes through the vault's existing file
/// sync path. A failed upload leaves its outbox row pending for the next pass.
class RevisionPublisher {
  const RevisionPublisher(this.database);

  final TyLogDatabase database;

  Future<int> publish({
    required RevisionFileUpload upload,
    int limit = 100,
  }) async {
    final pending = await database.pendingRevisionUploads(limit: limit);
    var published = 0;
    for (final item in pending) {
      final path = '_system/revisions/${item.revision.id}.json';
      final bytes = utf8.encode(
        jsonEncode({
          'revision': item.revision.toJson(),
          if (item.node case final node?) 'node': node.toJson(),
        }),
      );
      await upload(path, bytes);
      await database.acknowledgeRevisionUpload(item.revision.id);
      published++;
    }
    return published;
  }
}
