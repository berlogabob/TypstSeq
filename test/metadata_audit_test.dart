@Tags(['audit'])
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog_core/tylog_core.dart';

/// Metadata parsing/scanner audit harness (report-only; always passes).
/// Runs the real `typst` metadata query over the vault via the CLI inspector
/// (a faithful proxy for the native one — same decode path), classifying each
/// note and timing it, to size the query/fallback/failed distribution, the
/// failure taxonomy, poisoning risk, and the fallback `properties` gap.
///
/// Opt-in (slow — one Typst compile per note):
///   AUDIT_VAULT=1 flutter test test/metadata_audit_test.dart --tags audit -r expanded
/// Optional AUDIT_STRIDE=N samples every Nth note (default 1 = all).

String _bucketError(String raw) {
  final line = raw.split('\n').firstWhere((l) => l.trim().isNotEmpty,
      orElse: () => raw);
  final l = line.toLowerCase();
  if (l.contains('unknown variable') && l.contains('tylog')) {
    return 'missing/incompatible tylog import';
  }
  if (l.contains('unknown variable')) return 'unknown variable';
  if (l.contains('unexpected') || l.contains('expected')) return 'syntax error';
  if (l.contains('file not found') || l.contains('failed to load')) {
    return 'missing file/asset';
  }
  if (l.contains('type') && l.contains('has no')) return 'type/field error';
  if (l.contains('not found') && l.contains('root')) return 'outside root';
  return 'other: ${line.length > 60 ? '${line.substring(0, 60)}…' : line}';
}

void main() {
  test('METADATA AUDIT: query / fallback / failed distribution', () async {
    if (Platform.environment['AUDIT_VAULT'] != '1') {
      // ignore: avoid_print
      print('metadata audit skipped (set AUDIT_VAULT=1 to run the sweep).');
      return;
    }
    final vault =
        Directory('${Platform.environment['HOME']}/Nextcloud/TyLogVault');
    if (!vault.existsSync()) {
      // ignore: avoid_print
      print('vault not found: ${vault.path}');
      return;
    }
    final stride = int.tryParse(Platform.environment['AUDIT_STRIDE'] ?? '1') ?? 1;
    // Match the real scanner's note roots (excludes _system, .tylog backups).
    const noteRoots = ['daily/', 'notes/', 'projects/', 'articles/'];
    final files = vault
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) {
          if (!f.path.endsWith('.typ')) return false;
          final rel = f.path.replaceAll('${vault.path}/', '');
          return noteRoots.any(rel.startsWith);
        })
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    final inspector = CliTypstInspector(vault, executable: 'typst');
    var query = 0, fallback = 0, failed = 0, scanned = 0;
    var slow = 0, propsGap = 0;
    var maxMs = 0;
    final errorBuckets = <String, int>{};
    final errorExample = <String, String>{};
    final slowNotes = <String>[];

    for (var i = 0; i < files.length; i += stride) {
      final f = files[i];
      final rel = f.path.replaceAll('${vault.path}/', '');
      scanned++;
      final sw = Stopwatch()..start();
      try {
        final records = await inspector
            .inspect(TypstDocumentInput(path: rel, source: f.readAsStringSync()))
            .timeout(const Duration(seconds: 30));
        sw.stop();
        final meta = decodeTylogMetadataRecords(records);
        if (meta.note != null) {
          query++;
          final props = meta.note!['properties'];
          if (props is Map && props.isNotEmpty) propsGap++;
        } else {
          fallback++;
        }
      } catch (e) {
        sw.stop();
        failed++;
        final bucket =
            e is TimeoutException ? 'TIMEOUT (poisons native pass)' : _bucketError('$e');
        errorBuckets.update(bucket, (v) => v + 1, ifAbsent: () => 1);
        errorExample.putIfAbsent(bucket, () => rel);
      }
      final ms = sw.elapsedMilliseconds;
      if (ms > maxMs) maxMs = ms;
      if (ms > 5000) {
        slow++;
        if (slowNotes.length < 8) slowNotes.add('$rel (${ms}ms)');
      }
    }

    String pct(int n) => '${(100 * n / scanned).toStringAsFixed(1)}%';
    // ignore: avoid_print
    print('\n============ METADATA PARSING AUDIT ============');
    // ignore: avoid_print
    print('vault notes total ${files.length}; scanned $scanned (stride $stride)');
    // ignore: avoid_print
    print('DISTRIBUTION:');
    // ignore: avoid_print
    print('  typst-query (verified)     $query  (${pct(query)})');
    // ignore: avoid_print
    print('  fallback (no #metadata)    $fallback  (${pct(fallback)})');
    // ignore: avoid_print
    print('  query-failed (compile err) $failed  (${pct(failed)})');
    // ignore: avoid_print
    print('PROPERTIES GAP: $propsGap verified notes carry non-empty properties '
        'that _fallbackNote drops ($fallback fallback notes are already stripped)');
    // ignore: avoid_print
    print('POISONING RISK: $slow notes took >5s (max ${maxMs}ms; native worker '
        'times out at 30s and poisons the rest of the pass)');
    for (final s in slowNotes) {
      // ignore: avoid_print
      print('    slow: $s');
    }
    // ignore: avoid_print
    print('FAILURE TAXONOMY:');
    final buckets = errorBuckets.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final e in buckets) {
      // ignore: avoid_print
      print('  [${e.value.toString().padLeft(4)}] ${e.key}');
      // ignore: avoid_print
      print('         e.g. ${errorExample[e.key]}');
    }
    // ignore: avoid_print
    print('========== END METADATA PARSING AUDIT ==========\n');
    expect(true, isTrue);
  }, timeout: const Timeout(Duration(minutes: 30)));
}
