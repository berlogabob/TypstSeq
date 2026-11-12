import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tylog/review_queue.dart';
import 'package:tylog/vault_storage.dart';
import 'package:tylog_core/tylog_core.dart';
import 'package:vm_service/vm_service_io.dart';

class _MeasuredStorage extends LocalVaultStorage {
  _MeasuredStorage(super.root);

  int lists = 0, stats = 0, reads = 0, byteReads = 0, bytesRead = 0;
  int creates = 0, appends = 0, writes = 0;

  void reset() {
    lists = 0;
    stats = 0;
    reads = 0;
    byteReads = 0;
    bytesRead = 0;
    creates = 0;
    appends = 0;
    writes = 0;
  }

  @override
  Future<void> createDirectory(String path) {
    creates++;
    return super.createDirectory(path);
  }

  @override
  Future<Uint8List> readBytes(String path) async {
    byteReads++;
    final bytes = await super.readBytes(path);
    bytesRead += bytes.length;
    return bytes;
  }

  @override
  Future<void> writeBytes(String path, List<int> bytes) {
    writes++;
    return super.writeBytes(path, bytes);
  }

  @override
  Future<void> appendBytes(String path, List<int> bytes) {
    appends++;
    return super.appendBytes(path, bytes);
  }

  @override
  Future<List<VaultStorageEntry>> list({
    String path = '',
    bool recursive = false,
  }) {
    lists++;
    return super.list(path: path, recursive: recursive);
  }

  @override
  Future<VaultStorageEntry?> stat(String path) {
    stats++;
    return super.stat(path);
  }

  @override
  Stream<List<int>> openRead(String path, [int? start, int? end]) {
    reads++;
    return super.openRead(path, start, end).map((bytes) {
      bytesRead += bytes.length;
      return bytes;
    });
  }
}

class _MeasuredSafStorage extends AndroidTreeVaultStorage {
  _MeasuredSafStorage({required super.uri, required super.name});

  int lists = 0, stats = 0, reads = 0, bytesRead = 0, appends = 0;

  @override
  Future<Uint8List> readBytes(String path) async {
    reads++;
    final bytes = await super.readBytes(path);
    bytesRead += bytes.length;
    return bytes;
  }

  @override
  Future<void> appendBytes(String path, List<int> bytes) {
    appends++;
    return super.appendBytes(path, bytes);
  }

  @override
  Future<List<VaultStorageEntry>> list({
    String path = '',
    bool recursive = false,
  }) {
    lists++;
    return super.list(path: path, recursive: recursive);
  }

  @override
  Future<VaultStorageEntry?> stat(String path) {
    stats++;
    return super.stat(path);
  }
}

