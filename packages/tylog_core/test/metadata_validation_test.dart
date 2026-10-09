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

  test('pre-validation cached metadata is checked again', () async {
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
  });

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
