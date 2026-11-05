import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tylog/task_scheduler.dart';
import 'package:tylog/vault.dart';
import 'package:tylog/vault_registry.dart';
import 'package:tylog/vault_storage.dart';
import 'package:tylog/workspace_controller.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

class _MeasuredStorage extends LocalVaultStorage {
  _MeasuredStorage(super.root);

  int listCalls = 0;
  int readCalls = 0;
  int existsCalls = 0;

  @override
  Future<List<VaultStorageEntry>> list({
    String path = '',
    bool recursive = false,
  }) {
    listCalls++;
    return super.list(path: path, recursive: recursive);
  }

  @override
  Future<Uint8List> readBytes(String path) {
    readCalls++;
    return super.readBytes(path);
  }

  @override
  Future<bool> exists(String path) {
    existsCalls++;
    return super.exists(path);
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

  testWidgets('PF6 vendored package readiness across isolated file counts', (
    tester,
  ) async {
    final (service, isolate) = await _connect();
    addTearDown(service.dispose);
    final timings = <FrameTiming>[];
    void collect(List<FrameTiming> values) => timings.addAll(values);
    SchedulerBinding.instance.addTimingsCallback(collect);
    addTearDown(() => SchedulerBinding.instance.removeTimingsCallback(collect));

    for (final fileCount in [0, 100, 1000]) {
      final root = await Directory.systemTemp.createTemp('pf6-packages-');
      final storage = _MeasuredStorage(root);
      await Vault.withStorage(storage).ensureCreated();
      for (var i = 0; i < fileCount; i++) {
        final path = '_system/packages/pkg-$i/1.0.0/lib.typ';
        await storage.writeBytes(path, Uint8List.fromList([i & 255, 10, 13]));
      }
      final controller = WorkspaceController(
        taskScheduler: TaskScheduler(),
        reconcileTasks: (_) async {},
      );
      var notifications = 0;
      var readyNotifications = 0;
      var rebuildNotifications = 0;
      var rebuildProgressTicks = 0;
      void collectRebuildProgress() => rebuildProgressTicks++;
      controller.addListener(() {
        notifications++;
        if (controller.typstPackagesReady) readyNotifications++;
        if (controller.status.startsWith('Rebuilding index:')) {
          rebuildNotifications++;
        }
      });
      controller.syncProgressTick.addListener(collectRebuildProgress);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: controller,
              builder: (_, __) => Text(
                controller.typstPackagesReady
                    ? 'Packages ready'
                    : 'Loading packages',
              ),
            ),
          ),
        ),
      );
      await service.getAllocationProfile(isolate, gc: true);
      final heapBefore = (await service.getMemoryUsage(isolate)).heapUsage!;
      final rssBefore = ProcessInfo.currentRss;
      await service.clearCpuSamples(isolate);
      final frameStart = timings.length;
      final watch = Stopwatch()..start();
      await controller.openVault(
        VaultEntry(id: 'pf6-$fileCount', name: 'PF6 fixture', path: root.path),
        storage: storage,
      );
      final deadline = DateTime.now().add(const Duration(minutes: 3));
      while ((!controller.typstPackagesReady || controller.rebuilding) &&
          DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 16));
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      watch.stop();
      expect(controller.typstPackagesReady, isTrue);
      expect(
        controller.typstPackageFiles.keys
            .where((path) => path.startsWith('_system/packages/pkg-'))
            .length,
        fileCount,
      );
      await tester.pump(const Duration(milliseconds: 100));
      final heapAfter = (await service.getMemoryUsage(isolate)).heapUsage!;
      final cpu = await service.getCpuSamples(isolate, 0, 1 << 62);
      final frameUs =
          timings
              .skip(frameStart)
              .map((timing) => timing.totalSpan.inMicroseconds)
              .toList()
            ..sort();
      int percentile(double p) =>
          frameUs.isEmpty ? 0 : frameUs[((frameUs.length - 1) * p).round()];
      // ignore: avoid_print
      print(
        'PF6_PACKAGES files=$fileCount readyMs=${watch.elapsedMilliseconds} '
        'readyNotifications=$readyNotifications rebuildNotifications=$rebuildNotifications '
        'workspaceNotifications=$notifications listCalls=${storage.listCalls} '
        'readCalls=${storage.readCalls} existsCalls=${storage.existsCalls} '
        'platformChannelCalls=0 channelFixture=app-local '
        'cpuSamples=${cpu.samples?.length ?? 0} cpuPeriodUs=${cpu.samplePeriod} '
        'heapBefore=$heapBefore heapAfter=$heapAfter heapDelta=${heapAfter - heapBefore} '
        'rssBefore=$rssBefore rssAfter=${ProcessInfo.currentRss} '
        'frames=${frameUs.length} frameP95Us=${percentile(.95)} '
        'frameP99Us=${percentile(.99)} frameMaxUs=${frameUs.isEmpty ? 0 : frameUs.last}',
      );
      expect(readyNotifications, greaterThan(0));
      while (controller.indexing && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 16));
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      for (var i = 0; i < 205; i++) {
        await storage.writeText('notes/pf6-$i.typ', '= PF6 note $i\n');
      }
      rebuildProgressTicks = 0;
      await controller.rebuildIndex(force: true);
      expect(rebuildProgressTicks, greaterThan(0));
      // ignore: avoid_print
      print(
        'PF6_REBUILD files=205 progressTicks=$rebuildProgressTicks '
        'workspaceNotifications=$rebuildNotifications',
      );
      controller.syncProgressTick.removeListener(collectRebuildProgress);
      controller.dispose();
      await root.delete(recursive: true);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  }, timeout: const Timeout(Duration(minutes: 15)));
}
