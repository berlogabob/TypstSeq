class NoteRef {
  const NoteRef({
    required this.path,
    required this.title,
    required this.outgoingLinks,
    this.date,
    this.tags = const [],
    this.aliases = const [],
  });

  final String path;
  final String title;
  final String? date;
  final List<String> tags;
  final List<String> aliases;
  final List<String> outgoingLinks;

  Map<String, Object?> toJson() => {
    'path': path,
    'title': title,
    'date': date,
    'tags': tags,
    'aliases': aliases,
    'outgoingLinks': outgoingLinks,
  };

  factory NoteRef.fromJson(Map<String, Object?> json) => NoteRef(
    path: json['path'] as String,
    title: json['title'] as String,
    date: json['date'] as String?,
    tags: (json['tags'] as List? ?? const []).cast<String>(),
    aliases: (json['aliases'] as List? ?? const []).cast<String>(),
    outgoingLinks: (json['outgoingLinks'] as List? ?? const []).cast<String>(),
  );
}

class VaultIndex {
  const VaultIndex({
    required this.notesByPath,
    required this.backlinksByTarget,
  });

  final Map<String, NoteRef> notesByPath;
  final Map<String, List<String>> backlinksByTarget;

  List<NoteRef> get notes =>
      notesByPath.values.toList()..sort((a, b) => a.path.compareTo(b.path));

  Map<String, Object?> toJson() => {
    'version': 1,
    'notes': notes.map((note) => note.toJson()).toList(),
    'backlinksByTarget': backlinksByTarget,
  };

  factory VaultIndex.fromJson(Map<String, Object?> json) {
    final notes = (json['notes'] as List? ?? const []).cast<Map>().map(
      (item) => NoteRef.fromJson(item.cast<String, Object?>()),
    );
    final backlinks = <String, List<String>>{};
    for (final entry
        in (json['backlinksByTarget'] as Map? ?? const {}).entries) {
      backlinks[entry.key as String] = (entry.value as List).cast<String>();
    }
    return VaultIndex(
      notesByPath: {for (final note in notes) note.path: note},
      backlinksByTarget: backlinks,
    );
  }
}
