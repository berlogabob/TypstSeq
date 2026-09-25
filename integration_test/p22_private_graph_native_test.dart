import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tylog/app_mobile.dart';
import 'package:tylog/database/tylog_database.dart';
import 'package:tylog/graph.dart';
import 'package:tylog/scanner.dart';
import 'package:tylog/vault.dart';
import 'package:tylog/vault_storage.dart';
import 'package:tylog/workspace_controller.dart';

// Opt-in, read-only backup rehearsal. Never calls app startup, sync or sharing.
const _sampleCount = int.fromEnvironment('P22_SAMPLES', defaultValue: 100);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('P22 private graph route and note navigation', (tester) async {
    final root = Platform.environment['TYLOG_PRIVATE_GRAPH_ROOT'];
    if (root == null || !Platform.environment.containsKey('FLUTTER_TEST')) {
      throw StateError('Set TYLOG_PRIVATE_GRAPH_ROOT and FLUTTER_TEST.');
    }
    final storage = _ReadOnlyStorage(LocalVaultStorage(Directory(root)));
    final scan = Stopwatch()..start();
    final index = await scanVaultStorage(storage);
    scan.stop();
    expect(index.notesByPath.length > 1, isTrue);

    final database = TyLogDatabase(NativeDatabase.memory());
    final closed = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          startup: () async {},
          databaseOpener: () async => database,
          databaseCloser: (database) async {
            await database.close();
            closed.complete();
          },
        ),
      ),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await closed.future;
    });
    final dynamic home = tester.state(find.byType(HomeScreen));
    final workspace = home.workspace as WorkspaceController;
    workspace
      ..index = index
      ..communities = computeCommunities(index)
      ..vault = Vault.withStorage(storage)
      ..note = index.notesByPath.keys.first;
    home.mode = 'graph';
    workspace.notifyListeners();
    await tester.pumpAndSettle();

    if (const bool.fromEnvironment('P22_DIAGNOSE')) {
      for (final mode in ['conceptMap', 'allFiles']) {
        final watch = Stopwatch()..start();
        final built = mode == 'conceptMap'
            ? buildConceptMap(index)
            : buildNoteGraph(index);
        final buildUs = watch.elapsedMicroseconds;
        final bounded = boundGraphForLayout(built, currentPath: workspace.note);
        final boundUs = watch.elapsedMicroseconds - buildUs;
        watch.reset();
        forceLayoutPositions(
          bounded,
          graphCanvasSize(bounded, workspace.note, const Size(800, 500)),
          communities: workspace.communities,
        );
        // ignore: avoid_print
        print(
          'P22_STAGE mode=$mode build_us=$buildUs bound_us=$boundUs layout_us=${watch.elapsedMicroseconds}',
        );
      }
    }
    final report = await measureGraphModes(tester, home);
    report['note_count'] = index.notesByPath.length;
    report['scan_us'] = scan.elapsedMicroseconds;
    final graph = tester.widget<GraphView>(find.byType(GraphView)).graph;
    report['allFiles_nodes'] = graph.nodes.length;
    report['allFiles_edges'] = graph.edges.length;

    // Exercise the accessibility selection callback, then the visible Open
    // button. Canvas hit-testing is covered by the synthetic native benchmark.
    final painter =
        tester
                .widget<CustomPaint>(
                  find.byWidgetPredicate(
                    (widget) =>
                        widget is CustomPaint && widget.painter is GraphPainter,
                  ),
                )
                .painter!
            as GraphPainter;
    final path = graph.nodes
        .firstWhere(
          (node) =>
              node.path != workspace.note &&
              index.notesByPath.containsKey(node.path),
        )
        .path;
    painter.onSelect(path);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('graph-open')));
    for (var attempt = 0; attempt < 100 && home.mode == 'graph'; attempt++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(workspace.note == path && home.mode == 'normal', isTrue);
    expect(home.sourceController.text == await storage.readText(path), isTrue);
    expect(storage.mutationAttempts, 0);
    report['navigation'] = true;
    report['vault_mutation_attempts'] = storage.mutationAttempts;
    binding.reportData = report;
    for (final mode in ['conceptMap', 'allFiles']) {
      final samples = [...report['${mode}_us']! as List<int>]..sort();
      expect(samples.length, _sampleCount);
      final p95 = samples[(samples.length * .95).ceil() - 1];
      // ignore: avoid_print
      print('P22_PRIVATE mode=$mode samples=$_sampleCount p95_us=$p95');
      expect(p95, lessThanOrEqualTo(500000));
    }
  });
}

class _ReadOnlyStorage extends VaultStorage {
  _ReadOnlyStorage(this.inner);
  final VaultStorage inner;
  int mutationAttempts = 0;

  Never _reject() {
    mutationAttempts++;
    throw StateError('Private graph rehearsal cannot modify the vault.');
  }

  @override
  Future<bool> exists(String path) => inner.exists(path);
  @override
  Future<List<VaultStorageEntry>> list({
    String path = '',
    bool recursive = false,
  }) => inner.list(path: path, recursive: recursive);
  @override
  Future<VaultStorageEntry?> stat(String path) => inner.stat(path);
  @override
  Future<Uint8List> readBytes(String path) => inner.readBytes(path);
  @override
  Future<String> hash(String path) => inner.hash(path);
  @override
  Future<void> createDirectory(String path) => _reject();
  @override
  Future<void> writeBytes(String path, List<int> bytes) => _reject();
  @override
  Future<void> delete(String path) => _reject();
}

Future<Map<String, Object>> measureGraphModes(
  WidgetTester tester,
  dynamic home,
) async {
  final menu = tester.widget<PopupMenuButton<String>>(
    find.byWidgetPredicate(
      (w) => w is PopupMenuButton<String> && w.tooltip == 'Graph view',
    ),
  );

  final samples = <String, List<int>>{'conceptMap': [], 'allFiles': []};

  final results = <String, Object>{
    'conceptMap_us': samples['conceptMap']!,
    'allFiles_us': samples['allFiles']!,
    'sample_count': _sampleCount,
  };

  for (var i = 0; i < _sampleCount; i++) {
    for (final mode in samples.keys) {
      home.workspace.indexRevision++;

      final stopwatch = Stopwatch()..start();

      menu.onSelected!(mode);
      await tester.pumpAndSettle();

      stopwatch.stop();

      final graph = tester.widget<GraphView>(find.byType(GraphView)).graph;

      expect(graph.nodes.isNotEmpty, isTrue);
      expect(graph.nodes.length <= 200, isTrue);
      expect(graph.edges.length <= 500, isTrue);

      samples[mode]!.add(stopwatch.elapsedMicroseconds);
    }
  }

  results['sample_count'] = _sampleCount;

  return results;
}
