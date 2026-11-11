import 'package:test/test.dart';
import 'package:tylog_core/tylog_core.dart';

const header =
    '#import "/_system/tylog.typ" as tylog\n'
    '#show: tylog.note.with(id: "a", title: "A", tags: ("x",))\n'
    'Body\n';
const bare = '#show: tylog.note.with(id: "a", title: "A")\nBody\n';
const computed =
    '#show: tylog.note.with(id: "a", title: "A", tags: my-tags)\nBody\n';

void main() {
  group('updateNoteTags', () {
    test('add appends to an existing literal tag list', () {
      final actual = updateNoteTags(header, add: ['y']);
      expect(
        actual,
        equals(
          '#import "/_system/tylog.typ" as tylog\n'
          '#show: tylog.note.with(id: "a", title: "A", tags: ("x", "y",))\n'
          'Body\n',
        ),
      );
    });

    test('remove empties an existing literal tag list', () {
      final actual = updateNoteTags(header, remove: 'x');
      expect(
        actual,
        equals(
          '#import "/_system/tylog.typ" as tylog\n'
          '#show: tylog.note.with(id: "a", title: "A", tags: ())\n'
          'Body\n',
        ),
      );
    });

    test('add appends to a header with no tags field', () {
      final actual = updateNoteTags(bare, add: ['y', 'x']);
      expect(
        actual,
        equals(
          '#show: tylog.note.with(id: "a", title: "A", tags: ("y", "x",),)\n'
          'Body\n',
        ),
      );
    });

    test('add leaves a computed tag list untouched', () {
      final actual = updateNoteTags(computed, add: ['y']);
      expect(actual, equals(computed));
    });
  });
}
