import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tylog/app_mobile.dart';
import 'package:tylog/database/tylog_database.dart';
import 'package:tylog/graph.dart';
import 'package:tylog/scanner.dart';
import 'package:tylog/vault.dart';
import 'package:tylog/vault_storage.dart';
import 'package:tylog/workspace_controller.dart';

// Opt-in, read-only backup rehearsal. Never calls app startup, sync or sharing.
const _sampleCount = int.fromEnvironment('P22_SAMPLES', defaultValue: 100);

// Android has no host env and adb cannot create app-owned dirs: with
// P22_HANDSHAKE the app creates its external dir, prints P22_READY, and waits
// for the host to push the vault as <dir>/TyLog plus a .done marker.
const _handshake = bool.fromEnvironment('P22_HANDSHAKE');

Future<String?> _resolveGraphRoot() async {
  if (!_handshake) {
    final root = Platform.environment['TYLOG_PRIVATE_GRAPH_ROOT'];
    return root != null && Platform.environment.containsKey('FLUTTER_TEST')
        ? root
        : null;
  }
  final dir = Directory('${(await getExternalStorageDirectory())!.path}/p22');
  await dir.create(recursive: true);
  // ignore: avoid_print
  print('P22_READY ${dir.path}');
  for (var i = 0; i < 1800; i++) {
    if (File('${dir.path}/.done').existsSync()) return '${dir.path}/TyLog';
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  throw StateError('Handshake timed out waiting for the pushed vault.');
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'P22 private graph route and note navigation',
    (tester) async {
      final root = await _resolveGraphRoot();
      if (root == null) {
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
          final bounded = boundGraphForLayout(
            built,
            currentPath: workspace.note,
          );
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
                          widget is CustomPaint &&
                          widget.painter is GraphPainter,
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
      expect(
        home.sourceController.text == await storage.readText(path),
        isTrue,
      );
      expect(storage.mutationAttempts, 0);
      report['navigation'] = true;
      report['vault_mutation_attempts'] = storage.mutationAttempts;
      binding.reportData = report;
      for (final mode in ['conceptMap', 'allFiles']) {
        final samples = [...report['${mode}_us']! as List<int>]..sort();
        final count = samples.length;
        expect(count, _sampleCount);
        final p50 = samples[(count * .50).ceil() - 1];
        final p95 = samples[(count * .95).ceil() - 1];
        final max = samples.last;
        report['${mode}_valid'] = count;
        report['${mode}_p50_us'] = p50;
        report['${mode}_p95_us'] = p95;
        report['${mode}_max_us'] = max;
        // ignore: avoid_print
        print(
          'P22_PRIVATE mode=$mode valid=$count p50_us=$p50 p95_us=$p95 max_us=$max',
        );
        expect(p95, lessThanOrEqualTo(500000));
      }
    },
    skip:
        (Platform.environment['TYLOG_PRIVATE_GRAPH_ROOT'] ?? '').isEmpty &&
        !_handshake,
  );
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

  if (tester.binding.lifecycleState != AppLifecycleState.resumed) {
    throw StateError(
      'App is not foreground (${tester.binding.lifecycleState}); '
      'samples would be invalid.',
    );
  }
  var attempts = 0;
  while (samples.values.any((values) => values.length < _sampleCount)) {
    if (++attempts > _sampleCount * 6) {
      throw StateError('Too many invalid P22 samples: $results');
    }
    for (final mode in samples.keys) {
      if (samples[mode]!.length == _sampleCount) continue;
      final timing = await _switchToSettledGraph(tester, menu, mode);
      final graphFinder = find.byType(GraphView);
      final valid =
          timing != null &&
          find.byType(CircularProgressIndicator).evaluate().isEmpty &&
          tester.binding.lifecycleState == AppLifecycleState.resumed &&
          graphFinder.evaluate().length == 1 &&
          _graphModeIsShown(tester, mode) &&
          find
                  .byWidgetPredicate(
                    (widget) =>
                        widget is CustomPaint && widget.painter is GraphPainter,
                  )
                  .evaluate()
                  .length ==
              1 &&
          _selectedPath(tester) == home.workspace.note &&
          !tester.binding.hasScheduledFrame;
      if (!valid) continue;
      final graph = tester.widget<GraphView>(graphFinder).graph;
      if (graph.nodes.isEmpty ||
          graph.nodes.length > 200 ||
          graph.edges.length > 500) {
        continue;
      }
      samples[mode]!.add(timing);
    }
  }

  results['sample_count'] = _sampleCount;
  for (final entry in samples.entries) {
    results['${entry.key}_valid'] = entry.value.length;
  }

  return results;
}

Future<int?> _switchToSettledGraph(
  WidgetTester tester,
  dynamic menu,
  String mode,
) async {
  // Wall-clock from the menu selection to the first settled frame showing the
  // mode. Each pump waits for a real frame; a 5 s cap keeps a stalled frame
  // pipeline (backgrounded window) from hanging the run — it is an invalid
  // sample instead.
  final watch = Stopwatch()..start();
  menu.onSelected!(mode);
  for (var frame = 0; frame < 200; frame++) {
    try {
      await tester.pump().timeout(const Duration(seconds: 5));
    } on TimeoutException {
      return null;
    }
    if (_graphModeIsShown(tester, mode) &&
        find.byType(CircularProgressIndicator).evaluate().isEmpty &&
        !tester.binding.hasScheduledFrame) {
      return watch.elapsedMicroseconds;
    }
  }
  return null;
}

bool _graphModeIsShown(WidgetTester tester, String mode) {
  final graph = tester.widget<GraphView>(find.byType(GraphView));
  return mode == 'allFiles'
      ? graph.isWholeVault
      : graph.graph.nodes.every((node) => node.kind == GraphNodeKind.concept);
}

String? _selectedPath(WidgetTester tester) {
  final painter = tester
      .widget<CustomPaint>(
        find.byWidgetPredicate(
          (widget) => widget is CustomPaint && widget.painter is GraphPainter,
        ),
      )
      .painter;
  return painter is GraphPainter ? painter.selectedPath : null;
}
