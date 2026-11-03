# Task F1 (pi): board file model, pure Dart

Create exactly two NEW files. Do not edit any other file. Do not create any other file (no scripts).

1. `packages/tylog_core/lib/src/board.dart` (imports: dart:convert only)
```dart
class BoardColumns { final String field; final List<String> values; final bool showCancelled; ... }
class Board {
  final int schema;            // always 1
  final String id;
  final String title;
  final String layout;         // "columns" | "free" | "tree"
  final String? scopeEntity;   // scope.entity
  final BoardColumns columns;  // default field "status", values ["todo","doing","done"], showCancelled false
  final Map<String, List<String>> order; // column value -> card ids
  const Board({...});
  factory Board.fromJson(Map<String, Object?> json); // tolerant: missing fields -> defaults; unknown keys kept in `extra`
  final Map<String, Object?> extra;
  Map<String, Object?> toJson();   // writes extra back untouched (forward compatible)
  Board moveCard(String cardId, String toColumn, {int? index}); // removes cardId from every column list, inserts into toColumn at index (clamped) or end
  List<String> orderCards(String column, Iterable<String> cardIds); // cards in saved order first, then the rest in given order; ids not in cardIds dropped
}
String boardPath(String id) => 'boards/$id.board.json';
Board parseBoard(String text);   // jsonDecode + fromJson; throws FormatException on non-object
String encodeBoard(Board b);     // JsonEncoder.withIndent('  ')
```
2. `packages/tylog_core/test/board_test.dart` (package:test): round-trip equality of toJson; unknown keys preserved; defaults for empty `{}` plus id/title; moveCard between columns, within column to index, clamp index; orderCards with stale ids and new ids; parseBoard on `[]` throws FormatException.

Verify: `cd packages/tylog_core && dart test test/board_test.dart && dart analyze lib/src/board.dart test/board_test.dart`.
