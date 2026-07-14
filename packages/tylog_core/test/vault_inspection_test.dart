import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tylog_core/tylog_core.dart';

void main() {
  test(
    'vault inspection is read-only and distinguishes folder states',
    () async {
      final empty = await Directory.systemTemp.createTemp(
        'tylog_inspect_empty_',
      );
      final valid = await Directory.systemTemp.createTemp(
        'tylog_inspect_valid_',
      );
      final other = await Directory.systemTemp.createTemp(
        'tylog_inspect_other_',
      );
      final broken = await Directory.systemTemp.createTemp(
        'tylog_inspect_broken_',
      );
      addTearDown(() async {
        for (final directory in [empty, valid, other, broken]) {
          await directory.delete(recursive: true);
        }
      });

      await File('${empty.path}/.DS_Store').writeAsString('ignored');
      await Directory('${valid.path}/.tylog').create();
      await File(
        '${valid.path}/.tylog/settings.json',
      ).writeAsString(jsonEncode({'name': 'TyLogVault', 'version': 5}));
      await File('${other.path}/photo.jpg').writeAsBytes([1, 2, 3]);
      await Directory('${broken.path}/.tylog').create();
      await File('${broken.path}/.tylog/settings.json').writeAsString('{bad');

      expect(
        (await inspectVaultStorage(LocalVaultStorage(empty))).kind,
        VaultStorageKind.empty,
      );
      expect(
        (await inspectVaultStorage(LocalVaultStorage(valid))).kind,
        VaultStorageKind.validVault,
      );
      expect(
        (await inspectVaultStorage(LocalVaultStorage(other))).kind,
        VaultStorageKind.nonVault,
      );
      expect(
        (await inspectVaultStorage(LocalVaultStorage(broken))).kind,
        VaultStorageKind.incompatibleVault,
      );

      await expectLater(
        initializeVaultStorage(
          LocalVaultStorage(other),
          managedFiles: const {},
          currentHelper: '',
          legacyHelper: '',
        ),
        throwsStateError,
      );
      expect(await File('${other.path}/photo.jpg').readAsBytes(), [1, 2, 3]);
      expect(await Directory('${other.path}/daily').exists(), isFalse);
    },
  );
}
