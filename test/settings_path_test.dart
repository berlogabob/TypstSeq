import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/ai/ai_settings.dart';
import 'package:tylog/audio/processing_policy.dart';
import 'package:tylog/settings_path.dart';
import 'package:tylog_core/storage.dart';

void main() {
  late Directory dir;
  late LocalVaultStorage storage;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('tylog_settings_');
    storage = LocalVaultStorage(dir);
  });
  tearDown(() => dir.delete(recursive: true));

  for (final path in [
    aiSettingsPath,
    processingSettingsPath,
    '_system/settings/calendars.json',
  ]) {
    test('$path scope round trip preserves whole file bytes', () async {
      const original = '{\n "unknown": "Привет", "other": 7\n}\n';
      const edited = '{"local":true}\n';
      await storage.writeText(path, original);
      expect(await settingsPathFor(storage, path), path);
      await setSettingsDeviceOnly(storage, path, true);
      final local = localSettingsPath(path);
      expect(await settingsPathFor(storage, path), local);
      expect(await storage.readText(local), original);
      expect(await storage.readText(path), original);
      await storage.writeText(local, edited);
      await storage.writeText(path, '{"changed_on_peer":true}');
      await setSettingsDeviceOnly(storage, path, false);
      expect(await storage.readText(path), edited);
      expect(await storage.exists(local), isFalse);
      expect(await settingsPathFor(storage, path), path);
    });
  }

  test(
    'AI and audio readers and writers use local files without merging',
    () async {
      await writeAiSettings(
        storage,
        const AiSettings(
          connections: [
            AiConnection(id: 'shared', url: 'https://shared.example/v1'),
          ],
        ),
      );
      await writeAudioPolicy(storage, const AudioPolicy(transcribe: true));
      final sharedAi = await storage.readText(aiSettingsPath);
      final sharedAudio = await storage.readText(processingSettingsPath);
      await storage.writeText(localSettingsPath(aiSettingsPath), '{bad');
      await storage.writeText(localSettingsPath(processingSettingsPath), '{}');
      expect((await readAudioPolicy(storage)).transcribe, isFalse);
      expect((await readAiSettings(storage)).connections, isEmpty);
      await writeAiSettings(
        storage,
        const AiSettings(
          connections: [
            AiConnection(id: 'local', url: 'http://localhost:1234/v1'),
          ],
        ),
      );
      expect((await readAiSettings(storage)).connections.single.id, 'local');
      await writeAudioPolicy(storage, const AudioPolicy(scheduled: true));
      expect((await readAudioPolicy(storage)).scheduled, isTrue);
      expect(await storage.readText(aiSettingsPath), sharedAi);
      expect(await storage.readText(processingSettingsPath), sharedAudio);
      await storage.delete(localSettingsPath(processingSettingsPath));
      expect((await readAudioPolicy(storage)).transcribe, isTrue);
      await storage.delete(localSettingsPath(aiSettingsPath));
      expect((await readAiSettings(storage)).connections.single.id, 'shared');
    },
  );

  test('enabling local settings before a shared file exists', () async {
    await setSettingsDeviceOnly(storage, aiSettingsPath, true);
    expect(await storage.exists(aiSettingsPath), isFalse);
    expect(await storage.readText(localSettingsPath(aiSettingsPath)), '{}');
  });
}
