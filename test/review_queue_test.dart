import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/review_queue.dart';
import 'package:tylog_core/tylog_core.dart';

void main() {
  test('Incoming registry lists each review section in display order', () {
    expect(reviewQueueTypes.map((type) => type.label), [
      'Enrich mentions',
      'Audio proposals',
      'OCR rows',
      'OpenLabTwin bookings',
    ]);
  });

  test('audio proposals load and decisions hide them', () async {
    final dir = await Directory.systemTemp.createTemp('audio-review');
    addTearDown(() => dir.delete(recursive: true));
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
  test(
    'OCR review rows are loaded from mounts and ledger decisions hide them',
    () async {
      final dir = await Directory.systemTemp.createTemp('review-queue');
      addTearDown(() => dir.delete(recursive: true));
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
    addTearDown(() => root.delete(recursive: true));
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
