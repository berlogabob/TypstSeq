import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog_core/tylog_core.dart';

void main() {
  late Directory dir;
  late LocalVaultStorage storage;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('installed_modules_');
    storage = LocalVaultStorage(dir);
  });
  tearDown(() => dir.delete(recursive: true));

  test(
    'lists module records with legacy fallbacks and ignores other entries',
    () async {
      expect(await listInstalledModules(storage), isEmpty);
      await storage.writeText(moduleRecordPath('legacy'), '{"files":{}}');
      await storage.writeText(
        moduleRecordPath('course'),
        jsonEncode({
          'id': 'course',
          'name': 'My course',
          'start': '2026-11-02',
          'files': {},
        }),
      );
      await storage.writeText('_system/modules/readme.txt', 'Not a record');
      await storage.writeText('_system/modules/nested/ignored.json', '{}');
      await storage.writeText('_system/other.json', '{}');

      final modules = await listInstalledModules(storage);
      expect(modules.map((m) => m.id), ['course', 'legacy']);
      expect(modules.first.name, 'My course');
      expect(modules.first.start, DateTime(2026, 11, 2));
      expect(modules.last.name, 'legacy');
      expect(modules.last.start, isNull);
    },
  );

  test(
    'install, update, reschedule and uninstall keep the listing current',
    () async {
      ModulePack pack(String name) => ModulePack.parse({
        'manifest.json': Uint8List.fromList(
          utf8.encode(
            jsonEncode({
              'schema': 1,
              'id': 'course',
              'name': name,
              'files': [],
            }),
          ),
        ),
      });

      await installModule(storage, pack('Course'), DateTime(2026, 11, 2));
      var module = (await listInstalledModules(storage)).single;
      expect(module.name, 'Course');
      expect(module.start, DateTime(2026, 11, 2));

      await installModule(
        storage,
        pack('Updated course'),
        DateTime(2026, 12, 1),
      );
      module = (await listInstalledModules(storage)).single;
      expect(module.name, 'Updated course');
      expect(module.start, DateTime(2026, 12, 1));

      await rescheduleModule(
        storage,
        module.id,
        DateTime(2027, 1, 3),
        module.start!,
      );
      module = (await listInstalledModules(storage)).single;
      expect(module.start, DateTime(2027, 1, 3));
      expect(module.name, 'Updated course');

      await uninstallModule(storage, module.id);
      expect(await listInstalledModules(storage), isEmpty);
    },
  );
}
