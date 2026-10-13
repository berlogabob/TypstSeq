import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:tylog_core/tylog_core.dart';

Map<String, Uint8List> archive(Map<String, String> files, {String id = 'p1'}) {
  Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));
  final out = {for (final e in files.entries) e.key: b(e.value)};
  out['manifest.json'] = b(
    jsonEncode({
      'schema': 1,
      'id': id,
      'name': 'P',
      'version': '1',
      'files': [
        for (final e in out.entries)
          {'path': e.key, 'sha256': sha256.convert(e.value).toString()},
      ],
    }),
  );
  // manifest lists itself above only transiently; drop it from the list.
  final m = jsonDecode(utf8.decode(out['manifest.json']!)) as Map;
  (m['files'] as List).removeWhere((f) => (f as Map)['path'] == 'manifest.json');
  out['manifest.json'] = b(jsonEncode(m));
  return out;
}

void main() {
  late Directory dir;
  late LocalVaultStorage storage;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('pack_');
    storage = LocalVaultStorage(dir);
  });
  tearDown(() => dir.delete(recursive: true));

  final files = {
    'notes/1.typ': 'due: "{{due:0}}" next: "{{due:8}}" id {{id}}',
    'assets/a.mp3': 'AUDIO',
  };

  test('install maps paths, resolves tokens across month ends, records', () async {
    final pack = ModulePack.parse(archive(files));
    final r = await installModule(storage, pack, DateTime(2026, 1, 28));
    expect(r.written, hasLength(2));
    expect(
      await storage.readText('projects/p1/1.typ'),
      'due: "2026-01-28" next: "2026-02-05" id p1',
    );
    expect(await storage.readText('assets/modules/p1/a.mp3'), 'AUDIO');
    expect(await storage.exists('_system/modules/p1.json'), isTrue);
  });

  test('reinstall is a no-op; edited files survive; uninstall spares them', () async {
    final pack = ModulePack.parse(archive(files));
    await installModule(storage, pack, DateTime(2026, 1, 1));
    final again = await installModule(storage, pack, DateTime(2026, 1, 1));
    expect(again.written, isEmpty);
    await storage.writeText('projects/p1/1.typ', 'mine');
    final r = await installModule(storage, pack, DateTime(2026, 1, 1));
    expect(r.skipped, ['projects/p1/1.typ']);
    final u = await uninstallModule(storage, 'p1');
    expect(u.written, ['assets/modules/p1/a.mp3']);
    expect(u.skipped, ['projects/p1/1.typ']);
    expect(await storage.readText('projects/p1/1.typ'), 'mine');
    expect(await storage.exists('_system/modules/p1.json'), isFalse);
  });

  test('pre-existing foreign file is never overwritten', () async {
    await storage.writeText('assets/modules/p1/a.mp3', 'THEIRS');
    final r = await installModule(
      storage,
      ModulePack.parse(archive(files)),
      DateTime(2026, 1, 1),
    );
    expect(r.skipped, ['assets/modules/p1/a.mp3']);
    expect(await storage.readText('assets/modules/p1/a.mp3'), 'THEIRS');
  });

  test('parse rejects tampering, traversal, extras and bad ids', () {
    final ok = archive(files);
    final tampered = {...ok, 'assets/a.mp3': Uint8List.fromList([1])};
    expect(() => ModulePack.parse(tampered), throwsFormatException);
    final extra = {...ok, 'notes/evil.typ': Uint8List(1)};
    expect(() => ModulePack.parse(extra), throwsFormatException);
    expect(
      () => ModulePack.parse(archive({'notes/../x.typ': 'x'})),
      throwsFormatException,
    );
    expect(
      () => ModulePack.parse(archive({'other/x.typ': 'x'})),
      throwsFormatException,
    );
    expect(
      () => ModulePack.parse(archive(files, id: 'Bad Id')),
      throwsFormatException,
    );
  });
}
