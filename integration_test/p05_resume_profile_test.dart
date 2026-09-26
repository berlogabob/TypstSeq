import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tylog/database/tylog_database.dart';
import 'package:tylog/pdf/pdf_extraction.dart';
import 'package:tylog/retrieval/chunking.dart';
import 'package:tylog/retrieval/embedding_jobs.dart';

const _phase = String.fromEnvironment('P05_RESUME_PHASE');
const _model = 'p05-deterministic-resume-v1';
const _batchSize = 16;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('P05 durable embedding resumes after process stop', (_) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    if (_phase != 'interrupt' && _phase != 'resume') {
      fail('P05_RESUME_PHASE must be interrupt or resume');
    }

    final support = await getApplicationSupportDirectory();
    final file = File('${support.path}/p05-resume-device.db');
    if (_phase == 'interrupt') {
      for (final path in [file.path, '${file.path}-wal', '${file.path}-shm']) {
        final candidate = File(path);
        if (await candidate.exists()) await candidate.delete();
      }
    } else if (!await file.exists()) {
      fail(
        'Interrupted-run database is missing; run the interrupt phase first',
      );
    }

    final database = await openDatabaseWithFile(file);
    var databaseOpen = true;
    try {
      if (_phase == 'interrupt') await _seed(database);
      if (_phase == 'resume') {
        final alreadyComplete = await (database.select(
          database.chunks,
        )..where((chunk) => chunk.embedding.isNotNull())).get();
        expect(alreadyComplete.length, _batchSize);
      }

      if (_phase == 'interrupt') {
        final result = await runEmbeddingBatch(
          database: database,
          model: _model,
          limit: _batchSize,
          embed: _deterministicEmbed,
        );
        expect(result.completed, _batchSize);
        expect(result.failed, 0);
        expect((await database.pendingChunks()).length, greaterThan(0));
        // The test process exits after this phase. The coordinator force-stops
        // the app before the resume phase starts in a fresh instrumentation run.
        // ignore: avoid_print
        print('P05_RESUME_CHECKPOINT complete=${result.completed}');
        return;
      }

      while ((await database.pendingChunks(limit: 1)).isNotEmpty) {
        final result = await runEmbeddingBatch(
          database: database,
          model: _model,
          limit: _batchSize,
          embed: _deterministicEmbed,
        );
        if (result.completed == 0) fail('Resume made no progress');
      }

      final resumedHash = await _resultHash(database);
      await database.close();
      databaseOpen = false;
      final baseline = TyLogDatabase(NativeDatabase.memory());
      try {
        await _seed(baseline);
        while ((await baseline.pendingChunks(limit: 1)).isNotEmpty) {
          final result = await runEmbeddingBatch(
            database: baseline,
            model: _model,
            limit: _batchSize,
            embed: _deterministicEmbed,
          );
          if (result.completed == 0) fail('Baseline made no progress');
        }
        final baselineHash = await _resultHash(baseline);
        expect(resumedHash, baselineHash);
        // Aggregate-only report, with no document text or embedding bytes.
        // ignore: avoid_print
        print('P05_RESUME_RESULT count=128 sha256=$resumedHash match=true');
      } finally {
        await baseline.close();
      }
    } finally {
      if (databaseOpen) await database.close();
    }
  });
}

Future<void> _seed(TyLogDatabase database) async {
  final text = List.filled(128, 'x').join();
  await database
      .into(database.sources)
      .insert(
        SourcesCompanion.insert(
          id: 'p05-resume-source',
          kind: 'pdf',
          title: const Value('Synthetic resume fixture'),
          locator: const Value('synthetic fixture'),
          createdAtMs: 1,
          updatedAtMs: 1,
        ),
      );
  await database.savePdfExtraction(
    sourceId: 'p05-resume-source',
    extraction: versionPdfText(
      sourceVersionId: 'p05-resume-version',
      bytes: '%PDF-1.7'.codeUnits,
      pageTexts: [text],
    ),
    createdAtMs: 2,
  );
  await database.saveChunks(
    chunkText(
      sourceVersionId: 'p05-resume-version',
      text: text,
      targetLength: 1,
      overlap: 0,
    ),
  );
  final chunks = await database.pendingChunks(limit: 1000);
  if (chunks.length != 128) {
    throw StateError('Expected 128 deterministic chunks, got ${chunks.length}');
  }
}

Future<List<int>> _deterministicEmbed(String text) async =>
    sha256.convert(utf8.encode(text)).bytes;

Future<String> _resultHash(TyLogDatabase database) async {
  final chunks = await (database.select(
    database.chunks,
  )..orderBy([(chunk) => OrderingTerm.asc(chunk.id)])).get();
  if (chunks.length != 128 || chunks.any((chunk) => chunk.embedding == null)) {
    throw StateError('Expected 128 completed vectors');
  }
  final bytes = BytesBuilder(copy: false);
  for (final chunk in chunks) {
    bytes
      ..add(utf8.encode(chunk.id))
      ..addByte(0)
      ..add(chunk.embedding!);
  }
  return sha256.convert(bytes.takeBytes()).toString();
}
