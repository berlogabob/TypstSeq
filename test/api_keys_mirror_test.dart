import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/ai/api_keys.dart';

void main() {
  test('worker key file mirrors saved keys for the Mac scripts', () async {
    final home = await Directory.systemTemp.createTemp('keys-home-');
    addTearDown(() => home.delete(recursive: true));
    final file = File('${home.path}/.tylog/keys.json');
    await mirrorWorkerKey('studio', 'sk-1', home: home.path);
    await mirrorWorkerKey('other', 'sk-2', home: home.path);
    expect(jsonDecode(file.readAsStringSync()), {
      'studio': 'sk-1',
      'other': 'sk-2',
    });
    expect(file.statSync().modeString(), 'rw-------');
    await mirrorWorkerKey('studio', null, home: home.path);
    expect(jsonDecode(file.readAsStringSync()), {'other': 'sk-2'});
  }, skip: Platform.isWindows ? 'POSIX file modes' : false);
}
