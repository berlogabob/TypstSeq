import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tylog/task_scheduler.dart';
import 'package:tylog/vault.dart';
import 'package:tylog/vault_registry.dart';
import 'package:tylog/vault_storage.dart';
import 'package:tylog/widgets/entity_timeline.dart';
import 'package:tylog/workspace_controller.dart';
import 'package:tylog_core/tylog_core.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

class _MeasuredLocalStorage extends LocalVaultStorage {
  _MeasuredLocalStorage(super.root);

  int readCalls = 0;
  int readBytesTotal = 0;
  Duration readTime = Duration.zero;

  void reset() {
    readCalls = 0;
    readBytesTotal = 0;
    readTime = Duration.zero;
  }

  @override
  Future<String> readText(String path) async {
    final watch = Stopwatch()..start();
    try {
      final text = await super.readText(path);
      readCalls++;
      readBytesTotal += utf8.encode(text).length;
      return text;
    } finally {
      watch.stop();
      readTime += watch.elapsed;
    }
  }
}

class _MeasuredSafStorage extends AndroidTreeVaultStorage {
  _MeasuredSafStorage({required super.uri, required super.name});

  int readCalls = 0;
  int readBytesTotal = 0;
  Duration readTime = Duration.zero;

  void reset() {
    readCalls = 0;
    readBytesTotal = 0;
    readTime = Duration.zero;
  }

