import 'package:tylog_core/storage.dart';

import 'portable_merge.dart';
import 'portable_snapshot.dart';
import 'tylog_database.dart';

class PortableImportReport {
  const PortableImportReport(this.plan);

  final PortableMergePlan plan;

  int get insertedRows => plan.rows
      .where((decision) => decision.kind == PortableMergeKind.insert)
      .length;
  int get unchangedRows => plan.rows
      .where((decision) => decision.kind == PortableMergeKind.unchanged)
      .length;
  int get insertedFiles => plan.attachments
      .where((decision) => decision.kind == PortableMergeKind.insert)
      .length;
  int get unchangedFiles => plan.attachments
      .where((decision) => decision.kind == PortableMergeKind.unchanged)
      .length;
  bool get hasConflicts =>
      plan.conflicts.isNotEmpty || plan.attachmentConflicts.isNotEmpty;
}

/// Validates and restores one logical snapshot without overwriting local data.
/// Any conflict makes the whole operation a no-op and retains both payloads in
/// the returned plan.
Future<PortableImportReport> importPortableSnapshot({
  required TyLogDatabase database,
  required VaultStorage storage,
  required List<int> bytes,
}) async {
  final snapshot = parsePortableSnapshot(bytes);
  if (snapshot.schemaVersion != database.schemaVersion) {
    throw FormatException(
      'Unsupported portable database schema ${snapshot.schemaVersion}',
    );
  }

  final incomingRows = _snapshotRows(snapshot);
  final localRows = <PortableRow>[
    for (final row in await database.select(database.sourceVersions).get())
      PortableRow(table: 'source_versions', id: row.id, value: row.toJson()),
    for (final row in await database.select(database.annotations).get())
      PortableRow(table: 'annotations', id: row.id, value: row.toJson()),
    for (final row in await database.select(database.sources).get())
      PortableRow(table: 'sources', id: row.id, value: row.toJson()),
    for (final row in await database.select(database.nodes).get())
      PortableRow(table: 'nodes', id: row.id, value: row.toJson()),
    for (final row in await database.select(database.edges).get())
      PortableRow(table: 'edges', id: row.id, value: row.toJson()),
    for (final row in await database.select(database.revisions).get())
      PortableRow(table: 'revisions', id: row.id, value: row.toJson()),
  ];
  final localFiles = <PortableAttachment>[];
  for (final entry in snapshot.vaultFiles.entries) {
    if (await storage.exists(entry.key)) {
      localFiles.add(
        PortableAttachment(
          path: entry.key,
          bytes: await storage.readBytes(entry.key),
        ),
      );
    }
  }
  final plan = planPortableMerge(
    localRows: localRows,
    incomingRows: incomingRows,
    localAttachments: localFiles,
    incomingAttachments: [
      for (final entry in snapshot.vaultFiles.entries)
        PortableAttachment(path: entry.key, bytes: entry.value),
    ],
  );
  final report = PortableImportReport(plan);
  if (report.hasConflicts) return report;

  _validateReferences(snapshot, localRows);
  final createdFiles = <String>[];
  try {
    await database.transaction(() async {
      await _insertRows(database, plan.rows, {
        for (final row in localRows.where((row) => row.table == 'revisions'))
          row.id,
      });
      for (final file in plan.attachments.where(
        (decision) => decision.kind == PortableMergeKind.insert,
      )) {
        createdFiles.add(file.path);
        await storage.writeBytes(file.path, file.incoming!.bytes!);
      }
    });
  } catch (_) {
    for (final path in createdFiles.reversed) {
      await storage.delete(path);
    }
    rethrow;
  }
  return report;
}

List<PortableRow> _snapshotRows(PortableSnapshot snapshot) => [
  for (final row in snapshot.sourceVersions)
    PortableRow(table: 'source_versions', id: row['id'] as String, value: row),
  for (final row in snapshot.annotations)
    PortableRow(table: 'annotations', id: row['id'] as String, value: row),
  for (final row in snapshot.sources)
    PortableRow(table: 'sources', id: row['id'] as String, value: row),
  for (final row in snapshot.nodes)
    PortableRow(table: 'nodes', id: row['id'] as String, value: row),
  for (final row in snapshot.edges)
    PortableRow(table: 'edges', id: row['id'] as String, value: row),
  for (final row in snapshot.revisions)
    PortableRow(table: 'revisions', id: row['id'] as String, value: row),
];

void _validateReferences(PortableSnapshot snapshot, List<PortableRow> local) {
  final nodeIds = {
    for (final row in local.where((row) => row.table == 'nodes')) row.id,
    for (final row in snapshot.nodes) row['id'] as String,
  };
  for (final edge in snapshot.edges) {
    if (!nodeIds.contains(edge['fromNodeId']) ||
        !nodeIds.contains(edge['toNodeId'])) {
      throw FormatException('Edge ${edge['id']} references a missing node');
    }
  }
  final revisionIds = {
    for (final row in local.where((row) => row.table == 'revisions')) row.id,
    for (final row in snapshot.revisions) row['id'] as String,
  };
  for (final revision in snapshot.revisions) {
    final parent = revision['parentRevisionId'];
    if (parent != null && !revisionIds.contains(parent)) {
      throw FormatException(
        'Revision ${revision['id']} references a missing parent',
      );
    }
  }
}

Future<void> _insertRows(
  TyLogDatabase database,
  List<PortableMergeDecision> decisions,
  Set<String> localRevisionIds,
) async {
  final inserts = decisions
      .where((decision) => decision.kind == PortableMergeKind.insert)
      .map((decision) => decision.incoming!)
      .toList();
  for (final table in const [
    'sources',
    'source_versions',
    'annotations',
    'nodes',
    'edges',
  ]) {
    for (final row in inserts.where((row) => row.table == table)) {
      await _insertRow(database, row);
    }
  }

  final insertedRevisionIds = {
    ...localRevisionIds,
    for (final decision in decisions)
      if (decision.table == 'revisions' &&
          decision.kind == PortableMergeKind.unchanged)
        decision.id,
  };
  final pending = inserts.where((row) => row.table == 'revisions').toList();
  while (pending.isNotEmpty) {
    final ready = pending.where((row) {
      final value = row.value! as Map;
      final parent = value['parentRevisionId'];
      return parent == null || insertedRevisionIds.contains(parent);
    }).toList();
    if (ready.isEmpty) {
      throw const FormatException('Portable revision ancestry is cyclic');
    }
    for (final row in ready) {
      await _insertRow(database, row);
      insertedRevisionIds.add(row.id);
      pending.remove(row);
    }
  }
}

Future<void> _insertRow(TyLogDatabase database, PortableRow row) async {
  final value = (row.value! as Map).cast<String, dynamic>();
  switch (row.table) {
    case 'source_versions':
      await database
          .into(database.sourceVersions)
          .insert(SourceVersionData.fromJson(value));
      return;
    case 'annotations':
      await database
          .into(database.annotations)
          .insert(AnnotationData.fromJson(value));
      return;
    case 'sources':
      await database.into(database.sources).insert(SourceData.fromJson(value));
      return;
    case 'nodes':
      await database.into(database.nodes).insert(NodeData.fromJson(value));
      return;
    case 'edges':
      await database.into(database.edges).insert(EdgeData.fromJson(value));
      return;
    case 'revisions':
      await database
          .into(database.revisions)
          .insert(RevisionData.fromJson(value));
      return;
    default:
      throw FormatException('Unsupported portable table ${row.table}');
  }
}
