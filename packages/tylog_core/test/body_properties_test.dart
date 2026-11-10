import 'package:test/test.dart';
import 'package:tylog_core/tylog_core.dart';

const _header = '''#import "/_system/tylog.typ" as tylog

#show: tylog.note.with(
  id: "fm",
  title: "Fernando Marson",
  kind: "person",
  aliases: ("FernandoMarson",),
  properties: (email: "fm@iade.pt",),
)
''';

void main() {
  test('key:: lines at the top of a page become properties', () {
    final note = scanNote('notes/fm.typ', '''$_header
= Fernando Marson

Alias:: Marson, FM
- Work:: [[IADE]]
Part of:: UNIDCOM, Lab
Linked:: my thesis supervisor, professor of emerging technology
Профессия:: преподаватель
email:: other@example.test

Body text with time:: not a property.
''');
    expect(note.aliases, ['FM', 'FernandoMarson', 'Marson']);
    expect(note.partOf, ['UNIDCOM', 'Lab']);
    expect(note.properties['work'], 'IADE');
    expect(
      note.properties['linked'],
      'my thesis supervisor, professor of emerging technology',
    );
    expect(note.properties['профессия'], 'преподаватель');
    expect(note.properties['email'], 'fm@iade.pt', reason: 'header wins');
    expect(note.properties.containsKey('time'), isFalse);
    expect(note.properties.containsKey('alias'), isFalse);
    expect(note.outgoingLinks, contains('IADE'));
  });

  test('lines after other text are not properties', () {
    final note = scanNote('notes/fm.typ', '''$_header
Some intro.
Work:: IADE
''');
    expect(note.properties.containsKey('work'), isFalse);
  });

  test('legacy tags:: and source:: keep their own meaning', () {
    final note = scanNote('notes/a.typ', '''$_header
tags:: #A #B
source:: [[habr.com]]
''');
    expect(note.properties.containsKey('tags'), isFalse);
    expect(note.properties.containsKey('source'), isFalse);
    expect(note.tags, containsAll(['a', 'b']));
  });

  test('re-derivation drops a removed body property', () {
    const withLine = '$_header\nWork:: IADE\nAlias:: FM\n';
    final first = scanNote('notes/fm.typ', withLine);
    expect(first.properties['work'], 'IADE');
    final cached = first.copyWith(
      queryFacts: {
        'tags': const <String>[],
        'links': const <String>[],
        'dates': const <Object>[],
        'header_properties': {'email': 'fm@iade.pt'},
        'header_aliases': ['FernandoMarson'],
      },
    );
    final again = rederiveNote(cached, '$_header\n', 'f2', 2)!;
    expect(again.properties.containsKey('work'), isFalse);
    expect(again.properties['email'], 'fm@iade.pt');
    expect(again.aliases, ['FernandoMarson']);
  });
}
