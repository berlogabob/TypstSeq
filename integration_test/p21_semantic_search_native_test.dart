import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:typst_flutter/src/rust/frb_generated.dart';
import 'package:tylog/app_mobile.dart';
import 'package:tylog/database/note_persistence.dart';
import 'package:tylog/database/tylog_database.dart';
import 'package:tylog/knowledge_screen.dart';
import 'package:tylog/retrieval/semantic_model.dart';
import 'package:tylog/retrieval/semantic_search_controller.dart';
import 'package:tylog/scanner.dart';
import 'package:tylog/vault.dart';
import 'package:tylog/vault_registry.dart';

import 'p21_inputs.dart';

const _modelDirEnv = 'P21_MODEL_DIR';
const _vaultDirEnv = 'P21_VAULT_ROOT';

Future<void> main() async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // The app's main() does this; the test mounts HomeScreen directly.
  setUpAll(() async {
    try {
      await RustLib.init();
    } on StateError catch (error) {
      if (!error.message.contains('twice')) rethrow;
    }
  });

  testWidgets('P21 native semantic search end to end', (tester) async {
    if (!Platform.isMacOS && !Platform.isAndroid) {
      markTestSkipped('P21 native acceptance targets macOS and Android.');
    }

    final inputs = await awaitP21Inputs();
    final modelRoot = await _prepareModel(inputs?.model);
    if (modelRoot == null) return;

    final root = await Directory.systemTemp.createTemp('tylog_p21_vault_');
    addTearDown(() => root.delete(recursive: true));
    final sourceRoot =
        inputs?.vault?.path ?? Platform.environment[_vaultDirEnv];
    if (sourceRoot == null || sourceRoot.isEmpty) {
      await _makeFixture(root);
    } else {
      await _copyDirectory(Directory(sourceRoot), root);
    }

    final vault = Vault(root);
    await vault.ensureCreated();
    var index = await scanVaultStorage(vault.storage, force: true);
    expect(index.notesByPath, isNotEmpty);

    final database = TyLogDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    for (final path in index.notesByPath.keys) {
      await persistNoteSource(
        database: database,
        path: path,
        source: await vault.storage.readText(path),
      );
    }

    final targets = index.notesByPath.keys.take(3).toList();
    expect(targets, hasLength(3));
    final queries = <String>[];
    for (final path in targets) {
      final note = index.notesByPath[path]!;
      queries.add(note.title);
    }

    final homeClosed = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          startup: () async {},
          databaseOpener: () async => database,
          databaseCloser: (value) async {
            await value.close();
            if (!homeClosed.isCompleted) homeClosed.complete();
          },
        ),
      ),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await homeClosed.future;
    });

    final dynamic home = tester.state(find.byType(HomeScreen));
    final workspace = home.workspace;

    late final SemanticSearchController controller;
    var controllerDisposed = false;
    controller = SemanticSearchController(db: database, modelRoot: modelRoot);
    addTearDown(() {
      if (!controllerDisposed) controller.dispose();
    });
    await controller.init();
    var sampling = true;
    var samplingInFlight = false;
    var lastProgressSecond = 0;
    final chunkingEndedAt = <Duration>[];
    final indexingStarted = Stopwatch()..start();
    Future<void> sampleProgress() async {
      if (!sampling || samplingInFlight) return;
      samplingInFlight = true;
      try {
        final elapsed = indexingStarted.elapsed;
        final notesSynced = await _p21Count(
          database,
          "SELECT COUNT(*) AS count FROM nodes "
          "WHERE json_extract(attributes_json, '\$.path') IS NOT NULL",
        );
        final chunksTotal = await _p21Count(
          database,
          'SELECT COUNT(*) AS count FROM chunks',
        );
        final chunksEmbedded = await _p21Count(
          database,
          "SELECT COUNT(*) AS count FROM chunks "
          "WHERE status = 'complete' AND embedding IS NOT NULL",
        );
        if (chunksTotal > 0 && chunkingEndedAt.isEmpty) {
          chunkingEndedAt.add(elapsed);
          // ignore: avoid_print
          print(
            'P21_PHASE chunking_s=${elapsed.inMicroseconds / 1000000.0}',
          );
        }
        final elapsedSeconds = elapsed.inMicroseconds / 1000000.0;
        final elapsedSecond = elapsed.inSeconds;
        if (elapsedSecond >= 30 &&
            elapsedSecond ~/ 30 > lastProgressSecond ~/ 30) {
          lastProgressSecond = elapsedSecond;
          // ignore: avoid_print
          print(
            'P21_PROGRESS '
            'elapsed_s=${elapsedSeconds.toStringAsFixed(1)} '
            'notes_synced=$notesSynced '
            'chunks_total=$chunksTotal '
            'chunks_embedded=$chunksEmbedded '
            'chunks_per_s=${(chunksEmbedded / elapsedSeconds).toStringAsFixed(2)}',
          );
        }
      } finally {
        samplingInFlight = false;
      }
    }
    final progressTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(sampleProgress()),
    );
    addTearDown(() {
      sampling = false;
      progressTimer.cancel();
    });
    final indexing = Stopwatch()..start();
    await controller.refreshNotes();
    indexing.stop();
    await sampleProgress();
    sampling = false;
    progressTimer.cancel();
    expect(controller.ready, isTrue);

    final first = Stopwatch()..start();
    final firstHits = await controller.searchNotes(queries.first, limit: 10);
    first.stop();
    expect(firstHits.map((hit) => hit.id), contains(targets.first));
    for (var i = 0; i < queries.length; i++) {
      final hits = i == 0
          ? firstHits
          : await controller.searchNotes(queries[i], limit: 10);
      expect(hits.map((hit) => hit.id), contains(targets[i]));
      expect(
        (await controller.citations(
          queries[i],
        )).map((citation) => citation.sourceLocator),
        contains(targets[i]),
      );
    }

    final warm = <int>[];
    for (var i = 0; i < 20; i++) {
      final watch = Stopwatch()..start();
      await controller.searchNotes('${queries[i % queries.length]} $i');
      warm.add(watch.elapsedMicroseconds);
    }
    warm.sort();

    final stalePath = index.notesByPath.keys.last;
    await vault.storage.delete(stalePath);
    await database.customStatement(
      "DELETE FROM nodes WHERE json_extract(attributes_json, '\$.path') = '$stalePath'",
    );
    index = await scanVaultStorage(vault.storage, force: true);
    workspace.index = index;
    workspace.notifyListeners();
    await controller.refreshNotes();
    expect(
      (await controller.searchNotes(
        queries.last,
        limit: 50,
      )).map((hit) => hit.id),
      isNot(contains(stalePath)),
    );
    controller.dispose();
    controllerDisposed = true;

    workspace
      ..entry = VaultEntry(
        id: 'p21-native',
        name: 'P21 native',
        path: root.path,
      )
      ..vault = vault
      ..index = index
      ..searchReady = true
      ..note = targets.first
      ..source = await vault.storage.readText(targets.first);
    workspace.notifyListeners();
    await tester.pumpAndSettle();

    // Open the real maintenance route once, which is the production controller
    // construction and model-install seam used by the search screen.
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    // The More sheet's lazy list has not built its Maintenance rows yet.
    await tester.scrollUntilVisible(
      find.text('Semantic search'),
      100,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Semantic search'));
    await tester.pumpAndSettle();
    for (
      var attempt = 0;
      attempt < 200 && find.textContaining('Ready').evaluate().isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.textContaining('Ready'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    expect(find.byType(KnowledgeScreen), findsOneWidget);

    for (var i = 0; i < queries.length; i++) {
      final query = queries[i];
      await tester.enterText(find.byType(TextField), query);
      await _waitForCitation(tester, targets[i]);
      final tile = _citationTile(tester, targets[i]);
      expect(tile, isNotNull);
      await tester.tap(find.byKey(tile!.key!));
      await tester.pumpAndSettle();
      for (
        var attempt = 0;
        attempt < 100 && workspace.note != targets[i];
        attempt++
      ) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(workspace.note, targets[i]);
      expect(home.mode, 'normal');
      // A note citation leaves search for the editor, like a keyword hit.
      expect(find.byType(KnowledgeScreen), findsNothing);
      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();
      expect(find.byType(KnowledgeScreen), findsOneWidget);
    }

    final warmMs = warm.map((value) => value / 1000).toList();
    final result = <String, Object>{
      'index_ms': indexing.elapsedMicroseconds / 1000,
      'first_query_ms': first.elapsedMicroseconds / 1000,
      'warm_p50_ms': warmMs[9],
      'warm_p95_ms': warmMs[18],
      'note_count': index.notesByPath.length,
    };
    // The app sandbox on Android has no writable ./build; the log line is the record.
    // ignore: avoid_print
    print('P21_RESULT ${jsonEncode(result)}');
    if (!Platform.isAndroid) {
      await Directory('build').create(recursive: true);
      await File(
        'build/p21_native_result.json',
      ).writeAsString(jsonEncode(result));
    }
    // ignore: avoid_print
    print(
      'P21_NATIVE index_ms=${result['index_ms']} first_query_ms=${result['first_query_ms']} warm_p50_ms=${result['warm_p50_ms']} warm_p95_ms=${result['warm_p95_ms']}',
    );
  });
}

