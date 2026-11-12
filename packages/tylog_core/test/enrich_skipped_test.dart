import 'dart:io';

import 'package:test/test.dart';
import 'package:tylog_core/tylog_core.dart';

void main() {
  late Directory dir;
  late VaultStorage storage;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('enrich-skipped-');
    storage = LocalVaultStorage(dir);
  });
  tearDown(() async => dir.delete(recursive: true));

  test('persists per device and loads afresh', () async {
    final skipped = EnrichSkipped()..skip('daily/a.typ', 'line|suggestion');
    await storage.writeText(
      '$enrichSkippedDir/device.json',
      skipped.serialize(),
    );
    expect((await EnrichSkipped.load(storage, 'device')).notes, {
      'daily/a.typ': {'line|suggestion'},
    });
    expect((await EnrichSkipped.load(storage, 'other')).notes, isEmpty);
  });

  test('pruning lapses changed cards and preserves valid ones', () async {
    final skipped = EnrichSkipped()
      ..skip('a', 'old')
      ..skip('a', 'unchanged');
    expect(skipped.prune('a', {'new', 'unchanged'}), isTrue);
    await storage.writeText(
      '$enrichSkippedDir/device.json',
      skipped.serialize(),
    );
    final loaded = await EnrichSkipped.load(storage, 'device');
    expect(loaded.notes['a'], {'unchanged'});
    expect(loaded.prune('a', {}), isTrue);
    expect(loaded.notes, isEmpty);
  });

  test('missing or corrupt data is ignored', () async {
    expect((await EnrichSkipped.load(storage, 'device')).notes, isEmpty);
    for (final bad in ['{', '{"a":[1]}', '{"a":"key"}']) {
      await storage.writeText('$enrichSkippedDir/device.json', bad);
      expect((await EnrichSkipped.load(storage, 'device')).notes, isEmpty);
    }
  });

  test('caps keys and notes, evicting oldest', () async {
    final skipped = EnrichSkipped();
    for (var i = 0; i < 201; i++) {
      skipped.skip('note', '$i');
    }
    expect(skipped.notes['note']!.length, 200);
    expect(skipped.notes['note'], isNot(contains('0')));
    for (var i = 0; i < 500; i++) {
      skipped.skip('note$i', 'key');
    }
    expect(skipped.notes.length, 500);
    expect(skipped.notes, isNot(contains('note')));
    await storage.writeText(
      '$enrichSkippedDir/device.json',
      skipped.serialize(),
    );
    expect((await EnrichSkipped.load(storage, 'device')).notes.length, 500);
  });
}
