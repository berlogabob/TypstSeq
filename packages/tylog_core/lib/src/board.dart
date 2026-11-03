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

class BoardCard {
  const BoardCard({
    required this.id,
    required this.type,
    this.ref,
    this.text,
    this.x = 0,
    this.y = 0,
    this.w = 240,
    this.h = 120,
    this.color,
    this.frame,
    this.extra = const {},
  });
  final String id, type;
  final String? ref, text, color, frame;
  final num x, y, w, h;
  final Map<String, Object?> extra;

  factory BoardCard.fromJson(Map<String, Object?> json) => BoardCard(
    id: json['id'] as String? ?? '',
    type: json['type'] as String? ?? 'text',
    ref: json['ref'] as String?,
    text: json['text'] as String?,
    x: json['x'] as num? ?? 0,
    y: json['y'] as num? ?? 0,
    w: json['w'] as num? ?? 240,
    h: json['h'] as num? ?? 120,
    color: json['color'] as String?,
    frame: json['frame'] as String?,
    extra: _extra(json, {
      'id',
      'type',
      'ref',
      'text',
      'x',
      'y',
      'w',
      'h',
      'color',
      'frame',
    }),
  );
  Map<String, Object?> toJson() => {
    ...extra,
    'id': id,
    'type': type,
    if (ref != null) 'ref': ref,
    if (text != null) 'text': text,
    'x': x,
    'y': y,
    'w': w,
    'h': h,
    'color': color,
    'frame': frame,
  };
  BoardCard copyWith({num? x, num? y, num? w, num? h}) => BoardCard(
    id: id,
    type: type,
    ref: ref,
    text: text,
    x: x ?? this.x,
    y: y ?? this.y,
    w: w ?? this.w,
    h: h ?? this.h,
    color: color,
    frame: frame,
    extra: extra,
  );
}

class BoardFrame {
  const BoardFrame({
    required this.id,
    required this.title,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    this.extra = const {},
  });
  final String id, title;
  final num x, y, w, h;
  final Map<String, Object?> extra;
  factory BoardFrame.fromJson(Map<String, Object?> json) => BoardFrame(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    x: json['x'] as num? ?? 0,
    y: json['y'] as num? ?? 0,
    w: json['w'] as num? ?? 0,
    h: json['h'] as num? ?? 0,
    extra: _extra(json, {'id', 'title', 'x', 'y', 'w', 'h'}),
  );
  Map<String, Object?> toJson() => {
    ...extra,
    'id': id,
    'title': title,
    'x': x,
    'y': y,
    'w': w,
    'h': h,
  };
  BoardFrame moveTo(num x, num y) =>
      BoardFrame(id: id, title: title, x: x, y: y, w: w, h: h, extra: extra);
}

class BoardEdge {
  const BoardEdge({
    required this.id,
    required this.from,
    required this.to,
    this.label = '',
    this.extra = const {},
  });
  final String id, from, to, label;
  final Map<String, Object?> extra;
  factory BoardEdge.fromJson(Map<String, Object?> json) => BoardEdge(
    id: json['id'] as String? ?? '',
    from: json['from'] as String? ?? '',
    to: json['to'] as String? ?? '',
    label: json['label'] as String? ?? '',
    extra: _extra(json, {'id', 'from', 'to', 'label'}),
  );
  Map<String, Object?> toJson() => {
    ...extra,
    'id': id,
    'from': from,
    'to': to,
    'label': label,
  };
}

class BoardViewport {
  const BoardViewport({
    this.x = 0,
    this.y = 0,
    this.zoom = 1,
    this.extra = const {},
  });
  final num x, y, zoom;
  final Map<String, Object?> extra;
  factory BoardViewport.fromJson(Map<String, Object?> json) => BoardViewport(
    x: json['x'] as num? ?? 0,
    y: json['y'] as num? ?? 0,
    zoom: json['zoom'] as num? ?? 1,
    extra: _extra(json, {'x', 'y', 'zoom'}),
  );
  Map<String, Object?> toJson() => {...extra, 'x': x, 'y': y, 'zoom': zoom};
}

