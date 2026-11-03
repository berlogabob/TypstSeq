import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/widgets/constants.dart';

void main() {
  test('registry icon and label override built-ins', () {
    final registry = {
      'person': {'icon': 'science', 'label': 'Researcher'},
    };
    expect(iconForKind('person', registry: registry), Icons.science_outlined);
    expect(labelForKind('person', registry: registry), 'Researcher');
  });

  test('unknown icons and malformed entries fall back to built-ins', () {
    final registry = {
      'person': {'icon': 'future-icon', 'label': ''},
      'lab': {'icon': 'future-icon'},
      'place': 'invalid',
    };
    expect(iconForKind('person', registry: registry), Icons.person_outline);
    expect(labelForKind('person', registry: registry), 'Person');
    expect(iconForKind('lab', registry: registry), Icons.description_outlined);
    expect(
      iconForKind('place', registry: registry),
      Icons.location_on_outlined,
    );
    expect(labelForKind('lab', registry: registry), 'Entity');
  });

  test('helpers use the active app registry', () {
    final previous = kindRegistry.value;
    addTearDown(() => kindRegistry.value = previous);
    kindRegistry.value = {
      'lab': {'icon': 'science', 'label': 'Lab'},
    };
    expect(iconForKind('lab'), Icons.science_outlined);
    expect(labelForKind('lab'), 'Lab');
  });
}
