import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/kind_registry.dart';
import 'package:tylog/settings_path.dart';
import 'package:tylog_core/storage.dart';

void main() {
  late Directory directory;
  late LocalVaultStorage storage;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('tylog_kinds_');
    storage = LocalVaultStorage(directory);
  });
  tearDown(() => directory.delete(recursive: true));

  test(
    'kinds.json round-trip preserves other kinds and unknown properties',
    () async {
      expect(await readKindRegistry(storage), isEmpty);
      await storage.writeText(
        kindsSyncPath,
        jsonEncode({
          'lab': {'icon': 'science', 'label': 'Lab', 'future': 42},
          'person': {'icon': 'school', 'label': 'Professor'},
        }),
      );
      await writeKindRegistryEntry(
        storage,
        'lab',
        icon: 'biotech',
        label: 'Лаборатория',
      );
      final registry = await readKindRegistry(storage);
      expect(registry['lab'], {
        'icon': 'biotech',
        'label': 'Лаборатория',
        'future': 42,
      });
      expect(registry['person'], {'icon': 'school', 'label': 'Professor'});
      expect(jsonDecode(await storage.readText(kindsSyncPath)), registry);
    },
  );

  test(
    'local override is read and written without changing the synced copy',
    () async {
      await storage.writeText(kindsSyncPath, '{}');
      await storage.writeText(localSettingsPath(kindsSyncPath), '{}');
      await writeKindRegistryEntry(
        storage,
        'lab',
        icon: 'science',
        label: 'Lab',
      );
      expect((await readKindRegistry(storage))['lab']['icon'], 'science');
      expect(await storage.readText(kindsSyncPath), '{}');
    },
  );

  test('malformed registry is never overwritten by an edit', () async {
    for (final content in ['{bad', '[]']) {
      await storage.writeText(kindsSyncPath, content);
      await expectLater(
        writeKindRegistryEntry(storage, 'lab', icon: 'science', label: 'Lab'),
        throwsFormatException,
      );
      expect(await storage.readText(kindsSyncPath), content);
    }
  });
}