Map<String, Object?> _extra(Map<String, Object?> json, Set<String> known) =>
    Map.of(json)..removeWhere((key, _) => known.contains(key));

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
    int? schema,
    this.cards = const [],
    this.frames = const [],
    this.edges = const [],
    this.viewport = const BoardViewport(),
  }) : schema = schema ?? (layout == 'free' ? 2 : 1);

  final int schema;
  final List<BoardCard> cards;
  final List<BoardFrame> frames;
  final List<BoardEdge> edges;
  final BoardViewport viewport;
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
      'cards',
      'frames',
      'edges',
      'viewport',
    };
    final scope = json['scope'];
    final columns = json['columns'];
    final order = json['order'];
    return Board(
      schema: json['schema'] as int? ?? 1,
      cards: (json['cards'] as List? ?? [])
          .map((v) => BoardCard.fromJson(Map<String, Object?>.from(v as Map)))
          .toList(),
      frames: (json['frames'] as List? ?? [])
          .map((v) => BoardFrame.fromJson(Map<String, Object?>.from(v as Map)))
          .toList(),
      edges: (json['edges'] as List? ?? [])
          .map((v) => BoardEdge.fromJson(Map<String, Object?>.from(v as Map)))
          .toList(),
      viewport: json['viewport'] is Map
          ? BoardViewport.fromJson(
              Map<String, Object?>.from(json['viewport'] as Map),
            )
          : const BoardViewport(),
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
    if (schema >= 2 || layout == 'free') ...{
      'cards': cards.map((c) => c.toJson()).toList(),
      'frames': frames.map((f) => f.toJson()).toList(),
      'edges': edges.map((e) => e.toJson()).toList(),
      'viewport': viewport.toJson(),
    },
  };

  Board moveCardToColumn(String cardId, String toColumn, {int? index}) {
    final next = <String, List<String>>{
      for (final entry in order.entries)
        entry.key: entry.value.where((id) => id != cardId).toList(),
    };
    final target = next.putIfAbsent(toColumn, () => []);
    target.insert(index?.clamp(0, target.length) ?? target.length, cardId);
    return _copy(order: next);
  }

  Board _copy({
    List<BoardCard>? cards,
    List<BoardFrame>? frames,
    List<BoardEdge>? edges,
    Map<String, List<String>>? order,
    int? schema,
  }) => Board(
    id: id,
    title: title,
    layout: layout,
    scopeEntity: scopeEntity,
    scopeExtra: scopeExtra,
    columns: columns,
    order: order ?? this.order,
    extra: extra,
    schema: schema ?? this.schema,
    cards: cards ?? this.cards,
    frames: frames ?? this.frames,
    edges: edges ?? this.edges,
    viewport: viewport,
  );

  Board addCard(BoardCard card) => _copy(cards: [...cards, card], schema: 2);
  Board moveCard(String id, num x, num y) => _copy(
    cards: [
      for (final card in cards)
        if (card.id == id)
          card.copyWith(x: (x / 8).round() * 8, y: (y / 8).round() * 8)
        else
          card,
    ],
  );
  Board resizeCard(String id, num w, num h) => _copy(
    cards: [
      for (final card in cards)
        if (card.id == id) card.copyWith(w: w, h: h) else card,
    ],
  );
  Board removeCard(String id) => _copy(
    cards: cards.where((card) => card.id != id).toList(),
    edges: edges.where((edge) => edge.from != id && edge.to != id).toList(),
  );
  Board addEdge(BoardEdge edge) =>
      edge.from == edge.to ||
          edges.any(
            (e) => e.id == edge.id || (e.from == edge.from && e.to == edge.to),
          )
      ? this
      : _copy(edges: [...edges, edge], schema: 2);
  List<BoardCard> cardsInRect(num x, num y, num w, num h) => cards
      .where(
        (c) => c.x < x + w && c.x + c.w > x && c.y < y + h && c.y + c.h > y,
      )
      .toList();
  Board moveFrame(String id, num x, num y) {
    final matches = frames.where((f) => f.id == id);
    if (matches.isEmpty) return this;
    final frame = matches.first;
    final dx = x - frame.x, dy = y - frame.y;
    return _copy(
      frames: [
        for (final f in frames)
          if (f.id == id) f.moveTo(x, y) else f,
      ],
      cards: [
        for (final c in cards)
          if (c.x + c.w / 2 >= frame.x &&
              c.x + c.w / 2 <= frame.x + frame.w &&
              c.y + c.h / 2 >= frame.y &&
              c.y + c.h / 2 <= frame.y + frame.h)
            c.copyWith(x: c.x + dx, y: c.y + dy)
          else
            c,
      ],
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
