import 'dart:convert';

import 'tylog_database.dart';

typedef RevisionFileUpload =
    Future<void> Function(String path, List<int> bytes);

typedef RevisionEnvelope = ({
  RevisionData revision,
  NodeData? node,
  AnnotationData? annotation,
});

/// Publishes durable revision envelopes through the vault's existing file
/// sync path. A failed upload leaves its outbox row pending for the next pass.
class RevisionPublisher {
  const RevisionPublisher(this.database);

  final TyLogDatabase database;

  static RevisionEnvelope decodeEnvelope(List<int> bytes) {
    final json = (jsonDecode(utf8.decode(bytes)) as Map)
        .cast<String, Object?>();
    final revision = RevisionData.fromJson(
      (json['revision'] as Map).cast<String, Object?>(),
    );
    final nodeJson = json['node'];
    final annotationJson = json['annotation'];
    return (
      revision: revision,
      node: nodeJson == null
          ? null
          : NodeData.fromJson((nodeJson as Map).cast<String, Object?>()),
      annotation: annotationJson == null
          ? null
          : AnnotationData.fromJson(
              (annotationJson as Map).cast<String, Object?>(),
            ),
    );
  }

  Future<List<String>> materialize({
    required RevisionFileUpload write,
    int limit = 100,
  }) async {
    final ids = <String>[];
    final pending = await database.pendingRevisionUploads(limit: limit);
    for (final item in pending) {
      final path = '_system/revisions/${item.revision.id}.json';
      final bytes = utf8.encode(
        jsonEncode({
          'revision': item.revision.toJson(),
          if (item.node case final node?) 'node': node.toJson(),
          if (item.annotation case final annotation?)
            'annotation': annotation.toJson(),
        }),
      );
      await write(path, bytes);
      ids.add(item.revision.id);
    }
    return ids;
  }

  Future<void> acknowledge(Iterable<String> revisionIds) async {
    for (final id in revisionIds) {
      await database.acknowledgeRevisionUpload(id);
    }
  }

  Future<int> publish({
    required RevisionFileUpload upload,
    int limit = 100,
  }) async {
    final ids = await materialize(write: upload, limit: limit);
    await acknowledge(ids);
    return ids.length;
  }
}
