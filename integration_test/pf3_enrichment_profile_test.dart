import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tylog_core/tylog_core.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

EnrichMemory _buildMemory((VaultIndex, List<EnrichFeedback>) input) =>
    EnrichMemory.build(input.$1, input.$2);

EnrichDayResolution _resolve(
  (EnrichMentions, NoteRef, EnrichMemory, VaultIndex, String) input,
) => resolveEnrichDay(input.$1, input.$2, input.$3, input.$4, input.$5);

Future<(VmService, String)> _connect() async {
  final info = await developer.Service.getInfo();
  final uri = info.serverUri!;
  final ws = uri.replace(
    scheme: uri.scheme == 'https' ? 'wss' : 'ws',
    path: '${uri.path}ws',
  );
  final service = await vmServiceConnectUri(ws.toString());
  final vm = await service.getVM();
  return (service, vm.isolates!.firstWhere((i) => i.name == 'main').id!);
}

Future<int?> _heapBytes() async {
  final (service, isolate) = await _connect();
  try {
    return (await service.getMemoryUsage(isolate)).heapUsage;
  } finally {
    await service.dispose();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('PF3 enrichment profile across page and mention sizes', (
    tester,
  ) async {
    const sizes = [1000, 10000];
    const mentionCounts = [1, 20, 100];
    final frames = <FrameTiming>[];
    void collect(List<FrameTiming> sample) => frames.addAll(sample);
    SchedulerBinding.instance.addTimingsCallback(collect);
    addTearDown(() => SchedulerBinding.instance.removeTimingsCallback(collect));
    final (service, rootIsolate) = await _connect();
    addTearDown(service.dispose);
    final baselineHeap = await service.getMemoryUsage(rootIsolate);
    await service.clearCpuSamples(rootIsolate);

    for (final pageCount in sizes) {
      final notes = <String, NoteRef>{};
      for (var i = 0; i < pageCount; i++) {
        final path = 'people/person-$i.typ';
        notes[path] = NoteRef(
          id: 'person-$i',
          path: path,
          title: 'Person $i',
          kind: 'person',
          outgoingLinks: const [],
        );
      }
      final index = VaultIndex(notesByPath: notes, backlinksByTarget: const {});
      final day = NoteRef(
        id: 'day',
        path: 'daily/2026-11-05.typ',
        title: 'Today',
        kind: 'daily',
        outgoingLinks: const [],
      );
      for (final mentionCount in mentionCounts) {
        final caseHeapBefore = await service.getMemoryUsage(rootIsolate);
        await service.clearCpuSamples(rootIsolate);
        final frameStart = frames.length;
        final mentions = EnrichMentions(
          note: day.path,
          contentSha: '',
          mentions: [
            for (var i = 0; i < mentionCount; i++)
              EnrichMention(surface: 'Person $i', type: 'person', line: i + 1),
          ],
        );
        final source = List.generate(
          mentionCount,
          (i) => 'Person $i',
        ).join('\n');
        final memoryWatch = Stopwatch()..start();
        final memory = await compute(_buildMemory, (index, <EnrichFeedback>[]));
        memoryWatch.stop();
        final resolveWatch = Stopwatch()..start();
        final resolution = await compute(_resolve, (
          mentions,
          day,
          memory,
          index,
          source,
        ));
        resolveWatch.stop();
        final caseHeapAfter = await service.getMemoryUsage(rootIsolate);
        final caseCpu = await service.getCpuSamples(rootIsolate, 0, 1 << 62);
        expect(resolution.decisions, hasLength(mentionCount));
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ListView.builder(
                itemCount: resolution.decisions.length,
                itemBuilder: (_, i) => ListTile(
                  title: Text(resolution.decisions[i].mention.surface),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        // ignore: avoid_print
        print(
          'TYLOG_ENRICH profile pages=$pageCount mentions=$mentionCount '
          'memoryMs=${memoryWatch.elapsedMilliseconds} '
          'resolveMs=${resolveWatch.elapsedMilliseconds} '
          'totalMs=${memoryWatch.elapsedMilliseconds + resolveWatch.elapsedMilliseconds} '
          'rootCpuSamples=${caseCpu.samples?.length ?? 0} '
          'rootCpuSamplePeriodUs=${caseCpu.samplePeriod} '
          'heapDelta=${caseHeapAfter.heapUsage! - caseHeapBefore.heapUsage!} '
          'framesUs=${frames.skip(frameStart).map((f) => f.totalSpan.inMicroseconds).toList()}',
        );
      }
    }
    final afterHeap = await service.getMemoryUsage(rootIsolate);
    final totalFrameMs = frames.map((f) => f.totalSpan.inMicroseconds).toList();
    // ignore: avoid_print
    print(
      'PF3_ENRICH_DEVICE pages=$sizes mentions=$mentionCounts '
      'heapBefore=${baselineHeap.heapUsage} heapAfter=${afterHeap.heapUsage} '
      'heapDelta=${afterHeap.heapUsage! - baselineHeap.heapUsage!} '
      'rssBytes=${ProcessInfo.currentRss} framesUs=$totalFrameMs',
    );
  }, timeout: const Timeout(Duration(minutes: 10)));
}
