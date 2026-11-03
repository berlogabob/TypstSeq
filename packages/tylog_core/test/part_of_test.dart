import 'dart:io';

import 'package:test/test.dart';
import 'package:tylog_core/tylog_core.dart';

class _Inspector implements TypstInspector {
  @override
  Future<List<TypstMetadataRecord>> inspect(TypstDocumentInput input) async => [
    const TypstMetadataRecord(
      label: '<tylog-note>',
      value: {
        'schema': 1,
        'entity': 'note',
        'id': 'person',
        'title': 'Person',
        'kind': 'person',
        'project': 'legacy',
        'properties': {
          'part_of': ['lab', 'lab'],
        },
      },
    ),
  ];
}

void main() {
  test('project is an entity kind and remains standard', () {
    expect(entityNoteKinds, contains('project'));
    expect(structuralNoteKinds, isNot(contains('project')));
    expect(standardNoteKinds, contains('project'));
  });

  for (final (value, project, expected) in [
    ('("lab", "university", "lab",)', '"lab"', ['lab', 'university']),
    ('"lab"', '"legacy"', ['lab', 'legacy']),
    ('()', '"legacy"', ['legacy']),
    ('()', '""', <String>[]),
    ('()', 'none', <String>[]),
  ]) {
    test('fallback part_of $value with project $project', () {
      final note = scanNote(
        'notes/person.typ',
        '#show: tylog.note.with(id: "person", title: "Person", '
            'kind: "person", project: $project, properties: (part_of: $value,))',
      );
      expect(note.partOf, expected);
    });
  }

  test('query and old cached query derive the same parents', () async {
    final root = await Directory.systemTemp.createTemp('tylog-part-of');
    addTearDown(() => root.delete(recursive: true));
    final storage = LocalVaultStorage(root);
    await storage.writeText('notes/person.typ', 'Person');
    final index = await scanVaultStorage(storage, inspector: _Inspector());
    final note = index.notes.single;
    expect(note.partOf, ['lab', 'legacy']);
    final old = note.copyWith(partOf: []);
    expect(rederiveNote(old, 'Person', 'new', 0)!.partOf, note.partOf);
  });

  test('partOf defaults, JSON round trip and copyWith', () {
    const note = NoteRef(
      id: 'p',
      path: 'notes/p.typ',
      title: 'P',
      outgoingLinks: [],
      partOf: ['lab', 'university'],
    );
    expect(NoteRef.fromJson(note.toJson()).partOf, note.partOf);
    expect(note.copyWith(title: 'Other').partOf, note.partOf);
    expect(note.copyWith(partOf: []).partOf, isEmpty);
    final old = note.toJson()..remove('partOf');
    expect(NoteRef.fromJson(old).partOf, isEmpty);
  });

  test(
    'children resolve ids first, then titles and aliases without duplicates',
    () {
      const lab = NoteRef(
        id: 'lab',
        path: 'notes/lab.typ',
        title: 'Lab',
        aliases: ['Laboratory'],
        outgoingLinks: [],
      );
      const university = NoteRef(
        id: 'uni',
        path: 'notes/uni.typ',
        title: 'University',
        outgoingLinks: [],
      );
      const collision = NoteRef(
        id: 'other',
        path: 'notes/other.typ',
        title: 'lab',
        outgoingLinks: [],
      );
      const person = NoteRef(
        id: 'person',
        path: 'notes/person.typ',
        title: 'Person',
        kind: 'person',
        outgoingLinks: [],
        partOf: ['lab', 'LABORATORY', 'uNivErSiTy', 'missing'],
      );
      expect(childrenByParent([lab, university, collision, person]), {
        'lab': [person],
        'uni': [person],
      });
    },
  );
}
