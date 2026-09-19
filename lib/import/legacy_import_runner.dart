import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:tylog/database/tylog_database.dart';
import 'package:tylog/import/legacy_import_plan.dart';
import 'package:tylog_core/storage.dart';

typedef LegacyNodeConverter =
    Future<({NodeData node, RevisionData revision, String targetPath})?>
    Function(LegacyImportEntry entry, String source, String sha256);
typedef LegacyImportMaterializer =
    Future<void> Function(
      ImportItemData item,
      NodeData node,
      String targetPath,
    );

class LegacyImportRunner {
  LegacyImportRunner({
    required this.database,
    required this.storage,
    required this.manifest,
    required this.converter,
    this.materializer,
    this.shouldCancel,
  });

  final TyLogDatabase database;
  final VaultStorage storage;
  final LegacyImportManifest manifest;
  final LegacyNodeConverter converter;
  final LegacyImportMaterializer? materializer;
  final bool Function()? shouldCancel;

  Future<bool> runBatch(String jobId, {int batchSize = 50}) async {
    if (batchSize < 1) throw ArgumentError.value(batchSize, 'batchSize');
    final job = await (database.select(
      database.importJobs,
    )..where((t) => t.id.equals(jobId))).getSingle();
    if (job.sourceKind != manifest.dialect.name ||
        job.sourceFingerprint != manifest.fingerprint ||
        job.totalCount != manifest.entries.length) {
      throw StateError('import manifest does not match job');
    }
    final entries = {for (final e in manifest.entries) e.path: e};
    final stored = await (database.select(
      database.importItems,
    )..where((t) => t.jobId.equals(jobId))).get();
    if (stored.length != manifest.entries.length ||
        stored.any((item) => !entries.containsKey(item.sourcePath))) {
      throw StateError('import job contains unknown source');
    }
    var terminal = stored.where((i) => i.state != 'pending').length;
    var failed = stored.where((i) => i.state == 'failed').length;
    var pendingCount = stored.where((i) => i.state == 'pending').length;
    final pending = await database.pendingImportItems(jobId, limit: batchSize);
    for (final item in pending) {
      if (shouldCancel?.call() ?? false) break;
      final entry = entries[item.sourcePath]!;
      if (entry.kind == LegacyImportEntryKind.asset ||
          entry.kind == LegacyImportEntryKind.unsupported) {
        await _mark(
          item,
          'skipped',
          _code(
            entry.kind == LegacyImportEntryKind.asset ? 'asset' : 'unsupported',
          ),
          terminal + 1,
          pendingCount - 1,
          failed,
        );
        terminal++;
        pendingCount--;
        continue;
      }
      String? hash;
      ({NodeData node, RevisionData revision, String targetPath})? result;
      String? sourceFailure;
      try {
        final bytes = await storage.readBytes(entry.path);
        final source = utf8.decode(bytes);
        hash = sha256.convert(bytes).toString();
        result = await converter(entry, source, hash);
      } catch (_) {
        sourceFailure = _code('read-or-convert');
      }
      if (sourceFailure != null) {
        await _mark(
          item,
          'failed',
          sourceFailure,
          terminal + 1,
          pendingCount - 1,
          failed + 1,
        );
        terminal++;
        pendingCount--;
        failed++;
        continue;
      }
      if (result == null) {
        await _mark(
          item.copyWith(sourceSha256: Value(hash)),
          'skipped',
          _code('empty'),
          terminal + 1,
          pendingCount - 1,
          failed,
        );
        terminal++;
        pendingCount--;
      } else {
        final count = terminal + 1;
        final status = pendingCount - 1 == 0
            ? (failed == 0 ? 'completed' : 'failed')
            : 'running';
        final targetPath = item.targetPath ?? result.targetPath;
        final checkpoint = item.copyWith(
          sourceSha256: Value(hash!),
          targetPath: Value(targetPath),
        );
        await database.checkpointImportItem(item: checkpoint);
        if (materializer != null) {
          await materializer!(checkpoint, result.node, targetPath);
        }
        await database.commitImportedNode(
          node: result.node,
          revision: result.revision,
          item: item.copyWith(
            sourceSha256: Value(hash),
            targetNodeId: Value(result.node.id),
            state: 'written',
            targetPath: Value(targetPath),
          ),
          completedCount: count,
          status: status,
        );
        terminal++;
        pendingCount--;
      }
    }
    final remaining = await database.pendingImportItems(jobId, limit: 1);
    return remaining.isNotEmpty;
  }

  Future<void> _mark(
    ImportItemData item,
    String state,
    String code,
    int count,
    int pending,
    int failed,
  ) async {
    await database.markImportItem(
      item: item.copyWith(state: state, errorJson: jsonEncode({'code': code})),
      completedCount: count,
      status: pending == 0 ? (failed == 0 ? 'completed' : 'failed') : 'running',
    );
  }

  String _code(String value) => 'legacy-import-$value';
}