  @override
  Future<String> readText(String path) async {
    final watch = Stopwatch()..start();
    try {
      final text = await super.readText(path);
      readCalls++;
      readBytesTotal += utf8.encode(text).length;
      return text;
    } finally {
      watch.stop();
      readTime += watch.elapsed;
    }
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

  testWidgets('PF5 timeline and merge preview CPU, frames, reads, and heap', (
    tester,
  ) async {
    final (service, isolate) = await _connect();
    addTearDown(service.dispose);
    final frames = <FrameTiming>[];
    void collect(List<FrameTiming> sample) => frames.addAll(sample);
    SchedulerBinding.instance.addTimingsCallback(collect);
    addTearDown(() => SchedulerBinding.instance.removeTimingsCallback(collect));

    for (final count in [50, 500, 1000]) {
      final root = await Directory.systemTemp.createTemp('pf5-local-');
      final storage = _MeasuredLocalStorage(root);
      final vault = Vault.withStorage(storage);
      await vault.ensureCreated();
      final index = await _writeMergeFixture(storage, count);
      await _profileFixture(
        tester,
        service,
        isolate,
        frames,
        storage,
        Vault.withStorage(storage),
        index,
        vaultName: 'app-local',
        fixtureSize: count,
      );
      await root.delete(recursive: true);
      await tester.pumpWidget(const SizedBox.shrink());
    }

    final selection = await AndroidTreeVaultStorage.pick();
    expect(
      selection,
      isNotNull,
      reason: 'select the dedicated empty PF5 fixture folder in Downloads',
    );
    final registry = await VaultRegistry.load();
    final entry = await registry.addTree(selection!);
    await registry.select(entry);
    final saf = _MeasuredSafStorage(uri: entry.treeUri!, name: entry.name);
    final safVault = Vault.withStorage(saf);
    for (final count in [50, 500]) {
      final index = await _writeMergeFixture(saf, count);
      await _profileFixture(
        tester,
        service,
        isolate,
        frames,
        saf,
        safVault,
        index,
        vaultName: 'SAF',
        fixtureSize: count,
      );
      for (final path in [
        'work/notes/keep.typ',
        'work/notes/remove.typ',
        for (var i = 0; i < count; i++) 'work/notes/n$i.typ',
      ]) {
        await saf.delete(path);
      }
    }
    await saf.deleteEmptyDirectory('work/notes');
  }, timeout: const Timeout(Duration(minutes: 30)));
}

Future<VaultIndex> _writeMergeFixture(VaultStorage storage, int count) async {
  await storage.createDirectory('work');
  await storage.createDirectory('work/notes');
  const keep = NoteRef(
    id: 'keep',
    path: 'work/notes/keep.typ',
    title: 'Keep',
    kind: 'person',
    outgoingLinks: [],
  );
  const remove = NoteRef(
    id: 'remove',
    path: 'work/notes/remove.typ',
    title: 'Remove',
    kind: 'person',
    outgoingLinks: [],
  );
  await _writeFixtureText(
    storage,
    keep.path,
    replaceNoteHeader(
      '',
      const NoteMetadataDraft(
        id: 'keep',
        title: 'Keep',
        kind: 'person',
        tags: ['person'],
      ),
    ),
  );
  await _writeFixtureText(
    storage,
    remove.path,
    replaceNoteHeader(
      '',
      const NoteMetadataDraft(
        id: 'remove',
        title: 'Remove',
        kind: 'person',
        tags: ['person'],
      ),
    ),
  );
  final notes = <String, NoteRef>{keep.path: keep, remove.path: remove};
  for (var i = 0; i < count; i++) {
    final path = 'work/notes/n$i.typ';
    final note = NoteRef(
      id: 'n$i',
      path: path,
      title: 'Note $i',
      kind: 'note',
      outgoingLinks: const ['keep'],
    );
    notes[path] = note;
    await _writeFixtureText(
      storage,
      path,
      replaceNoteHeader(
        'Reference to @remove.\n',
        NoteMetadataDraft(id: 'n$i', title: 'Note $i'),
      ),
    );
  }
  return VaultIndex(
    notesByPath: notes,
    backlinksByTarget: {
      'work/notes/keep.typ': [
        for (var i = 0; i < count; i++) 'work/notes/n$i.typ',
      ],
    },
    tasks: const [],
  );
}

Future<void> _writeFixtureText(VaultStorage storage, String path, String text) {
  if (storage is _MeasuredSafStorage) {
    return AndroidTreeVaultStorage.channel.invokeMethod<void>('write', {
      'uri': storage.uri,
      'path': path,
      'bytes': Uint8List.fromList(utf8.encode(text)),
    });
  }
  return storage.writeText(path, text);
}

Future<void> _profileFixture(
  WidgetTester tester,
  VmService service,
  String isolate,
  List<FrameTiming> frames,
  dynamic storage,
  Vault vault,
  VaultIndex index, {
  required String vaultName,
  required int fixtureSize,
}) async {
  final entity = index.notes.first;
  await _profileTimeline(
    tester,
    service,
    isolate,
    frames,
    entity,
    index,
    storage: vaultName,
    fixtureSize: fixtureSize,
  );
  storage.reset();
  final workspace = WorkspaceController(
    taskScheduler: TaskScheduler(),
    reconcileTasks: (_) async {},
  )..vault = vault;
  workspace.index = index;
  await _profileMerge(
    service,
    isolate,
    storage,
    workspace,
    'work/notes/keep.typ',
    'work/notes/remove.typ',
    fixtureSize: fixtureSize,
  );
  workspace.dispose();
}

Future<void> _profileTimeline(
  WidgetTester tester,
  VmService service,
  String isolate,
  List<FrameTiming> frames,
  NoteRef entity,
  VaultIndex index, {
  required String storage,
  required int fixtureSize,
}) async {
  await service.getAllocationProfile(isolate, gc: true);
  final heapBefore = (await service.getMemoryUsage(isolate)).heapUsage!;
  await service.clearCpuSamples(isolate);
  final frameStart = frames.length;
  final watch = Stopwatch()..start();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: EntityTimeline(entity: entity, index: index, onOpenPath: (_) {}),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  watch.stop();
  final cpu = await service.getCpuSamples(isolate, 0, 1 << 62);
  final frameUs =
      frames.skip(frameStart).map((f) => f.totalSpan.inMicroseconds).toList()
        ..sort();
  final heapAfter = (await service.getMemoryUsage(isolate)).heapUsage!;
  // ignore: avoid_print
  print(
    'PF5_TIMELINE storage=$storage fixtureNotes=$fixtureSize entity=${entity.path} '
    'buildMs=${watch.elapsedMilliseconds} cpuSamples=${cpu.samples?.length ?? 0} '
    'cpuPeriodUs=${cpu.samplePeriod} heapBefore=$heapBefore heapAfter=$heapAfter '
    'heapDelta=${heapAfter - heapBefore} frames=${frameUs.length} '
    'frameP50Us=${_percentile(frameUs, .50)} frameP95Us=${_percentile(frameUs, .95)} '
    'frameP99Us=${_percentile(frameUs, .99)} frameMaxUs=${frameUs.isEmpty ? 0 : frameUs.last}',
  );
}

Future<void> _profileMerge(
  VmService service,
  String isolate,
  dynamic storage,
  WorkspaceController workspace,
  String survivor,
  String loser, {
  required int fixtureSize,
}) async {
  await service.getAllocationProfile(isolate, gc: true);
  final heapBefore = (await service.getMemoryUsage(isolate)).heapUsage!;
  await service.clearCpuSamples(isolate);
  storage.reset();
  final watch = Stopwatch()..start();
  var outcome = 'accepted';
  var previewFiles = 0;
  try {
    final preview = await workspace.previewDuplicateMerge(survivor, loser);
    previewFiles = preview.files.length;
  } on StateError catch (error) {
    outcome = 'rejected:${error.message}';
  }
  watch.stop();
  final cpu = await service.getCpuSamples(isolate, 0, 1 << 62);
  await service.getAllocationProfile(isolate, gc: true);
  final heapAfter = (await service.getMemoryUsage(isolate)).heapUsage!;
  // ignore: avoid_print
  print(
    'PF5_MERGE storage=${storage is _MeasuredSafStorage ? 'SAF' : 'app-local'} '
    'fixtureNotes=$fixtureSize candidates=${storage.readCalls} previewFiles=$previewFiles outcome="$outcome" '
    'readBytes=${storage.readBytesTotal} readMs=${storage.readTime.inMilliseconds} '
    'elapsedMs=${watch.elapsedMilliseconds} cpuSamples=${cpu.samples?.length ?? 0} '
    'cpuPeriodUs=${cpu.samplePeriod} heapBefore=$heapBefore heapAfter=$heapAfter '
    'heapDelta=${heapAfter - heapBefore}',
  );
}

int _percentile(List<int> values, double p) =>
    values.isEmpty ? 0 : values[((values.length - 1) * p).round()];
