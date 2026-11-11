import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:tylog/ai/ai_settings.dart';
import 'package:tylog_core/tylog_core.dart';
import '../support/temp_dir.dart';

class _FailingReadStorage extends LocalVaultStorage {
  _FailingReadStorage(super.root);

  bool failReads = false;

  @override
  Future<String> readText(String path) {
    if (failReads && path.endsWith('ai.json')) {
      throw const FileSystemException('transient read failure');
    }
    return super.readText(path);
  }
}

void main() {
  test(
    'writeAiSettings does not overwrite the file when reading it fails',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final dir = await Directory.systemTemp.createTemp('tylog_ai_write_');
      addTearDown(() => deleteTempDir(dir));
      final storage = _FailingReadStorage(dir);

      await storage.createDirectory('_system/settings');
      const original = '{"keep":"me","tasks":{"enrich":{"model":"x"}}}';
      await storage.writeText('_system/settings/ai.json', original);

      storage.failReads = true;
      await expectLater(
        writeAiSettings(storage, const AiSettings()),
        throwsA(isA<FileSystemException>()),
      );

      storage.failReads = false;
      expect(await storage.readText('_system/settings/ai.json'), original);
    },
  );
}
