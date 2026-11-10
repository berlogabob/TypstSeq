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
      'equipment',
    ]);
  });

  test('entityKindChoices appends used kinds sorted, normalised, deduped, '
      'and drops app kinds and blanks', () {
    expect(
      entityKindChoices(<String>[
        ' Castle',
        'club',
        'article',
        'daily',
        'person',
        '',
        'Club',
      ]),
      <String>[
        'person',
        'place',
        'organization',
        'event',
        'project',
        'website',
        'equipment',
        'castle',
        'club',
      ],
    );
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
      'link',
    ]);
  });

  test('entityFieldsForKind for custom kind', () {
    expect(entityFieldsForKind('club'), <String>['link']);
  });

  test('entityFieldsForKind for equipment', () {
    expect(entityFieldsForKind('equipment'), <String>[
      'location',
      'serial',
      'status',
    ]);
  });

  test('kind registry fields override the built-in fields', () {
    final registry = {
      'place': {
        'icon': 'place',
        'fields': ['type', ' Address ', 'period', 'type', 3, ''],
      },
      'boat': {'fields': <Object>[]},
    };
    expect(entityFieldsForKind('place', registry), <String>[
      'type',
      'address',
      'period',
    ]);
    expect(entityFieldsForKind('boat', registry), <String>[]);
    expect(entityFieldsForKind('person', registry), <String>['email', 'link']);
  });

  test('entityFieldLabel', () {
    expect(entityFieldLabel('email'), 'Email (optional)');
    expect(entityFieldLabel('link'), 'Link or map URL (optional)');
    expect(entityFieldLabel('serial'), 'Serial (optional)');
  });
}
