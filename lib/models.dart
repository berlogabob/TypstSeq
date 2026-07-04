enum PkmsSeverity { info, warning, error }

class PkmsProblem {
  const PkmsProblem({
    required this.code,
    required this.severity,
    required this.subject,
    required this.message,
    this.fix,
  });

  final String code;
  final PkmsSeverity severity;
  final String subject;
  final String message;
  final String? fix;

  Map<String, Object?> toJson() => {
    'code': code,
    'severity': severity.name,
    'subject': subject,
    'message': message,
    if (fix != null) 'fix': fix,
  };

  factory PkmsProblem.fromJson(Map<String, Object?> json) => PkmsProblem(
    code: json['code'] as String,
    severity: PkmsSeverity.values.firstWhere(
      (value) => value.name == json['severity'],
      orElse: () => PkmsSeverity.warning,
    ),
    subject: json['subject'] as String,
    message: json['message'] as String,
    fix: json['fix'] as String?,
  );
}

class NoteRef {
  const NoteRef({
    required this.id,
    required this.path,
    required this.title,
    required this.outgoingLinks,
    this.date,
    this.tags = const [],
    this.aliases = const [],
    this.fileRefs = const [],
    this.citations = const [],
    this.properties = const {},
    this.fingerprint,
    this.metadataSource = 'fallback',
  });

  final String id;
  final String path;
  final String title;
  final String? date;
  final List<String> tags;
  final List<String> aliases;
  final List<String> outgoingLinks;
  final List<String> fileRefs;
  final List<String> citations;
  final Map<String, Object?> properties;
  final String? fingerprint;
  final String metadataSource;

  NoteRef copyWith({
    String? id,
    String? title,
    String? date,
    List<String>? tags,
    List<String>? aliases,
    List<String>? outgoingLinks,
    List<String>? fileRefs,
    List<String>? citations,
    Map<String, Object?>? properties,
    String? fingerprint,
    String? metadataSource,
  }) => NoteRef(
    id: id ?? this.id,
    path: path,
    title: title ?? this.title,
    date: date ?? this.date,
    tags: tags ?? this.tags,
    aliases: aliases ?? this.aliases,
    outgoingLinks: outgoingLinks ?? this.outgoingLinks,
    fileRefs: fileRefs ?? this.fileRefs,
    citations: citations ?? this.citations,
    properties: properties ?? this.properties,
    fingerprint: fingerprint ?? this.fingerprint,
    metadataSource: metadataSource ?? this.metadataSource,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'path': path,
    'title': title,
    'date': date,
    'tags': tags,
    'aliases': aliases,
    'outgoingLinks': outgoingLinks,
    'fileRefs': fileRefs,
    'citations': citations,
    'properties': properties,
    'fingerprint': fingerprint,
    'metadataSource': metadataSource,
  };

  factory NoteRef.fromJson(Map<String, Object?> json) => NoteRef(
    id:
        json['id'] as String? ??
        (json['path'] as String).split('/').last.replaceFirst('.typ', ''),
    path: json['path'] as String,
    title: json['title'] as String,
    date: json['date'] as String?,
    tags: _strings(json['tags']),
    aliases: _strings(json['aliases']),
    outgoingLinks: _strings(json['outgoingLinks']),
    fileRefs: _strings(json['fileRefs']),
    citations: _strings(json['citations']),
    properties: (json['properties'] as Map? ?? const {})
        .cast<String, Object?>(),
    fingerprint: json['fingerprint'] as String?,
    metadataSource: json['metadataSource'] as String? ?? 'legacy',
  );
}

class TaskRef {
  const TaskRef({
    required this.id,
    required this.notePath,
    required this.text,
    this.status = 'todo',
    this.priority = 'normal',
    this.project,
    this.scheduled,
    this.due,
    this.remind,
    this.timezone,
    this.recurrence,
    this.dependencies = const [],
    this.assignees = const [],
    this.tags = const [],
    this.completed = const [],
    this.properties = const {},
  });

