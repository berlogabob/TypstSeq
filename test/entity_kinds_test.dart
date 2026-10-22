import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/entity_kinds.dart';

void main() {
  test('entityKindChoices returns the standard kinds by default', () {
    expect(entityKindChoices([]), <String>[
      'person',
      'place',
      'organization',
      'event',
      'project',
      'website',
    ]);
  });

  test('entityKindChoices appends used kinds sorted, normalised, deduped, '
      'and drops app kinds and blanks', () {
    expect(entityKindChoices(<String>[
      ' Castle',
      'club',
      'article',
      'daily',
      'person',
      '',
      'Club',
    ]), <String>[
      'person',
      'place',
      'organization',
      'event',
      'project',
      'website',
      'castle',
      'club',
    ]);
  });

  test('entityFieldsForKind for person', () {
    expect(entityFieldsForKind('person'), <String>['email', 'link']);
  });

  test('entityFieldsForKind for place', () {
    expect(entityFieldsForKind('place'), <String>['address', 'link']);
  });

  test('entityFieldsForKind for organization', () {
    expect(entityFieldsForKind('organization'), <String>[
      'email',
      'address',
      'link'
    ]);
  });

  test('entityFieldsForKind for custom kind', () {
    expect(entityFieldsForKind('club'), <String>['link']);
  });
}
