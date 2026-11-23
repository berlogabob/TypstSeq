/// TyLog's ontology: classes (note kinds) with `is_a`, and slots (header
/// properties) with a value type, range and cardinality.
///
/// The core ships with the app. A field of application adds one JSON document
/// under [ontologyDir]; the legacy `kinds.json` is a bare `classes` map. Later
/// documents refine earlier ones key by key. Unknown keys are kept and ignored.
///
/// ```json
/// {"schema": 1, "id": "techlab",
///  "classes": {"lab": {"is_a": "place", "label": "Lab", "icon": "science",
///                      "fields": ["capacity"]}},
///  "slots": {"capacity": {"type": "number"},
///            "location": {"type": "entity", "range": "place",
///                         "domain": ["equipment"], "max": 1},
///            "status":   {"values": ["ok", "broken"], "domain": ["equipment"]}}}
/// ```
///
/// Slot `type` is `string` (default), `number`, `date` or `entity`. A slot with
/// a `domain` applies only to those classes and their subclasses.
library;

import 'dart:convert';

import 'enrich.dart' show loadEnrichFeedback;
import 'models.dart';
import 'scanner.dart' show LinkResolutionStatus, LinkResolver;
import 'storage.dart';

const ontologyDir = '_system/settings/ontology';

/// The built-in classes and their dialog fields, under the root `thing`. A
/// domain class with no closer core parent says `is_a: thing` to be linkable.
/// Kinds stay open: a kind that
/// is not listed here or in a domain document is still a valid kind.
const kCoreOntology = <String, Object?>{
  'schema': 1,
  'id': 'core',
  'classes': {
    'thing': <String, Object?>{},
    'person': {
      'is_a': 'thing',
      'fields': ['email', 'link'],
    },
    'organization': {
      'is_a': 'thing',
      'fields': ['email', 'address', 'link'],
    },
    'place': {
      'is_a': 'thing',
      'fields': ['address', 'link'],
    },
    'event': {
      'is_a': 'thing',
      'fields': ['link'],
    },
    'project': {
      'is_a': 'thing',
      'fields': ['link'],
    },
    'website': {
      'is_a': 'thing',
      'fields': ['link'],
    },
    'equipment': {
      'is_a': 'thing',
      'fields': ['location', 'serial', 'status'],
    },
  },
  'slots': {
    'part_of': {'type': 'entity'},
  },
};

class Ontology {
  /// Merges [documents] in order. Malformed parts are skipped, never thrown:
  /// a bad ontology must not stop a scan.
  Ontology(Iterable<Object?> documents) {
    for (final document in documents) {
      if (document is! Map) continue;
      _merge(_classes, document['classes'], lowerKeys: true);
      _merge(_slots, document['slots']);
    }
  }

  static final core = Ontology(const [kCoreOntology]);

  final _classes = <String, Map<String, Object?>>{};
  final _slots = <String, Map<String, Object?>>{};

  static void _merge(
    Map<String, Map<String, Object?>> into,
    Object? entries, {
    bool lowerKeys = false,
  }) {
    if (entries is! Map) return;
    entries.forEach((key, value) {
      if (key is! String || value is! Map) return;
      final name = lowerKeys ? key.trim().toLowerCase() : key.trim();
      (into[name] ??= {}).addAll(value.cast<String, Object?>());
    });
  }

  /// Every class with its merged definition (`is_a`, `label`, `icon`,
  /// `fields`), in the shape of the kind registry.
  Map<String, Map<String, Object?>> get classes => _classes;

  /// [kind] followed by its ancestors, nearest first. Stops on an `is_a` loop.
  List<String> lineage(String kind) {
    final chain = <String>[];
    Object? next = kind.trim().toLowerCase();
    while (next is String && next.isNotEmpty && !chain.contains(next)) {
      chain.add(next);
      final parent = _classes[next]?['is_a'];
      next = parent is String ? parent.trim().toLowerCase() : null;
    }
    return chain;
  }

  bool isA(String kind, String ancestor) =>
      lineage(kind).contains(ancestor.trim().toLowerCase());

  /// Header fields for [kind]: inherited ones first, then its own. Trimmed,
  /// lower-cased, deduped.
  List<String> fieldsFor(String kind) {
    final fields = <String>{};
    for (final name in lineage(kind).reversed) {
      final own = _classes[name]?['fields'];
      if (own is! List) continue;
      for (final field in own) {
        if (field is String && field.trim().isNotEmpty) {
          fields.add(field.trim().toLowerCase());
        }
      }
    }
    return fields.toList();
  }

  static final _wikiLink = RegExp(r'\[\[([^\]|]+)');

