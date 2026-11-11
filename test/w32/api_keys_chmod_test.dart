import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/ai/api_keys.dart';
import '../support/temp_dir.dart';

void main() {
  test('mirrorWorkerKey writes nothing when chmod fails', () async {
    final home = await Directory.systemTemp.createTemp('keys-home-');
    addTearDown(() => deleteTempDir(home));
    await expectLater(
      mirrorWorkerKey(
        'studio',
        'sk-secret',
        home: home.path,
        runProcess: (exe, args) async => ProcessResult(0, 1, '', 'denied'),
      ),
      throwsA(isA<ProcessException>()),
    );
    expect(File('${home.path}/.tylog/keys.json').existsSync(), isFalse);
    final tylog = Directory('${home.path}/.tylog');
    if (await tylog.exists()) {
      for (final entity in tylog.listSync(recursive: true)) {
        if (entity is File) {
          expect(entity.readAsStringSync(), isNot(contains('sk-secret')));
        }
      }
    }
  }, skip: Platform.isWindows ? 'POSIX file modes' : false);
}
