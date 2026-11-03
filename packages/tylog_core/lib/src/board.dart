import 'dart:convert';

import 'models.dart';
import 'storage.dart';

class BoardColumns {
  const BoardColumns({
    this.field = 'status',
    this.values = const ['todo', 'doing', 'done'],
    this.showCancelled = false,
    this.extra = const {},
  });

  final String field;
  final List<String> values;
  final bool showCancelled;
  final Map<String, Object?> extra;

  factory BoardColumns.fromJson(Map<String, Object?> json) => BoardColumns(
    field: json['field'] as String? ?? 'status',
    values:
        (json['values'] as List?)?.cast<String>().toList() ??
        const ['todo', 'doing', 'done'],
    showCancelled: json['showCancelled'] as bool? ?? false,
    extra: Map.of(json)
      ..removeWhere(
        (key, _) => const {'field', 'values', 'showCancelled'}.contains(key),
      ),
  );

  Map<String, Object?> toJson() => {
    ...extra,
    'field': field,
    'values': values,
    'showCancelled': showCancelled,
  };
}

class Board {
  const Board({
    required this.id,
    required this.title,
    this.layout = 'columns',
    this.scopeEntity,
    this.scopeExtra = const {},
    this.columns = const BoardColumns(),
    this.order = const {},
    this.extra = const {},
  });

  final int schema = 1;
  final String id;
  final String title;
  final String layout;
  final String? scopeEntity;
  final Map<String, Object?> scopeExtra;
  final BoardColumns columns;
  final Map<String, List<String>> order;
  final Map<String, Object?> extra;

  factory Board.fromJson(Map<String, Object?> json) {
    const known = {
      'schema',
      'id',
      'title',
      'layout',
      'scope',
      'columns',
      'order',
    };
    final scope = json['scope'];
    final columns = json['columns'];
    final order = json['order'];
    return Board(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      layout: json['layout'] as String? ?? 'columns',
      scopeEntity: scope is Map ? scope['entity'] as String? : null,
      scopeExtra: scope is Map<String, Object?>
          ? (Map.of(scope)..remove('entity'))
          : const {},
      columns: columns is Map<String, Object?>
          ? BoardColumns.fromJson(columns)
          : const BoardColumns(),
      order: order is Map<String, Object?>
          ? {
              for (final entry in order.entries)
                entry.key:
                    (entry.value as List?)?.cast<String>().toList() ?? [],
            }
          : {},
      extra: {
        for (final entry in json.entries)
          if (!known.contains(entry.key)) entry.key: entry.value,
      },
    );
  }

  Map<String, Object?> toJson() => {
    ...extra,
    'schema': schema,
    'id': id,
    'title': title,
    'layout': layout,
    if (scopeEntity != null || scopeExtra.isNotEmpty)
      'scope': {...scopeExtra, if (scopeEntity != null) 'entity': scopeEntity},
    'columns': columns.toJson(),
    'order': order,
  };

  Board moveCard(String cardId, String toColumn, {int? index}) {
    final next = <String, List<String>>{
      for (final entry in order.entries)
        entry.key: entry.value.where((id) => id != cardId).toList(),
    };
    final target = next.putIfAbsent(toColumn, () => []);
    target.insert(index?.clamp(0, target.length) ?? target.length, cardId);
    return Board(
      id: id,
      title: title,
      layout: layout,
      scopeEntity: scopeEntity,
      scopeExtra: scopeExtra,
      columns: columns,
      order: next,
      extra: extra,
    );
  }

  List<String> orderCards(String column, Iterable<String> cardIds) {
    final given = cardIds.toList();
    final available = given.toSet();
    final seen = <String>{};
    return [
      for (final id in [...?order[column], ...given])
        if (available.contains(id) && seen.add(id)) id,
    ];
  }
}

String boardPath(String id) => 'boards/$id.board.json';

Board parseBoard(String text) {
  final decoded = jsonDecode(text);
  if (decoded is! Map<String, Object?>) {
    throw FormatException('Board must be a JSON object', text);
  }
  return Board.fromJson(decoded);
}

String encodeBoard(Board b) =>
    const JsonEncoder.withIndent('  ').convert(b.toJson());

Future<Board?> readBoard(VaultStorage storage, String id) async {
  final path = boardPath(id);
  return await storage.exists(path)
      ? parseBoard(await storage.readText(path))
      : null;
}

Future<void> writeBoard(VaultStorage storage, Board board) async {
  await storage.createDirectory('boards');
  await storage.writeText(boardPath(board.id), encodeBoard(board));
}

List<TaskRef> tasksForEntity(String entityId, VaultIndex index) {
  final children = childrenByParent(index.notes);
  final ids = <String>{entityId};
  final pending = <String>[entityId];
  while (pending.isNotEmpty) {
    for (final child in children[pending.removeLast()] ?? <NoteRef>[]) {
      if (ids.add(child.id)) pending.add(child.id);
    }
  }
  final paths = index.notes
      .where((note) => ids.contains(note.id))
      .map((note) => note.path)
      .toSet();
  final names = <String, String>{};
  final byId = {for (final note in index.notes) note.id: note.id};
  for (final note in index.notes) {
    for (final name in [note.title, ...note.aliases]) {
      names.putIfAbsent(name.toLowerCase(), () => note.id);
    }
  }
  return index.tasks
      .where(
        (task) =>
            ids.contains(
              byId[task.project] ??
                  names[task.project?.toLowerCase()] ??
                  task.project,
            ) ||
            paths.contains(task.notePath),
      )
      .toList();
}

List<IssueRef> issuesForEntity(String entityId, VaultIndex index) {
  final children = childrenByParent(index.notes);
  final ids = <String>{entityId};
  final pending = <String>[entityId];
  while (pending.isNotEmpty) {
    for (final child in children[pending.removeLast()] ?? <NoteRef>[]) {
      if (ids.add(child.id)) pending.add(child.id);
    }
  }
  return index.issues.where((issue) => ids.contains(issue.projectId)).toList();
}

bool hasBoardItems(String entityId, VaultIndex index) =>
    tasksForEntity(entityId, index).isNotEmpty ||
    issuesForEntity(entityId, index).isNotEmpty;
