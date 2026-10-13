import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

Future<int> validate(String note) async {
  final bytes = utf8.encode(note);
  final manifest = utf8.encode(
    jsonEncode({
      'schema': 1,
      'id': 'p',
      'files': [
        {'path': 'notes/a.typ', 'sha256': sha256.convert(bytes).toString()},
      ],
    }),
  );
  final zip = Archive()
    ..addFile(ArchiveFile('manifest.json', manifest.length, manifest))
    ..addFile(ArchiveFile('notes/a.typ', bytes.length, bytes));
  final dir = await Directory.systemTemp.createTemp('pv_');
  addTearDown(() => dir.delete(recursive: true));
  final file = File('${dir.path}/p.tylogpack')
    ..writeAsBytesSync(ZipEncoder().encode(zip));
  final r = await Process.run(Platform.resolvedExecutable, [
    'run',
    'bin/tylog.dart',
    'pack-validate',
    file.path,
  ]);
  return r.exitCode;
}

void main() {
  test(
    'pack-validate accepts a tylog-only note and rejects other imports',
    () async {
      expect(await validate('#import "/_system/tylog.typ" as tylog\nhi'), 0);
      expect(await validate('#import "../course.typ": *\nhi'), 1);
    },
  );
}
