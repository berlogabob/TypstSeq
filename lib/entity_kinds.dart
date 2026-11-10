/// Standard entity kinds offered first in the New entity dropdown.
const List<String> _kinds = <String>[
  'person',
  'place',
  'organization',
  'event',
  'project',
  'website',
  'equipment',
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
/// (in this order: person, place, organization, event, project, website,
/// equipment),
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

/// Header fields the New entity dialog shows for [kind]. A `fields` list in
/// the kind registry (`_system/settings/kinds.json`) wins; otherwise the
/// built-in fields: email for person/organization, address for
/// place/organization, link for every kind except equipment (location, serial,
/// status). Keys are trimmed, lower-cased, deduped; non-strings dropped.
// ponytail: fields are plain string keys; add per-field types when a kind
// needs a date or entity picker.
List<String> entityFieldsForKind(
  String kind, [
  Map<String, dynamic>? registry,
]) {
  final String key = kind.trim().toLowerCase();
  final Object? custom = (registry?[key] as Object?) is Map
      ? (registry![key] as Map)['fields']
      : null;
  if (custom is List) {
    final Set<String> fields = <String>{};
    for (final Object? field in custom) {
      if (field is String && field.trim().isNotEmpty) {
        fields.add(field.trim().toLowerCase());
      }
    }
    return fields.toList();
  }
  if (key == 'equipment') return <String>['location', 'serial', 'status'];
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

/// Dialog label for an entity header field.
String entityFieldLabel(String field) => switch (field) {
  'email' => 'Email (optional)',
  'address' => 'Address (optional)',
  'link' => 'Link or map URL (optional)',
  _ => '${field[0].toUpperCase()}${field.substring(1)} (optional)',
};
