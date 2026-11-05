import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tylog_core/tylog_core.dart';
import 'package:tylog/vault.dart';
import 'package:tylog/widgets/journal_feed.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

class _FixtureStorage extends LocalVaultStorage {
  _FixtureStorage() : super(Directory.systemTemp);

  final sources = <String, String>{};

  @override
  Future<String> readText(String path) async => sources[path] ?? '';
}

Future<(VmService, String)> _connect() async {
  final uri = (await developer.Service.getInfo()).serverUri!;
  final ws = uri.replace(
    scheme: uri.scheme == 'https' ? 'wss' : 'ws',
    path: '${uri.path}ws',
  );
  final service = await vmServiceConnectUri(ws.toString());
  final vm = await service.getVM();
  return (service, vm.isolates!.firstWhere((i) => i.name == 'main').id!);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('PF4 journal scrolling, task rows, and retained memory', (
    tester,
  ) async {
    final (service, isolate) = await _connect();
    addTearDown(service.dispose);
    final frames = <FrameTiming>[];
    void collect(List<FrameTiming> sample) => frames.addAll(sample);
    SchedulerBinding.instance.addTimingsCallback(collect);
    addTearDown(() => SchedulerBinding.instance.removeTimingsCallback(collect));

    for (final dayCount in [50, 500, 5000]) {
      final storage = _FixtureStorage();
      final vault = Vault.withStorage(storage);
      final notes = <String, NoteRef>{};
      final tasks = <TaskRef>[];
      for (var i = 0; i < dayCount; i++) {
        final day = DateTime.utc(2020).add(Duration(days: i));
        final date =
            '${day.year.toString().padLeft(4, '0')}-'
            '${day.month.toString().padLeft(2, '0')}-'
            '${day.day.toString().padLeft(2, '0')}';
        final path = 'daily/$date.typ';
        final source = i == dayCount - 1
            ? List.generate(
                20,
                (n) => '#tylog.task(id: "task-$n", text: "Task $n")',
              ).join('\n\n')
            : 'Journal $date\n\n${'A short journal entry. ' * 8}';
        storage.sources[path] = source;
        notes[path] = NoteRef(
          id: date,
          path: path,
          title: date,
          date: date,
          kind: 'daily',
          outgoingLinks: const [],
        );
        if (i == dayCount - 1) {
          tasks.addAll([
            for (var n = 0; n < 20; n++)
              TaskRef(id: 'task-$n', notePath: path, text: 'Indexed task $n'),
          ]);
        }
      }
      final index = VaultIndex(
        notesByPath: notes,
        backlinksByTarget: const {},
        tasks: tasks,
      );
      await service.getAllocationProfile(isolate, gc: true);
      final before = await service.getMemoryUsage(isolate);
      final frameStart = frames.length;
      await service.clearCpuSamples(isolate);
      final watch = Stopwatch()..start();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: JournalFeed(vault: vault, index: index, onOpenPath: (_) {}),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(find.text('Indexed task 0'), findsOneWidget);
      final taskRows = find.textContaining('Indexed task').evaluate().length;
      final list = find.byType(ListView);
      const scrollGestures = 40;
      for (var i = 0; i < scrollGestures; i++) {
        await tester.fling(list, const Offset(0, -800), 3000);
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump();
      }
      watch.stop();
      await service.getAllocationProfile(isolate, gc: true);
      final after = await service.getMemoryUsage(isolate);
      final cpu = await service.getCpuSamples(isolate, 0, 1 << 62);
      final frameUs =
          frames
              .skip(frameStart)
              .map((f) => f.totalSpan.inMicroseconds)
              .toList()
            ..sort();
      int percentile(double p) =>
          frameUs.isEmpty ? 0 : frameUs[((frameUs.length - 1) * p).round()];
      // ignore: avoid_print
      print(
        'PF4_JOURNAL days=$dayCount indexedTasks=${tasks.length} '
        'renderedTaskRows=$taskRows '
        'scrollGestures=$scrollGestures '
        'browseMs=${watch.elapsedMilliseconds} '
        'heapBefore=${before.heapUsage} heapAfter=${after.heapUsage} '
        'heapDelta=${after.heapUsage! - before.heapUsage!} '
        'cpuSamples=${cpu.samples?.length ?? 0} '
        'cpuSamplePeriodUs=${cpu.samplePeriod} '
        'rssBytes=${ProcessInfo.currentRss} '
        'frames=${frameUs.length} frameP50Us=${percentile(.50)} '
        'frameP95Us=${percentile(.95)} frameP99Us=${percentile(.99)} '
        'frameMaxUs=${frameUs.isEmpty ? 0 : frameUs.last}',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
