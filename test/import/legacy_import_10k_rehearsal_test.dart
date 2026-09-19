import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/database/tylog_database.dart';
import 'package:tylog/import/legacy_import_plan.dart';
import 'package:tylog/import/legacy_import_runner.dart';
import 'package:tylog_core/storage.dart';

class _TenKStorage extends VaultStorage {
  _TenKStorage(this.files);

  final Map<String, Uint8List> files;

  @override
  Future<bool> exists(String path) async => files.containsKey(path);

  @override
  Future<void> createDirectory(String path) async {}

  @override
  Future<List<VaultStorageEntry>> list({
    String path = '',
    bool recursive = false,
  }) async => [
    for (final entry in files.entries)
      VaultStorageEntry(
        path: entry.key,
        isDirectory: false,
        size: entry.value.length,
      ),
  ];

  @override
  Future<VaultStorageEntry?> stat(String path) async => null;

  @override
  Future<Uint8List> readBytes(String path) async => files[path]!;

  @override
  Future<void> writeBytes(String path, List<int> bytes) async {}

  @override
  Future<void> delete(String path) async {}

  @override
  Future<String> hash(String path) async =>
      sha256.convert(files[path]!).toString();
}

void main() {
  test(
    '10k resumable import rehearsal accounts every row and measures validation',
    () async {
      final files = <String, Uint8List>{
        for (var i = 0; i < 10000; i++)
          'pages/n$i.md': Uint8List.fromList(utf8.encode('note-$i')),
      };
      final storage = _TenKStorage(files);
      final manifest = await buildLegacyImportManifest(
        storage,
        LegacyImportDialect.logseq,
      );
      expect(manifest.entries, hasLength(10000));
      expect(
        (await buildLegacyImportManifest(
          storage,
          LegacyImportDialect.logseq,
        )).fingerprint,
        manifest.fingerprint,
      );

      final dir = await Directory.systemTemp.createTemp('tylog_p09d4_');
      final db = await openDatabaseWithFile(File('${dir.path}/db'));
      addTearDown(() async {
        await db.close();
        await dir.delete(recursive: true);
      });
      const jobId = 'p09d4-job';
      await db.createOrResumeImportJob(
        ImportJobData(
          id: jobId,
          sourceKind: 'logseq',
          sourceFingerprint: manifest.fingerprint,
          status: 'running',
          totalCount: manifest.entries.length,
          completedCount: 0,
          createdAtMs: 1,
          updatedAtMs: 1,
          errorJson: '{}',
        ),
        [
          for (final entry in manifest.entries)
            ImportItemData(
              jobId: jobId,
              sourcePath: entry.path,
              sourceSha256: null,
              state: 'pending',
              targetNodeId: null,
              targetPath: null,
              errorJson: '{}',
              updatedAtMs: 1,
            ),
        ],
      );

      var materializations = 0;
      var interruptions = 0;
      var validation = Duration.zero;
      final total = Stopwatch()..start();
      while ((await db.pendingImportItems(jobId, limit: 1)).isNotEmpty) {
        final validationWatch = Stopwatch()..start();
        await (db.select(
          db.importJobs,
        )..where((job) => job.id.equals(jobId))).getSingle();
        await (db.select(
          db.importItems,
        )..where((item) => item.jobId.equals(jobId))).get();
        await db.pendingImportItems(jobId, limit: 100);
        validation += validationWatch.elapsed;

        final runner = LegacyImportRunner(
          database: db,
          storage: storage,
          manifest: manifest,
          converter: (entry, source, hash) async => (
            node: NodeData(
              id: 'node-${entry.path}',
              type: 'note',
              title: entry.path,
              content: source,
              attributesJson: '{}',
              createdAtMs: 1,
              updatedAtMs: 1,
            ),
            revision: RevisionData(
              id: 'revision-${entry.path}',
              entityKind: 'node',
              entityId: 'node-${entry.path}',
              payloadJson: '{}',
              createdAtMs: 1,
            ),
            targetPath: '${entry.path}.typ',
          ),
          materializer: (_, _, _) async {
            materializations++;
            if (materializations % 997 == 0) {
              interruptions++;
              throw StateError('synthetic interruption');
            }
          },
        );
        try {
          await runner.runBatch(jobId, batchSize: 100);
        } on StateError catch (error) {
          expect(error.message, 'synthetic interruption');
        }
      }
      total.stop();

      final items = await db.select(db.importItems).get();
      final nodes = await db.select(db.nodes).get();
      final revisions = await db.select(db.revisions).get();
      expect(items, hasLength(10000));
      expect(items.where((item) => item.state == 'written'), hasLength(10000));
      expect(nodes, hasLength(10000));
      expect(revisions, hasLength(10000));
      expect({for (final node in nodes) node.id}, hasLength(10000));
      expect({for (final revision in revisions) revision.id}, hasLength(10000));
      final aggregate = sha256
          .convert(
            utf8.encode(
              (nodes..sort((a, b) => a.id.compareTo(b.id)))
                  .map((node) => '${node.id}\n${node.content}')
                  .join('\n'),
            ),
          )
          .toString();
      expect(
        aggregate,
        'c0f2e8832e81045e7e8777dc60c95f5a1aa85fc37ad82ccf8a388af39273eee5',
      );
      stderr.writeln(
        'P09D4 notes=10000 interruptions=$interruptions '
        'total_ms=${total.elapsedMilliseconds} '
        'validation_ms=${validation.inMilliseconds} '
        'validation_pct=${(validation.inMicroseconds / total.elapsedMicroseconds * 100).toStringAsFixed(1)} '
        'aggregate=$aggregate',
      );
    },
    skip: Platform.environment['TYLOG_RUN_P09D4'] != '1',
  );
}