Future<int> _p21Count(TyLogDatabase database, String sql) async {
  final row = await database.customSelect(sql).getSingle();
  return row.read<int>('count');
}

Future<Directory?> _prepareModel([Directory? handshakeRoot]) async {
  final support = await getApplicationSupportDirectory();
  final installedRoot = Directory(
    '${support.path}/models/multilingual-e5-small-ccc66d3',
  );
  final configured = handshakeRoot?.path ?? Platform.environment[_modelDirEnv];
  final source = configured == null || configured.isEmpty
      ? null
      : Directory(configured);
  final sourceStore = source == null ? null : SemanticModelStore(source);
  if (sourceStore != null && await sourceStore.installed() == null) {
    markTestSkipped(
      'P21_MODEL_DIR must contain model_O4.onnx, tokenizer.json, and verified.',
    );
    return null;
  }
  if (source != null) {
    await installedRoot.create(recursive: true);
    for (final item in kSemanticModelManifest) {
      final bytes = await File('${source.path}/${item.name}').readAsBytes();
      expect(bytes.length, item.bytes, reason: item.name);
      expect(sha256.convert(bytes).toString(), item.sha256, reason: item.name);
      await File(
        '${installedRoot.path}/${item.name}',
      ).writeAsBytes(bytes, flush: true);
    }
    await File('${installedRoot.path}/verified').writeAsString('verified\n');
  }
  if (await SemanticModelStore(installedRoot).installed() == null) {
    markTestSkipped(
      'No verified P21 model found; set P21_MODEL_DIR for offline execution.',
    );
    return null;
  }
  return installedRoot;
}

