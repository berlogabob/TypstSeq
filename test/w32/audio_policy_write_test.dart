import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/audio/processing_policy.dart';
import 'package:tylog_core/tylog_core.dart';
import '../support/temp_dir.dart';

class _FailingReadStorage extends LocalVaultStorage {
  _FailingReadStorage(super.root);

  bool failReads = false;

  @override
  Future<String> readText(String path) {
    if (failReads && path.endsWith('processing.json')) {
      throw const FileSystemException('transient read failure');
    }
    return super.readText(path);
  }
}

void main() {
  test(
    'writeAudioPolicy does not overwrite the file when reading it fails',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'tylog_audio_policy_write_',
      );
      addTearDown(() => deleteTempDir(dir));
      final storage = _FailingReadStorage(dir);

      await storage.createDirectory('_system/settings');
      const original = '{"keep":"me","screenshots":{"mode":"watch"}}';
      await storage.writeText('_system/settings/processing.json', original);

      storage.failReads = true;
      await expectLater(
        writeAudioPolicy(storage, const AudioPolicy()),
        throwsA(isA<FileSystemException>()),
      );

      storage.failReads = false;
      expect(
        await storage.readText('_system/settings/processing.json'),
        original,
      );
    },
  );
}
