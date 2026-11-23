import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tylog_core/tylog_core.dart';

const _techlab = {
  'schema': 1,
  'id': 'techlab',
  'classes': {
    'lab': {
      'is_a': 'place',
      'fields': ['capacity'],
    },
  },
  'slots': {
    'capacity': {'type': 'number'},
    'bought': {'type': 'date'},
    'location': {
      'type': 'entity',
      'range': 'place',
      'domain': ['equipment'],
      'max': 1,
    },
    'status': {
      'values': ['ok', 'broken'],
      'domain': ['equipment'],
    },
  },
};

String _note(String id, String kind, [String body = '']) =>
    '''
#show: tylog.note.with(
  id: "$id",
  title: "$id",
  kind: "$kind",
)

$body
''';

void main() {
  final ontology = Ontology(const [kCoreOntology, _techlab]);
  String? kindOf(String ref) => const {'Lab 1': 'lab', 'Ana': 'person'}[ref];

  test('a subclass inherits fields and is its ancestors', () {
    expect(ontology.fieldsFor('lab'), ['address', 'link', 'capacity']);
    expect(ontology.isA('lab', 'place'), isTrue);
    expect(ontology.isA('place', 'lab'), isFalse);
    expect(Ontology.core.fieldsFor('club'), isEmpty);
  });

  test('a later document refines a class without dropping the rest', () {
    final merged = Ontology([
      kCoreOntology,
      {
        'classes': {
          'Person': {'icon': 'star'},
          'a': {'is_a': 'b'},
          'b': {'is_a': 'a'},
        },
      },
    ]);
    expect(merged.fieldsFor('person'), ['email', 'link']);
    expect(merged.classes['person']!['icon'], 'star');
    expect(merged.lineage('a'), ['a', 'b']);
  });

  test('facets: type, range, enum, cardinality, domain', () {
    expect(
      ontology.check('equipment', {
        'location': '[[Lab 1]]',
        'status': 'ok',
        'bought': '2026-11-23',
        'capacity': 4,
      }, kindOf),
      isEmpty,
    );
    expect(
      ontology.check('equipment', {
        'location': '[[Ana]], [[Lab 1]]',
        'status': 'lost',
        'bought': 'last year',
        'capacity': 'many',
        'location2': 'ignored',
      }, kindOf),
      [
        '"location" has 2 values, at most 1',
        '"location": "Ana" is a person, expected place',
        '"status": "lost" is not one of ok, broken',
        '"bought": "last year" is not a date (YYYY-MM-DD)',
        '"capacity": "many" is not a number',
      ],
    );
    // Outside the slot's domain, and unresolved references, are not judged.
    expect(ontology.check('article', {'status': 'unread'}, kindOf), isEmpty);
    expect(
      ontology.check('equipment', {'location': 'Nowhere'}, kindOf),
      isEmpty,
    );
  });

  test('the shipped TechLAB domain extends the core', () {
    final techlab = Ontology([
      kCoreOntology,
      jsonDecode(File('../../docs/ontology/techlab.json').readAsStringSync()),
    ]);
    expect(techlab.fieldsFor('lab'), ['address', 'link', 'capacity']);
    expect(techlab.isA('booking', 'event'), isTrue);
    expect(
      techlab.check('lab', {'capacity': 'big'}, (_) => null),
      hasLength(1),
    );
  });

  test('scan reports violations and a broken ontology file', () async {
    final root = await Directory.systemTemp.createTemp('tylog-ontology-');
    addTearDown(() => root.delete(recursive: true));
    final storage = LocalVaultStorage(root);
    await storage.writeText('notes/ana.typ', _note('Ana', 'person'));
    await storage.writeText('notes/lab.typ', _note('Lab 1', 'lab'));
    await storage.writeText(
      'notes/laser.typ',
      _note('Laser', 'equipment', 'location:: [[Ana]]\nstatus:: ok'),
    );
    await storage.writeText(
      'notes/printer.typ',
      _note('Printer', 'equipment', 'location:: [[Lab 1]]'),
    );
    await storage.writeText('$ontologyDir/techlab.json', jsonEncode(_techlab));
    await storage.writeText('$ontologyDir/bad.json', '{"schema": 2}');

    final index = await scanVaultStorage(storage);
    expect(
      [
        for (final p in index.problems)
          if (p.code.startsWith('ontology')) '${p.subject}: ${p.message}',
      ],
      unorderedEquals([
        '$ontologyDir/bad.json: This ontology file could not be read.',
        'notes/laser.typ: "location": "Ana" is a person, expected place',
      ]),
    );
  });
}