Future<void> _makeFixture(Directory root) async {
  final vault = Vault(root);
  await vault.ensureCreated();
  const topics = [
    (
      'Astronomy Observatory',
      'astronomy galaxies telescope orbital stars spectroscopy',
    ),
    (
      'Sourdough Fermentation',
      'sourdough bread baking yeast fermentation starter hydration',
    ),
    (
      'Native Garden',
      'garden soil compost pollinator biodiversity seedlings horticulture',
    ),
  ];
  for (final entry in topics) {
    final path = await vault.page(entry.$1);
    await vault.saveNote(
      path,
      '${await vault.storage.readText(path)}\n${entry.$2}\n',
    );
  }
  for (var i = 0; i < 47; i++) {
    final path = await vault.page('Fixture note $i');
    await vault.saveNote(
      path,
      '${await vault.storage.readText(path)}\nfixture archive note $i\n',
    );
  }
}

Future<void> _copyDirectory(Directory source, Directory target) async {
  await target.create(recursive: true);
  await for (final entity in source.list(recursive: true, followLinks: false)) {
    final relative = entity.path.substring(source.path.length + 1);
    final destination = '${target.path}/$relative';
    if (entity is Directory) {
      await Directory(destination).create(recursive: true);
    } else if (entity is File) {
      await File(destination).parent.create(recursive: true);
      await entity.copy(destination);
    }
  }
}

Future<void> _waitForCitation(WidgetTester tester, String path) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (_citationTile(tester, path) != null) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail('Timed out waiting for citation $path');
}

ListTile? _citationTile(WidgetTester tester, String path) {
  for (final tile in tester.widgetList<ListTile>(find.byType(ListTile))) {
    final subtitle = tile.subtitle;
    if (subtitle is Text && subtitle.data?.contains(path) == true) return tile;
  }
  return null;
}
