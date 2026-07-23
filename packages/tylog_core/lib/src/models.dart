enum PkmsSeverity { info, warning, error }

class PkmsProblem {
  const PkmsProblem({
    required this.code,
    required this.severity,
    required this.subject,
    required this.message,
    this.fix,
    this.detail,
    this.targets = const [],
  });

  final String code;
  final PkmsSeverity severity;
  final String subject;
  final String message;
  final String? fix;
  final String? detail;

  /// Vault paths this problem concerns beyond [subject] — e.g. every file that
  /// claims a duplicated id/date, so a fixer can open them all to merge.
  final List<String> targets;

  Map<String, Object?> toJson() => {
    'code': code,
    'severity': severity.name,
    'subject': subject,
    'message': message,
    if (fix != null) 'fix': fix,
    if (detail != null) 'detail': detail,
    if (targets.isNotEmpty) 'targets': targets,
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
    detail: json['detail'] as String?,
    targets:
        (json['targets'] as List?)?.map((e) => e as String).toList() ??
        const [],
  );
}

class NoteRef {
  const NoteRef({
    required this.id,
    required this.path,
    required this.title,
    required this.outgoingLinks,
    this.kind = 'note',
    this.project,
    this.date,
    this.tags = const [],
    this.aliases = const [],
    this.fileRefs = const [],
    this.citations = const [],
    this.dateRefs = const [],
    this.attachments = const [],
    this.properties = const {},
    this.fingerprint,
    this.modifiedMillis,
    this.metadataSource = 'fallback',
  });

  final String id;
  final String path;
  final String title;
  final String kind;
  final String? project;
  final String? date;
  final List<String> tags;
  final List<String> aliases;
  final List<String> outgoingLinks;
  final List<String> fileRefs;
  final List<String> citations;
  final List<DateRef> dateRefs;
  final List<AttachmentRef> attachments;
  final Map<String, Object?> properties;
  final String? fingerprint;
  final int? modifiedMillis;
  final String metadataSource;

  NoteRef copyWith({
    String? id,
    String? title,
    String? kind,
    String? project,
    String? date,
    List<String>? tags,
    List<String>? aliases,
    List<String>? outgoingLinks,
    List<String>? fileRefs,
    List<String>? citations,
    List<DateRef>? dateRefs,
    List<AttachmentRef>? attachments,
    Map<String, Object?>? properties,
    String? fingerprint,
    int? modifiedMillis,
    String? metadataSource,
  }) => NoteRef(
    id: id ?? this.id,
    path: path,
    title: title ?? this.title,
    kind: kind ?? this.kind,
    project: project ?? this.project,
    date: date ?? this.date,
    tags: tags ?? this.tags,
    aliases: aliases ?? this.aliases,
    outgoingLinks: outgoingLinks ?? this.outgoingLinks,
    fileRefs: fileRefs ?? this.fileRefs,
    citations: citations ?? this.citations,
    dateRefs: dateRefs ?? this.dateRefs,
    attachments: attachments ?? this.attachments,
    properties: properties ?? this.properties,
    fingerprint: fingerprint ?? this.fingerprint,
    modifiedMillis: modifiedMillis ?? this.modifiedMillis,
    metadataSource: metadataSource ?? this.metadataSource,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'path': path,
    'title': title,
    'kind': kind,
    'project': project,
    'date': date,
    'tags': tags,
    'aliases': aliases,
    'outgoingLinks': outgoingLinks,
    'fileRefs': fileRefs,
    'citations': citations,
    'dateRefs': dateRefs.map((item) => item.toJson()).toList(),
    'attachments': attachments.map((item) => item.toJson()).toList(),
    'properties': properties,
    'fingerprint': fingerprint,
    'modifiedMillis': modifiedMillis,
    'metadataSource': metadataSource,
  };