Future<int?> _dartHeapBytes() async {
  final info = await developer.Service.getInfo();
  final uri = info.serverUri;
  if (uri == null) return null;
  final wsUri = uri.replace(
    scheme: uri.scheme == 'https' ? 'wss' : 'ws',
    path: '${uri.path}ws',
  );
  final service = await vmServiceConnectUri(wsUri.toString());
  try {
    final vm = await service.getVM();
    final isolate = vm.isolates?.firstWhere((i) => i.isSystemIsolate != true);
    if (isolate == null) return null;
    final usage = await service.getMemoryUsage(isolate.id!);
    return usage.heapUsage;
  } finally {
    await service.dispose();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'PF2 Incoming sparse and dense queue profile',
    (tester) async {
      const count = 1000;
      final summary = ActionableSidecarSummary();
      final timings = <FrameTiming>[];
      void collect(List<FrameTiming> sample) => timings.addAll(sample);
      SchedulerBinding.instance.addTimingsCallback(collect);
      addTearDown(
        () => SchedulerBinding.instance.removeTimingsCallback(collect),
      );

      final baselineRss = ProcessInfo.currentRss;
      final baselineHeap = await _dartHeapBytes();

      Future<void> fixture(String density) async {
        final root = await Directory.systemTemp.createTemp(
          'pf2-incoming-$density-',
        );
        addTearDown(() => root.delete(recursive: true));
        final storage = _MeasuredStorage(root);
        await storage.createDirectory('_system/enrich/audio');
        const ocrCount = 100;
        for (var i = 0; i < ocrCount; i++) {
          await storage.createDirectory('ext/fixture-$i');
          await storage.writeText(
            'ext/fixture-$i/rows.jsonl',
            '${jsonEncode({
              'review': true,
              'source_photo_hash': 'photo-$i',
              'fields': {
                'title': {'value': 'OCR proposal $i'},
              },
            })}\n',
          );
        }
        for (var i = 0; i < count; i++) {
          await storage.writeText(
            '_system/enrich/audio/$i.json',
            jsonEncode({
              'note': 'notes/note-$i.typ',
              'items': [
                {'id': 'audio:$i', 'text': 'Proposal $i'},
              ],
            }),
          );
        }
        final fixtureDecisions = [
          for (var i = 0; i < count; i++)
            if (density == 'sparse' && i >= 10)
              Decision(
                at: 'profile',
                device: 'profiletest',
                item: 'audio:$i',
                source: 'audio',
                action: 'rejected',
              ),
        ];
        if (fixtureDecisions.isNotEmpty) {
          await storage.createDirectory(decisionsDir);
          await storage.writeText(
            '$decisionsDir/profiletest.jsonl',
            encodeDecisions(fixtureDecisions),
          );
        }
        storage.reset();
        final decisionLoadWatch = Stopwatch()..start();
        final decisions = await loadDecisions(storage);
        decisionLoadWatch.stop();
        final decisionLoadOps = (
          lists: storage.lists,
          byteReads: storage.byteReads,
          bytes: storage.bytesRead,
        );
        storage.reset();
        final firstWatch = Stopwatch()..start();
        final first = await loadAudioProposals(
          storage,
          decisions,
          summary: summary,
        );
        firstWatch.stop();
        final ocrWatch = Stopwatch()..start();
        final ocrFirst = await loadOcrReviewRows(
          storage,
          [for (var i = 0; i < ocrCount; i++) 'fixture-$i'],
          decisions,
          summary: summary,
        );
        ocrWatch.stop();
        final firstOps = (
          lists: storage.lists,
          stats: storage.stats,
          reads: storage.reads,
          bytes: storage.bytesRead,
        );
        storage.reset();
        final nextWatch = Stopwatch()..start();
        final older = await loadAudioProposals(
          storage,
          decisions,
          offset: 20,
          summary: summary,
        );
        nextWatch.stop();
        final olderOps = (
          lists: storage.lists,
          stats: storage.stats,
          reads: storage.reads,
          bytes: storage.bytesRead,
        );
        final newDecision = first.isEmpty
            ? null
            : Decision(
                at: 'profile',
                device: 'profiletest',
                item: first.first.id,
                source: 'audio',
                action: 'accepted',
              );
        final ocrDecision = Decision(
          at: 'profile',
          device: 'profiletest',
          item: ocrFirst.first.id,
          source: 'ocr',
          action: 'accepted',
        );
        if (newDecision != null) {
          await storage.createDirectory(decisionsDir);
          await storage.appendBytes(
            '$decisionsDir/profiletest.jsonl',
            utf8.encode(encodeDecisions([newDecision])),
          );
        }
        await storage.appendBytes(
          '$decisionsDir/profiletest.jsonl',
          utf8.encode(encodeDecisions([ocrDecision])),
        );
        final decisionAppendOps = (
          creates: storage.creates,
          appends: storage.appends,
          writes: storage.writes,
          byteReads: storage.byteReads,
        );
        final decided = [...decisions, ?newDecision];
        storage.reset();
        final decisionWatch = Stopwatch()..start();
        final afterDecision = await loadAudioProposals(
          storage,
          decided,
          summary: summary,
        );
        decisionWatch.stop();
        final afterOcrDecision = await loadOcrReviewRows(
          storage,
          [for (var i = 0; i < ocrCount; i++) 'fixture-$i'],
          [...decisions, ocrDecision],
          summary: summary,
        );
        expect(first, hasLength(density == 'sparse' ? 10 : 20));
        expect(older, hasLength(density == 'sparse' ? 0 : 20));
        expect(afterDecision, hasLength(density == 'sparse' ? 9 : 20));
        expect(ocrFirst, hasLength(20));
        expect(afterOcrDecision, hasLength(20));

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ListView.builder(
                itemCount: first.length + ocrFirst.length,
                itemBuilder: (_, index) => ListTile(
                  title: Text(
                    index < first.length
                        ? first[index].text
                        : ocrFirst[index - first.length].fields,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final heap = await _dartHeapBytes();
        expect(heap, isNotNull);
        // ignore: avoid_print
        print(
          'PF2_INCOMING density=$density audioFiles=$count ocrMounts=$ocrCount visible=${first.length} ocrVisible=${ocrFirst.length} older=${older.length} afterDecision=${afterDecision.length} ocrAfterDecision=${afterOcrDecision.length} decisionLoadMs=${decisionLoadWatch.elapsedMilliseconds} decisionLoadOps=$decisionLoadOps audioFirstMs=${firstWatch.elapsedMilliseconds} ocrFirstMs=${ocrWatch.elapsedMilliseconds} olderMs=${nextWatch.elapsedMilliseconds} decisionMs=${decisionWatch.elapsedMilliseconds} firstOps=$firstOps olderOps=$olderOps decisionAppendOps=$decisionAppendOps decisionRefreshOps=(lists:${storage.lists},reads:${storage.reads},bytes:${storage.bytesRead}) rssBytes=${ProcessInfo.currentRss} rssDelta=${ProcessInfo.currentRss - baselineRss} dartHeapBytes=$heap heapDelta=${heap == null || baselineHeap == null ? null : heap - baselineHeap}',
        );
      }

      await fixture('sparse');
      await fixture('dense');
      // FrameTiming is captured by Flutter's scheduler while each queue page is rendered.
      // ignore: avoid_print
      print(
        'PF2_INCOMING_FRAMES ${timings.length} ${timings.map((t) => t.totalSpan.inMicroseconds).toList()}',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
    skip: const bool.fromEnvironment('PF2_SAF_ONLY'),
  );

  testWidgets('PF2 Incoming SAF-backed queue profile', (tester) async {
    final selection = await AndroidTreeVaultStorage.pick();
    expect(
      selection,
      isNotNull,
      reason: 'select the dedicated empty PF2 fixture folder in Downloads',
    );
    final storage = _MeasuredSafStorage(
      uri: selection!.uri,
      name: selection.name,
    );
    await storage.persistAccess();
    expect(await storage.hasAccess(), isTrue);
    const audioCount = 50;
    const ocrCount = 25;
    addTearDown(() async {
      for (final path in [
        for (var i = 0; i < audioCount; i++) '_system/enrich/audio/pf2-$i.json',
        'ext/pf2/rows.jsonl',
        '$decisionsDir/profiletest.jsonl',
      ]) {
        try {
          await storage.delete(path);
        } catch (_) {}
      }
      for (final path in [
        'ext/pf2',
        'ext',
        '_system/enrich/audio',
        '_system/enrich',
        decisionsDir,
        '_system',
      ]) {
        try {
          await storage.delete(path);
        } catch (_) {}
      }
    });
    await storage.createDirectory('_system/enrich/audio');
    await storage.createDirectory('ext/pf2');
    for (var i = 0; i < audioCount; i++) {
      await storage.writeText(
        '_system/enrich/audio/pf2-$i.json',
        jsonEncode({
          'note': 'notes/pf2-$i.typ',
          'items': [
            {'id': 'pf2-audio:$i', 'text': 'PF2 fixture proposal $i'},
          ],
        }),
      );
    }
    await storage.writeText(
      'ext/pf2/rows.jsonl',
      [
        for (var i = 0; i < ocrCount; i++)
          jsonEncode({
            'review': true,
            'source_photo_hash': 'pf2-photo-$i',
            'fields': {
              'title': {'value': 'PF2 OCR $i'},
            },
          }),
      ].join('\n'),
    );
    storage.reads = 0;
    storage.bytesRead = 0;
    storage.lists = 0;
    storage.stats = 0;
    final frames = <FrameTiming>[];
    void collect(List<FrameTiming> sample) => frames.addAll(sample);
    SchedulerBinding.instance.addTimingsCallback(collect);
    addTearDown(() => SchedulerBinding.instance.removeTimingsCallback(collect));
    final summary = ActionableSidecarSummary();
    final baselineHeap = await _dartHeapBytes();
    final decisions = await loadDecisions(storage);
    final loadWatch = Stopwatch()..start();
    final audio = await loadAudioProposals(
      storage,
      decisions,
      limit: 20,
      summary: summary,
    );
    final ocr = await loadOcrReviewRows(
      storage,
      const ['pf2'],
      decisions,
      limit: 20,
      summary: summary,
    );
    loadWatch.stop();
    final firstOps = (
      lists: storage.lists,
      stats: storage.stats,
      reads: storage.reads,
      bytes: storage.bytesRead,
    );
    storage.lists = 0;
    storage.stats = 0;
    storage.reads = 0;
    storage.bytesRead = 0;
    final olderWatch = Stopwatch()..start();
    final older = await loadAudioProposals(
      storage,
      decisions,
      offset: 20,
      summary: summary,
    );
    olderWatch.stop();
    final decision = Decision(
      at: DateTime.now().toIso8601String(),
      device: 'profiletest',
      item: audio.first.id,
      source: 'audio',
      action: 'accepted',
    );
    await storage.createDirectory(decisionsDir);
    await storage.appendBytes(
      '$decisionsDir/profiletest.jsonl',
      utf8.encode(encodeDecisions([decision])),
    );
    final afterDecision = await loadAudioProposals(storage, [
      ...decisions,
      decision,
    ], summary: summary);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView.builder(
            itemCount: audio.length + ocr.length,
            itemBuilder: (_, i) => ListTile(
              title: Text(
                i < audio.length ? audio[i].text : ocr[i - audio.length].fields,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final heap = await _dartHeapBytes();
    expect(audio, hasLength(20));
    expect(ocr, hasLength(20));
    expect(older, hasLength(20));
    expect(afterDecision, hasLength(20));
    expect(heap, isNotNull);
    // ignore: avoid_print
    print(
      'PF2_SAF fixture=$selection audioFiles=$audioCount ocrRows=$ocrCount visible=${audio.length + ocr.length} older=${older.length} afterDecision=${afterDecision.length} loadMs=${loadWatch.elapsedMilliseconds} loadOps=$firstOps olderMs=${olderWatch.elapsedMilliseconds} olderOps=(lists:${storage.lists},stats:${storage.stats},reads:${storage.reads},bytes:${storage.bytesRead}) appends=${storage.appends} heapDelta=${baselineHeap == null ? null : heap! - baselineHeap} frameUs=${frames.map((f) => f.totalSpan.inMicroseconds).toList()}',
    );
  }, timeout: const Timeout(Duration(minutes: 5)));
}