  /// A property's values as trimmed strings. For an [entity] slot, `[[x]]`
  /// links are unwrapped, several per string.
  static List<String> slotValues(Object? raw, {bool entity = false}) => [
    for (final item in raw is List ? raw : [raw])
      if (item != null)
        if (entity && _wikiLink.hasMatch('$item'))
          ..._wikiLink.allMatches('$item').map((m) => m[1]!.trim())
        else if ('$item'.trim().isNotEmpty)
          '$item'.trim(),
  ];
  static final _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}');

  /// Facet violations of one note's [properties]; empty when it conforms.
  /// [kindOf] gives the kind of the note an entity reference resolves to, or
  /// null when it does not resolve.
  // ponytail: one definition per slot name; add per-class slot overrides when
  // two classes need different ranges for the same property.
  List<String> check(
    String kind,
    Map<String, Object?> properties,
    String? Function(String reference) kindOf,
  ) {
    final violations = <String>[];
    properties.forEach((key, raw) {
      final slot = _slots[key];
      if (slot == null) return;
      final domain = slot['domain'];
      if (domain is List && !domain.any((d) => d is String && isA(kind, d))) {
        return;
      }
      final type = slot['type'];
      final values = slotValues(raw, entity: type == 'entity');
      final max = slot['max'];
      if (max is int && values.length > max) {
        violations.add('"$key" has ${values.length} values, at most $max');
      }
      final allowed = slot['values'];
      final range = slot['range'];
      for (final value in values) {
        if (allowed is List && !allowed.contains(value)) {
          violations.add(
            '"$key": "$value" is not one of ${allowed.join(', ')}',
          );
        } else if (type == 'number' && num.tryParse(value) == null) {
          violations.add('"$key": "$value" is not a number');
        } else if (type == 'date' &&
            !(_isoDate.hasMatch(value) && DateTime.tryParse(value) != null)) {
          violations.add('"$key": "$value" is not a date (YYYY-MM-DD)');
        } else if (type == 'entity' && range is String) {
          // An unresolved reference cannot be judged; broken links are
          // reported by the link pass.
          final target = kindOf(value);
          if (target != null && !isA(target, range)) {
            violations.add('"$key": "$value" is a $target, expected $range');
          }
        }
      }
    });
    return violations;
  }
}

/// The core plus every `*.json` under [ontologyDir]; `domains` is those
/// documents without the core. An unreadable document becomes a problem
/// instead of failing the scan.
Future<({Ontology ontology, List<Object?> domains, List<PkmsProblem> problems})>
loadOntology(VaultStorage storage) async {
  final documents = <Object?>[];
  final problems = <PkmsProblem>[];
  if (await storage.exists(ontologyDir)) {
    final entries = await storage.list(path: ontologyDir);
    final paths = [
      for (final entry in entries)
        if (!entry.isDirectory && entry.path.endsWith('.json')) entry.path,
    ]..sort();
    for (final path in paths) {
      try {
        final document = jsonDecode(await storage.readText(path));
        if (document is! Map || document['schema'] != 1) {
          throw const FormatException('expected an object with "schema": 1');
        }
        documents.add(document);
      } on FormatException catch (error) {
        problems.add(
          PkmsProblem(
            code: 'ontology-file',
            severity: PkmsSeverity.warning,
            subject: path,
            message: 'This ontology file could not be read.',
            detail: error.message,
          ),
        );
      }
    }
  }
  return (
    ontology: Ontology([kCoreOntology, ...documents]),
    domains: documents,
    problems: problems,
  );
}

/// Notes whose entity slot [slot] points at the note with [id], or at anything
/// inside it through `part_of`, transitively. "What equipment is in lab L,
/// including its rooms?" is `pointingInto(index, 'location', lab.id)`.
List<NoteRef> pointingInto(VaultIndex index, String slot, String id) {
  final children = childrenByParent(index.notes);
  final inside = <String>{};
  final queue = [id];
  while (queue.isNotEmpty) {
    final next = queue.removeLast();
    if (inside.add(next)) {
      queue.addAll([
        for (final child in children[next] ?? <NoteRef>[]) child.id,
      ]);
    }
  }
  final resolver = LinkResolver(index.notes);
  bool hits(String reference) {
    final resolved = resolver.resolve(reference);
    return resolved.status == LinkResolutionStatus.resolved &&
        inside.contains(index.notesByPath[resolved.path]?.id);
  }

  return [
    for (final note in index.notes)
      if (Ontology.slotValues(note.properties[slot], entity: true).any(hits))
        note,
  ];
}

