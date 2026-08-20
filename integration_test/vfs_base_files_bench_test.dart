import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tylog/flutter_typst_inspector.dart';
import 'package:tylog_core/scanner.dart';
import 'package:tylog_core/storage.dart';

/// A/B measurement for the base-files handoff (plan Phase 1.1).
///
/// Mode A reproduces the old cold-index path: the whole support-file map
/// (package, templates, `assets/`) attached to every inspect, i.e. one full
/// FFI copy per note. Mode B installs the map once via `setBaseFiles` and
/// inspects with empty per-note files. Disjoint note samples and a fresh
/// engine per mode keep comemo's compile cache from flattering either side.
///
/// Read-only over the real vault; auto-skips when it is absent (CI).
/// Run: flutter test -d macos integration_test/vfs_base_files_bench_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('base-files handoff beats per-note file shipping', () async {
    final vault = Directory(
      '${Platform.environment['HOME']}/Nextcloud/TyLogVault',
    );
    if (!vault.existsSync()) {
      debugPrint('vfs bench skipped: no vault at ${vault.path}');
      return;
    }
    final storage = LocalVaultStorage(vault);

    const noteRoots = ['daily/', 'notes/', 'projects/', 'articles/'];
    final entries = await storage.list(recursive: true);
    // Same exclusions as the scanner's _inspectionFiles.
    final support = <String, Uint8List>{};
    var supportBytes = 0;
    final notes = <String>[];
    for (final entry in entries) {
      if (entry.isDirectory) continue;
      final path = entry.path;
      if (path.startsWith('_index/') ||
          path.startsWith('_system/index/') ||
          path.startsWith('.tylog/')) {
        continue;
      }
      if (noteRoots.any(path.startsWith) && path.endsWith('.typ')) {
        notes.add(path);
        continue;
      }
      final bytes = await storage.readBytes(path);
      support[path] = bytes;
      supportBytes += bytes.length;
    }
    notes.sort();
    // Disjoint interleaved samples of comparable composition.
    const perMode = 24;
    final stride = notes.length ~/ (perMode * 2);
    final sampleA = <String>[], sampleB = <String>[];
    for (var i = 0; i < perMode * 2; i++) {
      (i.isEven ? sampleA : sampleB).add(notes[i * (stride == 0 ? 1 : stride)]);
    }
    debugPrint(
      'vfs bench: ${notes.length} notes, support ${support.length} files '
      '${(supportBytes / (1 << 20)).toStringAsFixed(1)} MB, '
      '$perMode notes per mode',
    );

    Future<Duration> run(
      List<String> sample, {
      required bool baseFiles,
    }) async {
      final inspector = await FlutterTypstInspector.create();
      if (baseFiles) await inspector.setBaseFiles(support);
      final watch = Stopwatch()..start();
      var failures = 0;
      for (final path in sample) {
        final source = await storage.readText(path);
        try {
          await inspector.inspect(
            TypstDocumentInput(
              path: path,
              source: source,
              files: baseFiles ? const {} : support,
            ),
          );
        } catch (_) {
          failures++; // Broken notes fall back in production; count, don't die.
        }
      }
      watch.stop();
      inspector.dispose();
      debugPrint(
        '  mode ${baseFiles ? 'B (base-files)' : 'A (per-note)'}: '
        '${watch.elapsed.inMilliseconds} ms for ${sample.length} notes '
        '(${(sample.length / watch.elapsed.inMilliseconds * 60000).toStringAsFixed(1)} notes/min, '
        '$failures failures)',
      );
      return watch.elapsed;
    }

    final a = await run(sampleA, baseFiles: false);
    final b = await run(sampleB, baseFiles: true);

    expect(
      b < a,
      isTrue,
      reason: 'base-files handoff must beat shipping the vault per note '
          '(A=${a.inMilliseconds}ms, B=${b.inMilliseconds}ms)',
    );
  }, timeout: const Timeout(Duration(minutes: 30)));
}
