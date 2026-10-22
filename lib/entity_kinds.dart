/// Standard entity kinds offered first in the New entity dropdown.
const List<String> _kinds = <String>[
  'person',
  'place',
  'organization',
  'event',
  'project',
  'website',
];

/// App's own note kinds that are never offered as entity kinds.
const Set<String> _appKinds = <String>{
  'note',
  'daily',
  'article',
  'screenshot',
  'audio',
  'idea',
};

/// Kinds offered in the New entity dropdown: the standard entity kinds first
/// (in this order: person, place, organization, event, project, website),
/// then every other kind in [usedKinds] sorted alphabetically. Excludes the
/// app's own note kinds (note, daily, article, screenshot, audio, idea) and
/// blank values. Values are trimmed and lower-cased; no duplicates.
List<String> entityKindChoices(Iterable<String> usedKinds) {
  final Set<String> seen = <String>{}..addAll(_kinds);
  final List<String> others = <String>[];

  for (final raw in usedKinds) {
    final String kind = raw.trim().toLowerCase();
    if (kind.isEmpty || _appKinds.contains(kind) || seen.contains(kind)) {
      continue;
    }
    seen.add(kind);
    others.add(kind);
  }

  others.sort();
  return <String>[..._kinds, ...others];
}

/// Optional header fields the dialog shows for [kind]: 'email' for person and
/// organization; 'link' for every kind; 'address' for place and organization.
/// Order: email, address, link (only those that apply).
List<String> entityFieldsForKind(String kind) {
  final String key = kind.trim().toLowerCase();
  final List<String> fields = <String>[];

  if (key == 'person' || key == 'organization') {
    fields.add('email');
  }
  if (key == 'place' || key == 'organization') {
    fields.add('address');
  }
  fields.add('link');

  return fields;
}
