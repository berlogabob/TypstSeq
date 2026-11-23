import 'package:test/test.dart';
import 'package:tylog_core/tylog_core.dart';

NoteRef _entity(String id, String kind) => NoteRef(
  id: id,
  path: 'notes/$id.typ',
  title: id,
  kind: kind,
  outgoingLinks: const [],
);

EnrichFeedback _event(String entity, {bool accepted = true}) => EnrichFeedback(
  surface: entity,
  entity: entity,
  accepted: accepted,
  note: 'd',
  at: 't',
);

void main() {
  final ontology = Ontology(const [
    kCoreOntology,
    {
      'classes': {
        'lab': {'is_a': 'place'},
        'crop': {'is_a': 'thing'},
      },
    },
  ]);
  final notes = [
    for (var i = 0; i < kSlmMinEntities; i++) _entity('p$i', 'person'),
    _entity('fablab', 'lab'),
    _entity('lisboa', 'place'),
    _entity('trigo', 'crop'),
    _entity('stray', 'note'),
  ];
  final index = VaultIndex(
    notesByPath: {for (final note in notes) note.path: note},
    backlinksByTarget: const {},
  );
  final feedback = [
    for (var i = 0; i < kSlmMinDecisions - 1; i++)
      _event('p${i % kSlmMinEntities}'),
    _event('fablab'),
    _event('lisboa', accepted: false),
    _event('stray'),
    _event('tag:x'),
  ];

  test('decisions are counted per top class', () {
    final rows = {
      for (final row in classReadiness(index, feedback, ontology))
        row.kind: row,
    };
    expect(rows.keys, unorderedEquals(['person', 'place', 'crop']));
    expect(rows['place']!.pages, 2);
    expect((rows['place']!.accepts, rows['place']!.rejects), (1, 1));
    expect(rows['person']!.missing, [
      '1 more decisions',
      'at least one rejection',
    ]);
    expect(rows['crop']!.ready, isFalse);
  });

  test('a ready class is suggested until the user answers', () {
    final rows = classReadiness(index, [
      ...feedback,
      _event('p0', accepted: false),
    ], ontology);
    expect(rows.first.kind, 'person');
    expect(rows.first.ready, isTrue);
    expect(slmSuggestions(rows, const []).map((r) => r.kind), ['person']);
    Decision answer(String action) => Decision(
      at: 't',
      device: 'd',
      item: slmDecisionItem('person'),
      source: slmDecisionSource,
      action: action,
    );
    expect(slmSuggestions(rows, [answer('seen')]), hasLength(1));
    expect(slmSuggestions(rows, [answer('rejected')]), isEmpty);
    expect(slmReadinessReport(rows), contains('| person | 20 | 199 | 1 |'));
  });
}
