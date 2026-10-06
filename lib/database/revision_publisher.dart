import 'dart:convert';

import 'note_persistence.dart';
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

  static NodeData? _nodeAtRevision(NodeData? node, RevisionData revision) {
    if (node == null || !revision.id.startsWith('note-')) return node;
    final payload = jsonDecode(revision.payloadJson) as Map;
    final attributes = payload['attributesJson'] as String;
    final metadata = jsonDecode(attributes) as Map;
    return node.copyWith(
      content: payload['content'] as String,
      attributesJson: attributes,
      title: metadata['title'] as String,
      type: metadata['kind'] as String,
      updatedAtMs: revision.createdAtMs,
    );
  }

  /// Older single-revision envelopes still decode unchanged. Coalesced files
  /// carry the immutable parent chain so a receiver can apply every revision.
  static Iterable<RevisionEnvelope> decodeEnvelopes(List<int> bytes) sync* {
    final latest = decodeEnvelope(bytes);
    final json = jsonDecode(utf8.decode(bytes)) as Map;
    for (final row in (json['history'] as List? ?? const [])) {
      final revision = RevisionData.fromJson(
        (row as Map).cast<String, Object?>(),
      );
      yield (
        revision: revision,
        node: _nodeAtRevision(latest.node, revision),
        annotation: latest.annotation,
      );
    }
    yield latest;
  }

  Future<List<String>> materialize({
    required RevisionFileUpload write,
    int limit = 100,
  }) async {
    final ids = <String>[];
    final pending = await database.pendingRevisionUploads(limit: limit);
    final written = <String>{};
    for (final item in pending) {
      ids.add(item.revision.id);
      final session = await noteRevisionEnvelope(database, item.revision);
      final envelopeId = session.first.id;
      if (!written.add(envelopeId)) continue;
      final latest = session.last;
      final path = '_system/revisions/$envelopeId.json';
      final bytes = utf8.encode(
        jsonEncode({
          'revision': latest.toJson(),
          if (session.length > 1)
            'history': session
                .take(session.length - 1)
                .map((r) => r.toJson())
                .toList(),
          if (item.node case final node?)
            'node': _nodeAtRevision(node, latest)!.toJson(),
          if (item.annotation case final annotation?)
            'annotation': annotation.toJson(),
        }),
      );
      await write(path, bytes);
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
