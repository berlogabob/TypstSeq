import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/widgets/settings/p2p_snapshot.dart';

void main() {
  test(
    'synthetic folder snapshot verifies and restores into a fresh folder',
    () async {
      final root = await Directory.systemTemp.createTemp('p2p-test-');
      addTearDown(() => root.delete(recursive: true));
      final snapshot = createScratchSnapshot();
      final destination = await restoreScratchSnapshot(snapshot, root);
      expect(
        await File('${destination.path}/notes/welcome.typ').readAsString(),
        contains('scratch'),
      );
      expect(
        await File('${destination.path}/assets/sample.bin').readAsBytes(),
        [0, 1, 2, 255],
      );
      final again = await restoreScratchSnapshot(snapshot, root);
      expect(again.path, isNot(destination.path));
    },
  );

  test('generated scratch folder contains 200 notes and assets', () async {
    final root = await Directory.systemTemp.createTemp('p2p-fixture-');
    addTearDown(() => root.delete(recursive: true));
    final snapshot = await createRepresentativeScratchSnapshot(root);
    final restored = await restoreScratchSnapshot(snapshot, root);
    final notes = await Directory('${restored.path}/notes').list().toList();
    expect(notes.length, 200);
    expect(
      await File('${restored.path}/assets/payload.bin').length(),
      128 * 1024,
    );
  });

  test('rejects tampered or unsafe snapshots before creating files', () async {
    final root = await Directory.systemTemp.createTemp('p2p-test-');
    addTearDown(() => root.delete(recursive: true));
    final snapshot =
        jsonDecode(createScratchSnapshot()) as Map<String, dynamic>;
    final files = snapshot['files'] as List<dynamic>;
    (files.first as Map<String, dynamic>)['path'] = '../escape';
    expect(
      () => restoreScratchSnapshot(jsonEncode(snapshot), root),
      throwsFormatException,
    );
    expect(await root.list().toList(), isEmpty);
    (files.first as Map<String, dynamic>)['path'] = 'safe.typ';
    (files.first as Map<String, dynamic>)['sha256'] = 'wrong';
    expect(
      () => restoreScratchSnapshot(jsonEncode(snapshot), root),
      throwsFormatException,
    );
    expect(await root.list().toList(), isEmpty);
  });
}
