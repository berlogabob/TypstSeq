import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/review_queue.dart';
import 'package:tylog_core/tylog_core.dart';
import 'support/temp_dir.dart';

class _CountingStorage extends LocalVaultStorage {
  _CountingStorage(super.root);
  int sidecarReads = 0;
  int sidecarBytes = 0;

  @override
  Stream<List<int>> openRead(String path, [int? start, int? end]) {
    if (path.startsWith('_system/enrich/audio/')) {
      sidecarReads++;
      sidecarBytes += (end ?? 1024 * 1024) - (start ?? 0);
    }
    return super.openRead(path, start, end);
  }
}

void main() {
  test('Incoming registry lists each review section in display order', () {
    expect(reviewQueueTypes.map((type) => type.label), [
      'Enrich mentions',
      'Tasks and dates',
      'OCR rows',
      'OpenLabTwin bookings',
      'Vault health',
    ]);
  });

  test('health queue reads only the latest dated report', () async {
    final dir = await Directory.systemTemp.createTemp('health-review');
    addTearDown(() => deleteTempDir(dir));
    final storage = LocalVaultStorage(dir);
    await storage.writeText(
      '_system/health/2026-11-03.json',
      '{"issues":[{"path":"notes/old.typ","code":"unreadable"}]}',
    );
    await storage.writeText(
      '_system/health/2026-11-04.json',
      '{"issues":[{"path":"notes/new.typ","code":"missing-note-header"},{"path":"../outside.typ","code":"unreadable"}]}',
    );
    await storage.writeText('_system/health/not-a-date.json', '{"issues":[]}');
    final issues = await loadHealthFindings(storage);
    expect(issues, hasLength(1));
    expect(issues.single.path, 'notes/new.typ');
    expect(issues.single.code, 'missing-note-header');
  });

  test('audio proposals load and decisions hide them', () async {
    final dir = await Directory.systemTemp.createTemp('audio-review');
    addTearDown(() => deleteTempDir(dir));
    final storage = LocalVaultStorage(dir);
    await storage.writeText(
      '_system/enrich/audio/a.json',
      '{"note":"notes/audio.typ","items":[{"id":"audio:abc","text":"Send notes","date":"2026-11-06","kind":"task"}]}',
    );
    final rows = await loadAudioProposals(storage, []);
    expect(rows.single.text, 'Send notes');
    expect(rows.single.note, 'notes/audio.typ');
    final decision = Decision(
      at: 'now',
      device: 'd',
      item: rows.single.id,
      source: 'audio',
      action: 'rejected',
    );
    expect(await loadAudioProposals(storage, [decision]), isEmpty);
  });

  test('screenshot actions are proposals under their own source', () async {
    final dir = await Directory.systemTemp.createTemp('review-shots');
    addTearDown(() => deleteTempDir(dir));
    final storage = _CountingStorage(dir);
    await storage.writeText(
      '_system/enrich/actions/shot-x.json',
      '{"schema":1,"note":"screenshots/2026/11/shot-x.typ","items":[{"id":"shot:shot-x:0","title":"Jantar","text":"Jantar 20:30 · Tomar","kind":"agenda","date":"2026-11-12","time":"20:30","place":"Tomar"}]}',
    );
    await storage.writeText(
      '_system/enrich/actions/bad.json',
      '{"note":"notes/a.typ","items":[{"id":"x","text":"wrong folder"}]}',
    );
    final rows = await loadAudioProposals(storage, [
      Decision(
        at: 'now',
        device: 'd',
        item: 'shot:shot-x:0',
        source: 'audio',
        action: 'rejected',
      ),
    ]);
    final row = rows.single;
    expect(row.source, 'screenshot');
    expect(row.kind, 'agenda');
    expect(row.title, 'Jantar');
    expect((row.date, row.time, row.place), ('2026-11-12', '20:30', 'Tomar'));
    expect(
      await loadAudioProposals(storage, [
        Decision(
          at: 'now',
          device: 'd',
          item: 'shot:shot-x:0',
          source: 'screenshot',
          action: 'accepted',
        ),
      ]),
      isEmpty,
    );
  });

  test(
    'actionable sidecar summary reuses unchanged reads and invalidates edits',
    () async {
      final dir = await Directory.systemTemp.createTemp('review-summary');
      addTearDown(() => deleteTempDir(dir));
      final storage = _CountingStorage(dir);
      final summary = ActionableSidecarSummary();
      await storage.writeText(
        '_system/enrich/audio/a.json',
        '{"note":"notes/a.typ","items":[{"id":"a1","text":"first"}]}',
      );
      expect((await summary.audio(storage, [])).single.text, 'first');
      final firstReads = storage.sidecarReads;
      await summary.audio(storage, []);
      expect(storage.sidecarReads, firstReads);
      expect(
        await summary.audio(storage, [
          Decision(
            at: 'now',
            device: 'd',
            item: 'a1',
            source: 'audio',
            action: 'accepted',
          ),
        ]),
        isEmpty,
      );
      expect(storage.sidecarReads, firstReads);
      await storage.writeText(
        '_system/enrich/audio/a.json',
        '{"note":"notes/a.typ","items":[{"id":"a2","text":"second"}]}',
      );
      expect((await summary.audio(storage, [])).single.id, 'a2');
      expect(storage.sidecarReads, firstReads + 1);
    },
  );

  test('actionable sidecar reads have a fixed byte ceiling', () async {
    final dir = await Directory.systemTemp.createTemp('review-bound');
    addTearDown(() => deleteTempDir(dir));
    final storage = _CountingStorage(dir);
    final summary = ActionableSidecarSummary();
    await storage.writeText(
      '_system/enrich/audio/large.json',
      '{"note":"notes/a.typ","items":[]}${' ' * (1024 * 1024 + 500)}',
    );
    expect(await summary.audio(storage, []), isEmpty);
    expect(storage.sidecarBytes, 1024 * 1024);
  });

  test('audio and OCR sidecars return bounded pages in stable order', () async {
    final dir = await Directory.systemTemp.createTemp('review-pages');
    addTearDown(() => deleteTempDir(dir));
    final storage = LocalVaultStorage(dir);
    await storage.writeText(
      '_system/enrich/audio/a.json',
      jsonEncode({
        'note': 'notes/audio.typ',
        'items': [
          for (var i = 0; i < 23; i++) {'id': 'audio:$i', 'text': 'item $i'},
        ],
      }),
    );
    await storage.writeText(
      'ext/forms/rows.jsonl',
      [
        for (var i = 0; i < 23; i++)
          jsonEncode({
            'source_photo_hash': 'hash$i',
            'review': true,
            'fields': {'name': 'row $i'},
          }),
      ].join('\n'),
    );

    final audioFirst = await loadAudioProposals(storage, [], limit: 20);
    final audioNext = await loadAudioProposals(storage, [], offset: 20);
    final ocrFirst = await loadOcrReviewRows(storage, ['forms'], [], limit: 20);
    final ocrNext = await loadOcrReviewRows(storage, ['forms'], [], offset: 20);
    expect(audioFirst, hasLength(20));
    expect(audioNext, hasLength(3));
    expect(ocrFirst, hasLength(20));
    expect(ocrNext, hasLength(3));
    expect(audioFirst.last.id, 'audio:19');
    expect(audioNext.first.id, 'audio:20');
    expect(ocrFirst.last.id, 'ocr:forms:hash19');
    expect(ocrNext.first.id, 'ocr:forms:hash20');
  });
  test(
    'OCR review rows are loaded from mounts and ledger decisions hide them',
    () async {
      final dir = await Directory.systemTemp.createTemp('review-queue');
      addTearDown(() => deleteTempDir(dir));
      final storage = LocalVaultStorage(dir);
      await storage.writeText(
        'ext/forms/manifest.json',
        '{"template_id":"student","created":"2026-11-04T00:00:00Z"}',
      );
      await storage.writeText(
        'ext/forms/rows.jsonl',
        '{"source_photo_hash":"abc","review":true,"fields":{"name":{"value":"Ana","confidence":0.4,"crop":"crops/1.png"}}}\n{"source_photo_hash":"def","review":false,"fields":{}}\ninvalid\n',
      );
      final rows = await loadOcrReviewRows(storage, ['forms'], []);
      expect(rows, hasLength(1));
      expect(rows.single.fields, contains('Ana'));
      final decision = Decision(
        at: '2026-11-04',
        device: 'd',
        item: rows.single.id,
        source: 'ocr',
        action: 'accepted',
      );
      expect(await loadOcrReviewRows(storage, ['forms'], [decision]), isEmpty);
    },
  );
  test('review rows work in a mounted dataset without a manifest', () async {
    final root = await Directory.systemTemp.createTemp('review-mount');
    addTearDown(() => deleteTempDir(root));
    final main = LocalVaultStorage(Directory('${root.path}/vault'));
    final dataset = LocalVaultStorage(Directory('${root.path}/dataset'));
    await dataset.writeText(
      'rows.jsonl',
      '{"source_photo_hash":"abc","review":true,"fields":{"name":"Ana"}}\n',
    );
    final storage = CompositeVaultStorage(main, {'forms': dataset});
    final rows = await loadOcrReviewRows(storage, ['forms'], []);
    expect(rows.single.dataset, 'forms');
    expect(rows.single.fields, contains('Ana'));
    final decision = Decision(
      at: '2026-11-04',
      device: 'd',
      item: rows.single.id,
      source: 'ocr',
      action: 'rejected',
    );
    expect(await loadOcrReviewRows(storage, ['forms'], [decision]), isEmpty);
  });
}
