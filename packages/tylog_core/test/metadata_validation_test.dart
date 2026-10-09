import 'dart:io';
import 'package:test/test.dart';
import 'package:tylog_core/tylog_core.dart';

class _Inspector implements TypstInspector {
  _Inspector(this.records);
  final List<TypstMetadataRecord> records;
  @override
  Future<List<TypstMetadataRecord>> inspect(TypstDocumentInput input) async =>
      records;
}

void main() {
  late Directory dir;
  late LocalVaultStorage storage;
  setUp(() async {
    dir = await Directory('.dart_tool').createTemp('metadata-validation-');
    storage = LocalVaultStorage(dir);
    await storage.writeText('notes/a.typ', 'Body');
  });
  tearDown(() => dir.delete(recursive: true));

  test('actual attachment helper query produces validated metadata', () async {
    if (Process.runSync('which', ['typst']).exitCode != 0) {
      markTestSkipped('typst not on PATH');
      return;
    }
    final repo = Directory.current.path.endsWith('packages/tylog_core')
        ? Directory.current.parent.parent
        : Directory.current;
    await storage.writeText(
      '_system/tylog.typ',
      File('${repo.path}/typst/tylog/lib.typ').readAsStringSync(),
    );
    await storage.writeText('assets/file.txt', 'asset');
    await storage.writeText(
      'notes/a.typ',
      '#import "/_system/tylog.typ" as tylog\n'
          '#show: tylog.note.with(id: "a", title: "A")\n'
          '#tylog.attachment("/assets/file.txt")[File]',
    );
    final index = await scanVaultStorage(
      storage,
      inspector: CliTypstInspector(dir),
    );
    expect(index.notes.single.metadataSource, 'typst-query');
    expect(index.notes.single.attachments.single.path, 'assets/file.txt');
    final report = await validatePkmsStorage(storage, index);
    expect(
      report.problems.where((p) => p.severity == PkmsSeverity.error),
      isEmpty,
    );
  });

  test('attachment lookup paths become safe metadata paths', () async {
    await storage.writeText('assets/file.txt', 'asset');
    const source =
        '#show: tylog.note.with(id: "a", title: "A")\n'
        '#tylog.attachment("/assets/file.txt")[File]';
    await storage.writeText('notes/a.typ', source);
    for (final inspector in [
      null,
      _Inspector(const [
        TypstMetadataRecord(
          label: '<tylog-note>',
          value: {'id': 'a', 'title': 'A'},
        ),
        TypstMetadataRecord(
          label: '<tylog-attachment>',
          value: {'path': '/assets/file.txt', 'kind': 'file'},
        ),
      ]),
    ]) {
      final index = await scanVaultStorage(storage, inspector: inspector);
      expect(index.notes.single.attachments.single.path, 'assets/file.txt');
      final report = await validatePkmsStorage(storage, index);
      expect(report.count('unsafe-attachment-path'), 0);
      expect(report.count('missing-attachment'), 0);
      final legacy = index.toJson();
      legacy['version'] = kVaultIndexVersion - 1;
      final notes = legacy['notes'] as List;
      ((notes.single as Map)['attachments'] as List).single['path'] =
          '/assets/file.txt';
      final restored = VaultIndex.fromJson(legacy);
      expect(restored.notes.single.attachments.single.path, 'assets/file.txt');
      final cached = await scanVaultStorage(storage, previous: restored);
      expect(cached.notes.single.attachments.single.path, 'assets/file.txt');
    }
    for (final path in [
      r'assets\file.txt',
      'assets/../file.txt',
      '//assets/file.txt',
      'assets//file.txt',
      'assets/./file.txt',
      'C:/file.txt',
    ]) {
      expect(isSafeVaultPath(path), isFalse, reason: path);
    }
  });

  test(
    'pre-validation cached metadata is checked again',
    () async {
      final inspector = _Inspector(const [
        TypstMetadataRecord(
          label: '<tylog-note>',
          value: {'schema': 1, 'entity': 'note', 'id': 'a'},
        ),
      ]);
      final original = await scanVaultStorage(storage, inspector: inspector);
      final old = VaultIndex(
        version: 11,
        queryVersion: 1,
        notesByPath: original.notesByPath,
        backlinksByTarget: original.backlinksByTarget,
      );
      final checked = await scanVaultStorage(
        storage,
        inspector: inspector,
        previous: old,
      );
      expect(
        checked.problems.where(
          (p) => p.code == 'invalid-metadata-required-field',
        ),
        hasLength(2),
      );
    },
    skip:
        "kVaultQueryVersion stays 1 in 0.12.3: a bump recompiles every note; re-enable with the bump",
  );

  test('task dates reject malformed and impossible ISO values', () async {
    for (final value in [
      'banana',
      '2026-02-30',
      '2026-13-01',
      '2026-10-09T25:00',
      '2026-10-09T12:60',
      '2026-10-09T12:00:60',
      '2026-10-09T12:00+25:00',
    ]) {
      final index = VaultIndex(
        notesByPath: const {},
        backlinksByTarget: const {},
        tasks: [
          TaskRef(
            id: 't',
            notePath: 'notes/a.typ',
            text: 'Call',
            due: value,
            scheduled: value,
            remind: value,
          ),
        ],
      );
      final report = await validatePkmsStorage(storage, index);
      expect(report.count('invalid-task-date'), 3, reason: value);
    }
    for (final value in [
      null,
      '2024-02-29',
      '2026-10-09T12:00',
      '2026-10-09T12:00:01.123Z',
      '2026-10-09T12:00:01+02:00',
    ]) {
      final report = await validatePkmsStorage(
        storage,
        VaultIndex(
          notesByPath: const {},
          backlinksByTarget: const {},
          tasks: [
            TaskRef(
              id: 't',
              notePath: 'notes/a.typ',
              text: 'Call',
              due: value,
              scheduled: value,
              remind: value,
            ),
          ],
        ),
      );
      expect(report.count('invalid-task-date'), 0, reason: '$value');
    }
  });

  test(
    'V1 missing required fields report errors while legacy defaults remain',
    () async {
      for (final v1 in [true, false]) {
        final index = await scanVaultStorage(
          storage,
          inspector: _Inspector([
            TypstMetadataRecord(
              label: '<tylog-note>',
              value: {
                if (v1) ...{'schema': 1, 'entity': 'note'},
                'id': 'a',
              },
            ),
            TypstMetadataRecord(
              label: '<tylog-task>',
              value: {
                if (v1) ...{'schema': 1, 'entity': 'task'},
                'id': 't',
                'text': 'Call',
              },
            ),
          ]),
        );
        final report = await validatePkmsStorage(storage, index);
        final errors = report.problems
            .where((p) => p.severity == PkmsSeverity.error)
            .toList();
        if (v1) {
          expect(errors, hasLength(4));
          for (final key in ['title', 'kind', 'status', 'priority']) {
            expect(
              errors.any((p) => p.message.contains(key)),
              isTrue,
              reason: key,
            );
          }
        } else {
          expect(errors, isEmpty);
          expect(index.tasks.single.status, 'todo');
          expect(index.tasks.single.priority, 'normal');
        }
      }
    },
  );

  test(
    'mismatched task envelope reports an error beside a valid note',
    () async {
      final inspector = _Inspector(const [
        TypstMetadataRecord(
          label: '<tylog-note>',
          value: {
            'schema': 1,
            'entity': 'note',
            'id': 'a',
            'title': 'A',
            'kind': 'note',
          },
        ),
        TypstMetadataRecord(
          label: '<tylog-task>',
          value: {
            'schema': 1,
            'entity': 'note',
            'id': 't',
            'text': 'Call',
            'status': 'todo',
            'priority': 'normal',
          },
        ),
      ]);
      final index = await scanVaultStorage(storage, inspector: inspector);
      final report = await validatePkmsStorage(storage, index);
      expect(
        report.problems.where((p) => p.severity == PkmsSeverity.error),
        hasLength(1),
      );
      expect(report.problems.single.subject, 'notes/a.typ');
      expect(report.problems.single.message, contains('task'));
      expect(index.tasks, isEmpty);
      final cached = await scanVaultStorage(
        storage,
        inspector: inspector,
        previous: index,
      );
      expect(
        cached.problems.map((p) => p.toJson()),
        index.problems.map((p) => p.toJson()),
      );
    },
  );
}