  factory NoteRef.fromJson(Map<String, Object?> json) => NoteRef(
    id:
        json['id'] as String? ??
        (json['path'] as String).split('/').last.replaceFirst('.typ', ''),
    path: json['path'] as String,
    title: json['title'] as String,
    kind: json['kind'] as String? ?? 'note',
    project: json['project'] as String?,
    date: json['date'] as String?,
    tags: _strings(json['tags']),
    aliases: _strings(json['aliases']),
    outgoingLinks: _strings(json['outgoingLinks']),
    fileRefs: _strings(json['fileRefs']),
    citations: _strings(json['citations']),
    dateRefs: (json['dateRefs'] as List? ?? const [])
        .cast<Map>()
        .map((item) => DateRef.fromJson(item.cast<String, Object?>()))
        .toList(),
    attachments: (json['attachments'] as List? ?? const [])
        .cast<Map>()
        .map((item) => AttachmentRef.fromJson(item.cast<String, Object?>()))
        .toList(),
    properties: (json['properties'] as Map? ?? const {})
        .cast<String, Object?>(),
    fingerprint: json['fingerprint'] as String?,
    modifiedMillis: (json['modifiedMillis'] as num?)?.toInt(),
    metadataSource: json['metadataSource'] as String? ?? 'legacy',
  );
}

class DateRef {
  const DateRef({required this.date, this.text});

  final String date;
  final String? text;

  Map<String, Object?> toJson() => {
    'date': date,
    if (text != null) 'text': text,
  };

  factory DateRef.fromJson(Map<String, Object?> json) =>
      DateRef(date: json['date'] as String, text: json['text'] as String?);
}

class AttachmentRef {
  const AttachmentRef({required this.path, this.kind = 'file', this.title});

  final String path;
  final String kind;
  final String? title;

  Map<String, Object?> toJson() => {
    'path': path,
    'kind': kind,
    if (title != null) 'title': title,
  };

  factory AttachmentRef.fromJson(Map<String, Object?> json) => AttachmentRef(
    path: json['path'] as String,
    kind: json['kind'] as String? ?? 'file',
    title: json['title'] as String?,
  );
}

enum CalendarItemKind { daily, task, dateRef }

class CalendarItem {
  const CalendarItem({
    required this.date,
    required this.kind,
    required this.title,
    required this.notePath,
  });

  final String date;
  final CalendarItemKind kind;
  final String title;
  final String notePath;
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
    this.version = 5,
    required this.notesByPath,
    required this.backlinksByTarget,
    this.attachmentBacklinksByPath = const {},
    this.problems = const [],
    this.tasks = const [],
  });

  final int version;
  final Map<String, NoteRef> notesByPath;
  final Map<String, List<String>> backlinksByTarget;
  final Map<String, List<String>> attachmentBacklinksByPath;
  final List<PkmsProblem> problems;
  final List<TaskRef> tasks;

  List<NoteRef> get notes =>
      notesByPath.values.toList()..sort((a, b) => a.path.compareTo(b.path));

  List<CalendarItem> get calendar {
    final items = <CalendarItem>[
      for (final note in notes)
        if (note.kind == 'daily' && note.date != null)
          CalendarItem(
            date: note.date!,
            kind: CalendarItemKind.daily,
            title: note.title,
            notePath: note.path,
          ),
      for (final note in notes)
        for (final ref in note.dateRefs)
          CalendarItem(
            date: ref.date,
            kind: CalendarItemKind.dateRef,
            title: ref.text ?? note.title,
            notePath: note.path,
          ),
      for (final task in tasks)
        if (task.due != null)
          CalendarItem(
            date: task.due!.split('T').first,
            kind: CalendarItemKind.task,
            title: task.text,
            notePath: task.notePath,
          ),
    ];
    items.sort((a, b) => a.date.compareTo(b.date));
    return items;
  }

  /// ISO days that carry calendar content, split by whether the day has its
  /// own journal file or only references pointing at it.
  ({Set<String> daily, Set<String> refs}) get calendarDayMarks {
    final daily = <String>{};
    final refs = <String>{};
    for (final item in calendar) {
      (item.kind == CalendarItemKind.daily ? daily : refs).add(item.date);
    }
    return (daily: daily, refs: refs);
  }

  Map<String, Object?> toJson() => {
    'version': version,
    'notes': notes.map((note) => note.toJson()).toList(),
    'backlinksByTarget': _sortedLists(backlinksByTarget),
    'attachmentBacklinksByPath': _sortedLists(attachmentBacklinksByPath),
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
      attachmentBacklinksByPath: _stringLists(
        json['attachmentBacklinksByPath'],
      ),
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
