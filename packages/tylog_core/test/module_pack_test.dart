import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:tylog_core/tylog_core.dart';

Map<String, Uint8List> archive(
  Map<String, String> files, {
  String id = 'p1',
  Object? unit,
}) {
  Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));
  final out = {for (final e in files.entries) e.key: b(e.value)};
  out['manifest.json'] = b(
    jsonEncode({
      'schema': 1,
      'id': id,
      'name': 'P',
      'version': '1',
      'unit': ?unit,
      'files': [
        for (final e in out.entries)
          {'path': e.key, 'sha256': sha256.convert(e.value).toString()},
      ],
    }),
  );
  // manifest lists itself above only transiently; drop it from the list.
  final m = jsonDecode(utf8.decode(out['manifest.json']!)) as Map;
  (m['files'] as List).removeWhere(
    (f) => (f as Map)['path'] == 'manifest.json',
  );
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

  test('unit defaults to tasks in packs and legacy install records', () async {
    final pack = ModulePack.parse(archive(files));
    expect(pack.unit, 'tasks');
    await installModule(storage, pack, DateTime(2026, 1, 1));
    expect((await listInstalledModules(storage)).single.unit, 'tasks');
    await storage.writeText(moduleRecordPath('p1'), '{"files":{}}');
    expect((await listInstalledModules(storage)).single.unit, 'tasks');
  });

  test('unit survives install, listing, reschedule and upgrade', () async {
    final pack = ModulePack.parse(archive(files, unit: 'lessons'));
    expect(pack.unit, 'lessons');
    await installModule(storage, pack, DateTime(2026, 1, 1));
    final record = jsonDecode(await storage.readText(moduleRecordPath('p1')));
    expect(record['unit'], 'lessons');
    expect((await listInstalledModules(storage)).single.unit, 'lessons');
    await rescheduleModule(
      storage,
      'p1',
      DateTime(2026, 1, 2),
      DateTime(2026, 1, 1),
    );
    expect((await listInstalledModules(storage)).single.unit, 'lessons');
    await installModule(
      storage,
      ModulePack.parse(archive(files, unit: 'exercises')),
      DateTime(2026, 1, 2),
    );
    expect((await listInstalledModules(storage)).single.unit, 'exercises');
  });

  test('unit must be a string', () {
    expect(
      () => ModulePack.parse(archive(files, unit: 72)),
      throwsFormatException,
    );
  });

  test(
    'install maps paths, resolves tokens across month ends, records',
    () async {
      final pack = ModulePack.parse(archive(files));
      final r = await installModule(storage, pack, DateTime(2026, 1, 28));
      expect(r.written, hasLength(2));
      expect(
        await storage.readText('projects/p1/1.typ'),
        'due: "2026-01-28" next: "2026-02-05" id p1',
      );
      expect(await storage.readText('assets/modules/p1/a.mp3'), 'AUDIO');
      expect(await storage.exists('_system/modules/p1.json'), isTrue);
    },
  );

  test(
    'reinstall is a no-op; edited files survive; uninstall spares them',
    () async {
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
    },
  );

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

  test('upgrade deletes obsolete owned files but keeps edited ones', () async {
    await installModule(
      storage,
      ModulePack.parse(
        archive({
          'notes/old.typ': 'old',
          'notes/edited.typ': 'original',
          'assets/old.bin': 'asset',
          'notes/missing.typ': 'missing',
        }),
      ),
      DateTime(2026, 1, 1),
    );
    await storage.writeText('projects/p1/edited.typ', 'mine');
    await storage.delete('projects/p1/missing.typ');
    final result = await installModule(
      storage,
      ModulePack.parse(archive({'notes/new.typ': 'new'})),
      DateTime(2026, 1, 1),
    );
    expect(result.written, [
      'projects/p1/old.typ',
      'assets/modules/p1/old.bin',
      'projects/p1/new.typ',
    ]);
    expect(result.skipped, ['projects/p1/edited.typ']);
    expect(await storage.exists('projects/p1/old.typ'), isFalse);
    expect(await storage.exists('assets/modules/p1/old.bin'), isFalse);
    expect(await storage.readText('projects/p1/edited.typ'), 'mine');
    final record = jsonDecode(await storage.readText(moduleRecordPath('p1')));
    expect((record['files'] as Map).keys, ['projects/p1/new.typ']);
    expect((await uninstallModule(storage, 'p1')).skipped, isEmpty);
    expect(await storage.readText('projects/p1/edited.typ'), 'mine');
  });

  test(
    'reschedule surgically shifts open tasks even in edited notes',
    () async {
      const source = r'''Prose due: "2026-01-28"
#tylog.task(id: "a", text: "due: \"2026-01-28\"", properties: (due: "2026-01-28",), due :  "{{due:0}}", status: "todo")
#tylog.task(id: "b", due: "{{due:8}}", status: "doing")[Body]
#tylog.task(id: "c", due: "{{due:0}}", status: "done")
#tylog.task(id: "d", due: "{{due:0}}", status: "cancelled")
#tylog.task(id: "e", due: none)
#tylog.task(id: "f", due: "2026-02-30")
// #tylog.task(id: "comment", due: "2026-01-28")
`#tylog.task(id: "raw", due: "2026-01-28")`
''';
      final pack = ModulePack.parse(
        archive({
          'notes/1.typ': source,
          'notes/edited.typ': '#tylog.task(id: "x", due: "{{due:0}}")',
          'assets/a.typ': '#tylog.task(id: "asset", due: "2026-01-28")',
        }),
      );
      await installModule(storage, pack, DateTime(2026, 1, 28));
      await storage.writeText(
        'projects/p1/edited.typ',
        '#tylog.task(id: "x", due: "2026-01-28")\nMy edits',
      );
      await storage.writeText(
        'projects/p1/unowned.typ',
        '#tylog.task(id: "foreign", due: "2026-01-28")',
      );
      // Old records without a start field remain readable.
      final recordPath = moduleRecordPath('p1');
      final oldRecord = jsonDecode(await storage.readText(recordPath)) as Map;
      oldRecord.remove('start');
      await storage.writeText(recordPath, jsonEncode(oldRecord));
      final before = await storage.readText('projects/p1/1.typ');
      final result = await rescheduleModule(
        storage,
        'p1',
        DateTime(2026, 2, 5, 1),
        DateTime(2026, 1, 28, 23),
      );
      expect(result.written, ['projects/p1/1.typ', 'projects/p1/edited.typ']);
      expect(result.skipped, isEmpty);
      expect(
        await storage.readText('projects/p1/1.typ'),
        before
            .replaceFirst('due :  "2026-01-28"', 'due :  "2026-02-05"')
            .replaceFirst('due: "2026-02-05"', 'due: "2026-02-13"'),
      );
      expect(
        await storage.readText('projects/p1/edited.typ'),
        '#tylog.task(id: "x", due: "2026-02-05")\nMy edits',
      );
      expect(
        await storage.readText('projects/p1/unowned.typ'),
        '#tylog.task(id: "foreign", due: "2026-01-28")',
      );
      expect(
        await storage.readText('assets/modules/p1/a.typ'),
        '#tylog.task(id: "asset", due: "2026-01-28")',
      );
      final record = jsonDecode(await storage.readText(recordPath));
      expect(record['start'], '2026-02-05');
      for (final path in result.written) {
        expect(record['files'][path], await storage.hash(path));
      }
      await rescheduleModule(
        storage,
        'p1',
        DateTime(2026, 1, 28),
        DateTime(2026, 2, 5),
      );
      expect(await storage.readText('projects/p1/1.typ'), before);
    },
  );

  test('progress counts current module tasks and score properties', () async {
    await storage.writeText('projects/p1/1.typ', r'''
#tylog.task(id: "a", status: "done")
#tylog.task(id: "b", status: "cancelled")
#tylog.task(id: "c", text: "status: \"done\"")
// #tylog.task(id: "comment", status: "done")
`#tylog.task(id: "raw", status: "done")`
score:: 32/40
''');
    await storage.writeText(
      'projects/p1/sub/2.typ',
      '#tylog.task(id: "d", status: "done")\nscore:: 5/10',
    );
    await storage.writeText(
      'projects/p10/other.typ',
      '#tylog.task(id: "other", status: "done")\nscore:: 1/1',
    );
    await storage.writeText(
      'projects/p1/asset.txt',
      '#tylog.task(id: "asset")',
    );
    await storage.writeText(
      moduleRecordPath('p1'),
      jsonEncode({
        'files': {
          'projects/p1/1.typ': '',
          'projects/p1/sub/2.typ': '',
          'projects/p1/asset.txt': '',
        },
      }),
    );
    final progress = await moduleProgress(storage, 'p1');
    expect(progress.total, 4);
    expect(progress.done, 2);
    expect(
      progress.scores,
      unorderedEquals([
        (path: 'projects/p1/1.typ', score: '32/40'),
        (path: 'projects/p1/sub/2.typ', score: '5/10'),
      ]),
    );
    final missing = await moduleProgress(storage, 'missing');
    expect(missing.total, 0);
    expect(missing.done, 0);
    expect(missing.scores, isEmpty);
  });

  test('parse rejects tampering, traversal, extras and bad ids', () {
    final ok = archive(files);
    final tampered = {
      ...ok,
      'assets/a.mp3': Uint8List.fromList([1]),
    };
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