/// One field of application as files: the "information blob" a small model can
/// be fitted or evaluated on, and the same content as OWL for Protégé.
///
/// - `<id>.ontology.json`: the domain document ([id] `core` is the built-in).
/// - `instances.jsonl`: every note whose kind is one of the domain's classes
///   or a subclass.
/// - `decisions.jsonl`: accept/reject ledger rows about those instances.
/// - `<id>.ttl`: classes, slots, instances and their resolved entity links.
///
/// [onlyClass] narrows the instances, and so the decisions, to one class and
/// its subclasses: `core` with `person` is the blob for a people model.
// ponytail: decisions carry the note path, not the sentence; join with the
// mentions files when a model needs the text.
Future<Map<String, String>> exportDomain(
  VaultStorage storage,
  VaultIndex index,
  String id, {
  String? onlyClass,
}) async {
  final loaded = await loadOntology(storage);
  final document = id == 'core'
      ? kCoreOntology
      : loaded.domains.cast<Map>().where((d) => d['id'] == id).firstOrNull;
  if (document == null) throw ArgumentError.value(id, 'id', 'No such domain');
  final ontology = loaded.ontology;
  final own = Ontology([document]);
  final instances = [
    for (final note in index.notes)
      if (ontology.lineage(note.kind).any(own.classes.containsKey) &&
          (onlyClass == null || ontology.isA(note.kind, onlyClass)))
        note,
  ]..sort((a, b) => a.id.compareTo(b.id));
  final ids = {for (final note in instances) note.id: note};
  String lines(Iterable<Object?> rows) =>
      rows.map((row) => '${jsonEncode(row)}\n').join();

  String iri(String space, String name) =>
      '<urn:tylog:$space#${Uri.encodeComponent(name)}>';
  final resolver = LinkResolver(index.notes);
  final ttl = StringBuffer()
    ..writeln('@prefix owl: <http://www.w3.org/2002/07/owl#> .')
    ..writeln('@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .')
    ..writeln('@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .')
    ..writeln(
      '<urn:tylog:ontology:${Uri.encodeComponent(id)}> a owl:Ontology .',
    );
  final classes = {
    for (final name in own.classes.keys) ...ontology.lineage(name),
    for (final note in instances) ...ontology.lineage(note.kind),
  };
  for (final name in classes) {
    ttl.writeln('${iri('class', name)} a owl:Class .');
    final parent = ontology.lineage(name).skip(1).firstOrNull;
    if (parent != null) {
      ttl.writeln(
        '${iri('class', name)} rdfs:subClassOf ${iri('class', parent)} .',
      );
    }
  }
  final slots = {
    'part_of': const <String, Object?>{'type': 'entity'},
    ...own._slots,
  };
  slots.forEach((name, slot) {
    final subject = iri('slot', name);
    final entity = slot['type'] == 'entity';
    ttl.writeln(
      '$subject a ${entity ? 'owl:ObjectProperty' : 'owl:DatatypeProperty'} .',
    );
    if (slot['max'] == 1) ttl.writeln('$subject a owl:FunctionalProperty .');
    final range = entity
        ? (slot['range'] is String ? iri('class', '${slot['range']}') : null)
        : switch (slot['type']) {
            'number' => 'xsd:decimal',
            'date' => 'xsd:dateTime',
            _ => 'xsd:string',
          };
    if (range != null) ttl.writeln('$subject rdfs:range $range .');
    // Several domains would mean their intersection in RDFS, so only a single
    // one is stated.
    final domain = slot['domain'];
    if (domain is List && domain.length == 1) {
      ttl.writeln('$subject rdfs:domain ${iri('class', '${domain.single}')} .');
    }
  });
  for (final note in instances) {
    final subject = iri('entity', note.id);
    ttl.writeln(
      '$subject a owl:NamedIndividual, '
      '${iri('class', note.kind.trim().toLowerCase())} ; '
      'rdfs:label ${jsonEncode(note.title)} .',
    );
    final links = {...note.properties, 'part_of': note.partOf};
    slots.forEach((name, slot) {
      if (slot['type'] != 'entity') return;
      for (final value in Ontology.slotValues(links[name], entity: true)) {
        final resolved = resolver.resolve(value);
        final target = resolved.status == LinkResolutionStatus.resolved
            ? index.notesByPath[resolved.path]
            : null;
        if (target != null) {
          ttl.writeln(
            '$subject ${iri('slot', name)} ${iri('entity', target.id)} .',
          );
        }
      }
    });
  }

  return {
    '$id.ontology.json': const JsonEncoder.withIndent('  ').convert(document),
    'instances.jsonl': lines([
      for (final note in instances)
        {
          'id': note.id,
          'title': note.title,
          'kind': note.kind,
          'aliases': note.aliases,
          'part_of': note.partOf,
          'properties': note.properties,
        },
    ]),
    'decisions.jsonl': lines([
      for (final event in await loadEnrichFeedback(storage))
        if (ids[event.entity] case final note?)
          {...event.toJson(), 'kind': note.kind},
    ]),
    '$id.ttl': ttl.toString(),
  };
}
