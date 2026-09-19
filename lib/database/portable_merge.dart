import 'dart:convert';

import 'package:crypto/crypto.dart';

/// The result for one incoming row or attachment.
enum PortableMergeKind { insert, unchanged, conflict }

/// A JSON row identified by its table and stable primary-key value.
///
/// [value] must contain only JSON values. Map keys are sorted before hashing,
/// so equivalent payloads do not conflict merely because their source order
/// differs.
class PortableRow {
  const PortableRow({
    required this.table,
    required this.id,
    required this.value,
  });

  final String table;
  final String id;
  final Object? value;

  String get key => portableMergeKey(table, id);
}

/// An attachment entry from a portable snapshot.
///
/// A snapshot normally carries only [sha256]. [bytes] is optional and lets the
/// planner detect the rare case where two payloads claim the same hash but
/// contain different bytes.
class PortableAttachment {
  PortableAttachment({required this.path, String? sha256, List<int>? bytes})
    : sha256 = sha256 ?? _hashBytes(bytes),
      bytes = bytes == null ? null : List.unmodifiable(bytes);

  final String path;
  final String sha256;
  final List<int>? bytes;

  static String _hashBytes(List<int>? bytes) {
    if (bytes == null) {
      throw ArgumentError('sha256 or bytes is required');
    }
    return sha256Digest(bytes);
  }
}

class PortableMergeDecision {
  const PortableMergeDecision({
    required this.table,
    required this.id,
    required this.kind,
    required this.incomingHash,
    this.localHash,
    this.local,
    this.incoming,
    this.conflictId,
  });

  final String table;
  final String id;
  final PortableMergeKind kind;
  final String? localHash;
  final String incomingHash;
  final PortableRow? local;
  final PortableRow? incoming;
  final String? conflictId;

  String get key => portableMergeKey(table, id);
}

class PortableAttachmentDecision {
  const PortableAttachmentDecision({
    required this.path,
    required this.kind,
    required this.incomingHash,
    this.localHash,
    this.local,
    this.incoming,
    this.conflictId,
  });

  final String path;
  final PortableMergeKind kind;
  final String? localHash;
  final String incomingHash;
  final PortableAttachment? local;
  final PortableAttachment? incoming;
  final String? conflictId;
}

class PortableMergePlan {
  const PortableMergePlan({required this.rows, required this.attachments});

  final List<PortableMergeDecision> rows;
  final List<PortableAttachmentDecision> attachments;

  Iterable<PortableMergeDecision> get conflicts =>
      rows.where((decision) => decision.kind == PortableMergeKind.conflict);

  Iterable<PortableAttachmentDecision> get attachmentConflicts => attachments
      .where((decision) => decision.kind == PortableMergeKind.conflict);
}

/// Pure, deterministic comparison of an incoming snapshot with local data.
///
/// The planner only describes changes. It never writes local rows, deletes
/// data, or reads the clock.
PortableMergePlan planPortableMerge({
  required Iterable<PortableRow> localRows,
  required Iterable<PortableRow> incomingRows,
  Iterable<PortableAttachment> localAttachments = const [],
  Iterable<PortableAttachment> incomingAttachments = const [],
}) {
  final localByKey = _indexRows(localRows);
  final incomingByKey = _indexRows(incomingRows);
  final rows = <PortableMergeDecision>[];

  for (final key in incomingByKey.keys.toList()..sort()) {
    final incoming = incomingByKey[key]!;
    final local = localByKey[key];
    final incomingHash = portableCanonicalHash(incoming.value);
    final localHash = local == null ? null : portableCanonicalHash(local.value);
    if (local == null) {
      rows.add(
        PortableMergeDecision(
          table: incoming.table,
          id: incoming.id,
          kind: PortableMergeKind.insert,
          incomingHash: incomingHash,
          incoming: incoming,
        ),
      );
    } else if (localHash == incomingHash) {
      rows.add(
        PortableMergeDecision(
          table: incoming.table,
          id: incoming.id,
          kind: PortableMergeKind.unchanged,
          localHash: localHash,
          incomingHash: incomingHash,
          local: local,
          incoming: incoming,
        ),
      );
    } else {
      rows.add(
        PortableMergeDecision(
          table: incoming.table,
          id: incoming.id,
          kind: PortableMergeKind.conflict,
          localHash: localHash,
          incomingHash: incomingHash,
          local: local,
          incoming: incoming,
          conflictId: portableConflictId(
            table: incoming.table,
            id: incoming.id,
            localHash: localHash!,
            incomingHash: incomingHash,
          ),
        ),
      );
    }
  }

  final localByPath = _indexAttachments(localAttachments);
  final incomingByPath = _indexAttachments(incomingAttachments);
  final attachments = <PortableAttachmentDecision>[];
  for (final path in incomingByPath.keys.toList()..sort()) {
    final incoming = incomingByPath[path]!;
    final local = localByPath[path];
    final sameBytes =
        local == null ||
        local.bytes == null ||
        incoming.bytes == null ||
        _bytesEqual(local.bytes!, incoming.bytes!);
    final sameHash = local?.sha256 == incoming.sha256;
    final kind = local == null
        ? PortableMergeKind.insert
        : sameHash && sameBytes
        ? PortableMergeKind.unchanged
        : PortableMergeKind.conflict;
    attachments.add(
      PortableAttachmentDecision(
        path: path,
        kind: kind,
        localHash: local?.sha256,
        incomingHash: incoming.sha256,
        local: local,
        incoming: incoming,
        conflictId: kind == PortableMergeKind.conflict
            ? portableConflictId(
                table: 'attachment',
                id: path,
                localHash: local!.sha256,
                incomingHash: incoming.sha256,
              )
            : null,
      ),
    );
  }

  return PortableMergePlan(
    rows: List.unmodifiable(rows),
    attachments: List.unmodifiable(attachments),
  );
}

