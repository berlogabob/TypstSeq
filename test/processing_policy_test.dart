import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/audio/processing_policy.dart';
import 'package:tylog_core/tylog_core.dart';

void main() {
  late Directory dir;
  late LocalVaultStorage storage;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('tylog_policy_');
    storage = LocalVaultStorage(dir);
    addTearDown(() => dir.delete(recursive: true));
  });

  test('missing file means everything off', () async {
    final p = await readAudioPolicy(storage);
    expect(p.transcribe, isFalse);
    expect(p.translate, isFalse);
    expect(p.onTheFly, isFalse);
    expect(p.scheduled, isFalse);
    expect(p.translateTo, ['ru', 'en', 'pt']);
  });

  test('round trip keeps other keys and the worker contract names', () async {
    await storage.createDirectory('_system/settings');
    await storage.writeText(
      processingSettingsPath,
      jsonEncode({'schema': 1, 'other': 7}),
    );
    await writeAudioPolicy(
      storage,
      const AudioPolicy(
        transcribe: true,
        translate: true,
        scheduled: true,
        time: '03:30',
        translateTo: ['ru', 'en', 'pt'],
      ),
    );
    final raw =
        jsonDecode(await storage.readText(processingSettingsPath)) as Map;
    expect(raw['other'], 7);
    expect(raw['audio'], {
      'transcribe': true,
      'translate': true,
      'on_the_fly': false,
      'scheduled': true,
      'time': '03:30',
      'translate_to': ['ru', 'en', 'pt'],
    });
    final back = await readAudioPolicy(storage);
    expect(back.translate, isTrue);
    expect(back.time, '03:30');
    expect(back.translateTo, ['ru', 'en', 'pt']);
  });

  test('language defaults and legacy translation settings', () {
    expect(const AudioPolicy().translateTo, ['ru', 'en', 'pt']);
    for (final json in [
      {},
      {'translate_to': 'bad'},
    ]) {
      final p = AudioPolicy.fromJson(json);
      expect(p.translateTo, ['ru', 'en', 'pt']);
      expect(p.translate, isTrue);
    }
    expect(AudioPolicy.fromJson({'translate_to': []}).translateTo, isEmpty);
    expect(AudioPolicy.fromJson({'translate_to': []}).translate, isFalse);
    expect(
      AudioPolicy.fromJson({
        'translate_to': ['pt'],
      }).translate,
      isTrue,
    );
    final p = AudioPolicy.fromJson({
      'translate': false,
      'translate_to': ['pt'],
    });
    expect(p.translate, isFalse);
    expect(p.copyWith(translate: true).translate, isTrue);
    expect(p.copyWith(transcribe: true).translate, isFalse);
    expect(
      AudioPolicy.fromJson({'translate': true, 'translate_to': []}).translate,
      isTrue,
    );
  });

  test('a bad time falls back to 03:00', () {
    expect(AudioPolicy.fromJson({'time': '25:99'}).time, '03:00');
  });

  test('process-now request is a fresh timestamp each time', () async {
    await requestProcessNow(storage, now: DateTime.utc(2026, 10, 14, 1));
    final a = jsonDecode(await storage.readText(processNowPath)) as Map;
    await requestProcessNow(storage, now: DateTime.utc(2026, 10, 14, 2));
    final b = jsonDecode(await storage.readText(processNowPath)) as Map;
    expect(a['requested_at'], isNot(b['requested_at']));
  });
}
