import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/metadata_lines.dart';
import 'package:tylog/models.dart';

const _iade = NoteRef(
  id: '20260715-001621-iade',
  path: 'notes/iade.typ',
  title: 'IADE',
  outgoingLinks: [],
);

void main() {
  const fernando = NoteRef(
    id: 'fm',
    path: 'notes/fm.typ',
    title: 'Fernando Marson',
    kind: 'person',
    aliases: ['FM', 'Marson'],
    tags: ['person', 'thesis'],
    outgoingLinks: [],
    properties: {
      'email': 'fm@iade.pt',
      'part_of': ['20260715-001621-iade'],
      'keywords': ['a', 'b'],
    },
  );

  test('a note reads as key:: lines, parents by title', () {
    expect(
      metadataLines(fernando, [_iade]),
      'alias:: FM, Marson\n'
      'tags:: thesis\n'
      'part of:: IADE\n'
      'email:: fm@iade.pt',
    );
  });

  test('lines write back aliases, tags, parents by id and text properties', () {
    final draft = applyMetadataLines(
      fernando,
      'Alias:: Marson, Fernando\n'
      'tags:: thesis, supervisor\n'
      'Part of:: IADE, UNIDCOM\n'
      'Work:: emerging technology\n'
      'not a property line\n',
      [_iade],
    );
    expect(draft.aliases, ['Marson', 'Fernando']);
    expect(draft.tags, ['thesis', 'supervisor']);
    expect(draft.properties['part_of'], ['20260715-001621-iade', 'UNIDCOM']);
    expect(draft.properties['work'], 'emerging technology');
    expect(draft.properties.containsKey('email'), isFalse, reason: 'line removed');
    expect(draft.properties['keywords'], ['a', 'b'], reason: 'non-text kept');
    expect(draft.title, 'Fernando Marson');
    expect(draft.kind, 'person');
  });

  test('no part of line removes parents', () {
    final draft = applyMetadataLines(fernando, 'alias:: FM', [_iade]);
    expect(draft.properties.containsKey('part_of'), isFalse);
    expect(draft.tags, isEmpty);
  });
}
