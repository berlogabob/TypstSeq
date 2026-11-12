import 'dart:developer' as developer;
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tylog_core/tylog_core.dart';
import 'package:tylog/vault.dart';
import 'package:tylog/widgets/journal_feed.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

abstract class _ProfileStorageBase extends LocalVaultStorage {
  _ProfileStorageBase(super.root);
  final readPaths = <String>{};
}

class _ProfileStorage extends _ProfileStorageBase {
  _ProfileStorage(super.root);

  @override
  Future<String> readText(String path) {
    readPaths.add(path);
    return super.readText(path);
  }
}

class _MemoryProfileStorage extends _ProfileStorageBase {
  _MemoryProfileStorage() : super(Directory.systemTemp);

  final sources = <String, String>{};

  @override
  Future<void> writeText(String path, String value) async {
    sources[path] = value;
  }

  @override
  Future<String> readText(String path) async {
    readPaths.add(path);
    return sources[path] ?? '';
  }
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

    for (final backend in ['memory', 'disk']) {
      for (final dayCount in [50, 500, 5000]) {
        final root = backend == 'disk'
            ? await Directory.systemTemp.createTemp('pf4-journal-')
            : null;
        if (root != null) addTearDown(() => root.delete(recursive: true));
        final storage = backend == 'disk'
            ? _ProfileStorage(root!)
            : _MemoryProfileStorage();
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
          await storage.writeText(path, source);
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
        var scrollGestures = 0;
        while (storage.readPaths.length < dayCount && scrollGestures < 20000) {
          await tester.fling(list, const Offset(0, -1200), 5000);
          await tester.pump(const Duration(milliseconds: 100));
          await tester.pump();
          scrollGestures++;
        }
        watch.stop();
        expect(
          storage.readPaths.length,
          dayCount,
          reason:
              'the profile must read every day before taking its heap sample',
        );
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
          'PF4_JOURNAL backend=$backend days=$dayCount '
          'indexedTasks=${tasks.length} '
          'renderedTaskRows=$taskRows '
          'scrollGestures=$scrollGestures readDays=${storage.readPaths.length} '
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
    }
  }, timeout: const Timeout(Duration(minutes: 30)));
}
