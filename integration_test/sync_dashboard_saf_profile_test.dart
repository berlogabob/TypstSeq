import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tylog/vault_registry.dart';
import 'package:tylog/vault_storage.dart';

/// Profile-only dashboard trace reload measurement.
///
/// Run with the release-signed profile app and
/// `flutter drive --profile --keep-app-running --driver=test_driver/integration_test.dart`.
/// The test requires the coordinator's disposable `TyLogAuditVault` fixture.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('SAF sync dashboard trace reload profile', (_) async {
    final registry = await VaultRegistry.load();
    final entry = registry.active;
    expect(entry.storageKind, 'android-tree');
    expect(entry.name, 'TyLogAuditVault');
    final storage = entry.storage;
    expect(storage, isA<AndroidTreeVaultStorage>());
    final saf = storage as AndroidTreeVaultStorage;
    expect(await saf.hasAccess(), isTrue);

    const marker = 'TyLogAuditVault\n';
    expect(
      await storage.readText('README-AUDIT.txt'),
      marker,
      reason: 'missing exact coordinator marker; refusing trace mutation',
    );

    const tracePath = '.tylog/sync_trace.jsonl';
    final hadTrace = await storage.exists(tracePath);
    final original = hadTrace ? await storage.readBytes(tracePath) : null;
    final trace = StringBuffer();
    for (var i = 0; i < 200; i++) {
      trace.writeln(
        jsonEncode({
          'timestamp':
              '2026-09-09T10:00:${(i % 60).toString().padLeft(2, '0')}Z',
          'runId': 'audit-$i',
          'event': 'sync-file',
          'path': 'notes/deterministic-$i.typ',
          'decision': i.isEven ? 'skip' : 'upload',
        }),
      );
    }
    final fixture = utf8.encode(trace.toString());

    Future<void> restore() async {
      if (hadTrace) {
        await storage.writeBytes(tracePath, original!);
      } else if (await storage.exists(tracePath)) {
        await storage.delete(tracePath);
      }
    }

    addTearDown(restore);
    await storage.writeBytes(tracePath, fixture);

    var existsProbes = 0;
    var traceReads = 0;
    var traceBytes = 0;
    var completedReloads = 0;
    var reloading = false;
    final samples = <Duration>[];
    final parseSamples = <Duration>[];

    Future<void> reload() async {
      if (reloading) return;
      reloading = true;
      final stopwatch = Stopwatch()..start();
      try {
        existsProbes++;
        if (!await storage.exists(tracePath)) return;
        final text = await storage.readText(tracePath);
        traceReads++;
        traceBytes += utf8.encode(text).length;
        final parseWatch = Stopwatch()..start();
        final events = [
          for (final line in text.split('\n'))
            if (line.trim().isNotEmpty) jsonDecode(line),
        ];
        parseWatch.stop();
        parseSamples.add(parseWatch.elapsed);
        expect(events, hasLength(200));
        completedReloads++;
      } finally {
        stopwatch.stop();
        samples.add(stopwatch.elapsed);
        reloading = false;
      }
    }

    var ticks = 0;
    var droppedFrames = 0;
    var worstGap = Duration.zero;
    var lastTick = DateTime.now();
    final frame = Timer.periodic(const Duration(milliseconds: 16), (_) {
      final now = DateTime.now();
      final gap = now.difference(lastTick);
      if (gap > worstGap) worstGap = gap;
      final late = gap - const Duration(milliseconds: 16);
      if (late > Duration.zero) {
        droppedFrames += late.inMicroseconds ~/ 16000;
      }
      ticks++;
      lastTick = now;
    });
    final refresh = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => unawaited(reload()),
    );

    final run = Stopwatch()..start();
    await reload();
    await Future<void>.delayed(const Duration(seconds: 60));
    run.stop();
    refresh.cancel();
    frame.cancel();
    while (reloading) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    String stats(List<Duration> values) {
      final micros = values.map((value) => value.inMicroseconds).toList()
        ..sort();
      int percentile(double value) =>
          micros[(micros.length * value).ceil() - 1];
      return 'p50=${percentile(.50) / 1000}ms '
          'p95=${percentile(.95) / 1000}ms '
          'max=${micros.last / 1000}ms';
    }

    // ignore: avoid_print
    print(
      'DASHBOARD-PROFILE seconds=${run.elapsed.inSeconds} '
      'reloads=$completedReloads exists=$existsProbes reads=$traceReads '
      'bytes=$traceBytes loadParse(${stats(samples)}) '
      'parse(${stats(parseSamples)}) '
      'frames=$ticks dropped=$droppedFrames '
      'worstGap=${worstGap.inMilliseconds}ms',
    );
  }, skip: !Platform.isAndroid);
}
