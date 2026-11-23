import 'package:tylog_core/tylog_core.dart' show Ontology, kCoreOntology;

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

/// Header fields the New entity dialog shows for [kind]: the ontology's
/// fields for the kind, inherited through `is_a`. [registry] is the kind
/// registry (kinds.json over the domain ontologies); a `fields` list there
/// replaces the core one. A kind that declares no fields anywhere gets a link.
List<String> entityFieldsForKind(
  String kind, [
  Map<String, dynamic>? registry,
]) {
  final ontology = Ontology([
    kCoreOntology,
    {'classes': registry},
  ]);
  final declared = ontology
      .lineage(kind)
      .any((name) => ontology.classes[name]?['fields'] is List);
  return declared ? ontology.fieldsFor(kind) : <String>['link'];
}

/// Dialog label for an entity header field.
String entityFieldLabel(String field) => switch (field) {
  'email' => 'Email (optional)',
  'address' => 'Address (optional)',
  'link' => 'Link or map URL (optional)',
  _ => '${field[0].toUpperCase()}${field.substring(1)} (optional)',
};