  final String id;
  final String notePath;
  final String text;
  final String status;
  final String priority;
  final String? project;
  final String? scheduled;
  final String? due;
  final String? remind;
  final String? timezone;
  final String? recurrence;
  final List<String> dependencies;
  final List<String> assignees;
  final List<String> tags;
  final List<String> completed;
  final Map<String, Object?> properties;

  Map<String, Object?> toJson() => {
    'id': id,
    'notePath': notePath,
    'text': text,
    'status': status,
    'priority': priority,
    'project': project,
    'scheduled': scheduled,
    'due': due,
    'remind': remind,
    'timezone': timezone,
    'recurrence': recurrence,
    'dependencies': dependencies,
    'assignees': assignees,
    'tags': tags,
    'completed': completed,
    'properties': properties,
  };

  factory TaskRef.fromJson(Map<String, Object?> json) => TaskRef(
    id: json['id'] as String,
    notePath: json['notePath'] as String,
    text: json['text'] as String,
    status: json['status'] as String? ?? 'todo',
    priority: json['priority'] as String? ?? 'normal',
    project: json['project'] as String?,
    scheduled: json['scheduled'] as String?,
    due: json['due'] as String?,
    remind: json['remind'] as String?,
    timezone: json['timezone'] as String?,
    recurrence: json['recurrence'] as String?,
    dependencies: _strings(json['dependencies']),
    assignees: _strings(json['assignees']),
    tags: _strings(json['tags']),
    completed: _strings(json['completed']),
    properties: (json['properties'] as Map? ?? const {})
        .cast<String, Object?>(),
  );
}

class VaultIndex {
  const VaultIndex({
    this.version = 4,
    required this.notesByPath,
    required this.backlinksByTarget,
    this.fileBacklinksById = const {},
    this.problems = const [],
    this.tasks = const [],
  });

  final int version;
  final Map<String, NoteRef> notesByPath;
  final Map<String, List<String>> backlinksByTarget;
  final Map<String, List<String>> fileBacklinksById;
  final List<PkmsProblem> problems;
  final List<TaskRef> tasks;

  List<NoteRef> get notes =>
      notesByPath.values.toList()..sort((a, b) => a.path.compareTo(b.path));

  Map<String, Object?> toJson() => {
    'version': version,
    'notes': notes.map((note) => note.toJson()).toList(),
    'backlinksByTarget': _sortedLists(backlinksByTarget),
    'fileBacklinksById': _sortedLists(fileBacklinksById),
    'problems': problems.map((problem) => problem.toJson()).toList(),
    'tasks': tasks.map((task) => task.toJson()).toList(),
  };

  factory VaultIndex.fromJson(Map<String, Object?> json) {
    final notes = (json['notes'] as List? ?? const []).cast<Map>().map(
      (item) => NoteRef.fromJson(item.cast<String, Object?>()),
    );
    return VaultIndex(
      version: (json['version'] as num?)?.toInt() ?? 1,
      notesByPath: {for (final note in notes) note.path: note},
      backlinksByTarget: _stringLists(json['backlinksByTarget']),
      fileBacklinksById: _stringLists(json['fileBacklinksById']),
      problems: (json['problems'] as List? ?? const [])
          .cast<Map>()
          .map((item) => PkmsProblem.fromJson(item.cast<String, Object?>()))
          .toList(),
      tasks: (json['tasks'] as List? ?? const [])
          .cast<Map>()
          .map((item) => TaskRef.fromJson(item.cast<String, Object?>()))
          .toList(),
    );
  }
}

List<String> _strings(Object? value) =>
    (value as List? ?? const []).map((item) => item.toString()).toList();

Map<String, List<String>> _stringLists(Object? value) => {
  for (final entry in (value as Map? ?? const {}).entries)
    entry.key.toString(): _strings(entry.value),
};

Map<String, List<String>> _sortedLists(Map<String, List<String>> value) => {
  for (final key in (value.keys.toList()..sort()))
    key: (value[key]!.toSet().toList()..sort()),
};
