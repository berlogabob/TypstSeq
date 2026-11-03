import '../models.dart';

abstract class Connector {
  String get id;
  Future<void> refresh();
  List<ExternalEntity> entities();
  List<NoteRef> incoming(String day);
}

class ExternalEntity {
  const ExternalEntity({
    required this.id,
    required this.kind,
    required this.title,
    this.aliases = const [],
    this.partOf = const [],
    this.properties = const {},
    this.url,
  });

  final String id;
  final String kind;
  final String title;
  final List<String> aliases;
  final List<String> partOf;
  final Map<String, Object?> properties;
  final String? url;

  NoteRef toNoteRef() => NoteRef(
    id: id,
    path: id,
    kind: kind,
    title: title,
    aliases: aliases,
    partOf: partOf,
    outgoingLinks: const [],
    properties: properties,
  );
}