Map<String, PortableRow> _indexRows(Iterable<PortableRow> rows) {
  final indexed = <String, PortableRow>{};
  for (final row in rows) {
    _validateKeyPart(row.table, 'table');
    _validateKeyPart(row.id, 'id');
    if (indexed.containsKey(row.key)) {
      throw ArgumentError('duplicate portable row key: ${row.key}');
    }
    indexed[row.key] = row;
    // Validate once, before a caller starts acting on a plan.
    portableCanonicalJson(row.value);
  }
  return indexed;
}

Map<String, PortableAttachment> _indexAttachments(
  Iterable<PortableAttachment> attachments,
) {
  final indexed = <String, PortableAttachment>{};
  for (final attachment in attachments) {
    if (attachment.path.isEmpty || attachment.path.contains('\u0000')) {
      throw ArgumentError.value(
        attachment.path,
        'path',
        'must be non-empty and may not contain NUL',
      );
    }
    if (indexed.containsKey(attachment.path)) {
      throw ArgumentError(
        'duplicate portable attachment path: ${attachment.path}',
      );
    }
    indexed[attachment.path] = attachment;
    if (attachment.sha256.isEmpty) {
      throw ArgumentError.value(
        attachment.sha256,
        'sha256',
        'must be non-empty',
      );
    }
  }
  return indexed;
}

String portableMergeKey(String table, String id) {
  _validateKeyPart(table, 'table');
  _validateKeyPart(id, 'id');
  return '$table\u0000$id';
}

String portableConflictId({
  required String table,
  required String id,
  required String localHash,
  required String incomingHash,
}) {
  final seed = [
    table,
    id,
    localHash,
    incomingHash,
  ].map((part) => '${part.length}:$part').join();
  return 'portable-${sha256Digest(utf8.encode(seed))}';
}

String portableCanonicalJson(Object? value) => jsonEncode(_canonicalize(value));

String portableCanonicalHash(Object? value) =>
    sha256Digest(utf8.encode(portableCanonicalJson(value)));

String sha256Digest(List<int> bytes) => sha256.convert(bytes).toString();

Object? _canonicalize(Object? value) {
  if (value == null || value is String || value is bool) return value;
  if (value is num) {
    if (!value.isFinite) throw ArgumentError('JSON numbers must be finite');
    return value;
  }
  if (value is List) return value.map(_canonicalize).toList(growable: false);
  if (value is Map) {
    final keys = value.keys.toList();
    if (keys.any((key) => key is! String)) {
      throw ArgumentError('JSON object keys must be strings');
    }
    keys.cast<String>().sort();
    return <String, Object?>{
      for (final key in keys.cast<String>()) key: _canonicalize(value[key]),
    };
  }
  throw ArgumentError.value(value, 'value', 'must contain JSON values only');
}

void _validateKeyPart(String value, String name) {
  if (value.isEmpty || value.contains('\u0000')) {
    throw ArgumentError.value(
      value,
      name,
      'must be non-empty and may not contain NUL',
    );
  }
}

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
