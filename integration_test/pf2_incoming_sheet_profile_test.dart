import 'dart:developer' as developer;
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tylog/app_mobile.dart';
import 'package:tylog/vault_registry.dart';
import 'package:vm_service/vm_service.dart' show VmService;
import 'package:vm_service/vm_service_io.dart';

Future<int?> _heapBytes() async {
  final info = await developer.Service.getInfo();
  final uri = info.serverUri;
  if (uri == null) return null;
  final ws = uri.replace(
    scheme: uri.scheme == 'https' ? 'wss' : 'ws',
    path: '${uri.path}ws',
  );
  VmService service;
  try {
    service = await vmServiceConnectUri(ws.toString());
  } on SocketException catch (error) {
    developer.log('PF2_HEAP_UNAVAILABLE $error');
    return null;
  }
  try {
    final vm = await service.getVM();
    final isolate = vm.isolates?.firstWhere((i) => i.isSystemIsolate != true);
    if (isolate == null) return null;
    return (await service.getMemoryUsage(isolate.id!)).heapUsage;
  } finally {
    await service.dispose();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('PF2 actual Incoming sheet on the P30 profile vault copy', (
    tester,
  ) async {
    final registry = await VaultRegistry.load();
    expect(registry.entries, isNotEmpty, reason: 'profile vault copy missing');
    expect(
      registry.active.storageKind,
      'app-local',
      reason: 'P2P6 received copy is not active',
    );

    final frames = <FrameTiming>[];
    void collect(List<FrameTiming> values) => frames.addAll(values);
    SchedulerBinding.instance.addTimingsCallback(collect);
    addTearDown(() => SchedulerBinding.instance.removeTimingsCallback(collect));

    await tester.pumpWidget(const TyLogApp());
    final openMore = find.byKey(const ValueKey('daily-more'));
    final deadline = DateTime.now().add(const Duration(minutes: 2));
    while (openMore.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    expect(openMore, findsWidgets, reason: 'home did not load profile vault');
    await tester.tap(openMore.first);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    final incomingOpen = find.byKey(const ValueKey('incoming-open'));
    expect(incomingOpen, findsOneWidget);

    final heapBefore = await _heapBytes();
    final openFrames = frames.length;
    final readyWatch = Stopwatch()..start();
    await tester.ensureVisible(incomingOpen);
    await tester.tap(incomingOpen);
    await tester.pump();
    final sheetDeadline = DateTime.now().add(const Duration(minutes: 2));
    final sheetTitle = find.text('Incoming');
    while ((sheetTitle.evaluate().isEmpty ||
            find.byType(CircularProgressIndicator).evaluate().isNotEmpty) &&
        DateTime.now().isBefore(sheetDeadline)) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    readyWatch.stop();
    expect(sheetTitle, findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pump(const Duration(milliseconds: 100));

    final sheetFrames = frames.skip(openFrames).toList();
    final heapAfter = await _heapBytes();
    final maxFrameUs = sheetFrames
        .map((frame) => frame.totalSpan.inMicroseconds)
        .fold<int>(0, (max, span) => span > max ? span : max);
    // ignore: avoid_print
    print(
      'PF2_INCOMING_SHEET readyMs=${readyWatch.elapsedMilliseconds} '
      'storageKind=${registry.active.storageKind} '
      'maxFrameUs=$maxFrameUs frameCount=${sheetFrames.length} '
      'heapBefore=$heapBefore heapAfter=$heapAfter '
      'heapDelta=${heapBefore == null || heapAfter == null ? null : heapAfter - heapBefore} '
      'rssBytes=${ProcessInfo.currentRss}',
    );
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(minutes: 4)));
}
