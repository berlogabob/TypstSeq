import 'package:test/test.dart';
import 'package:tylog_core/tylog_core.dart';

NoteRef node(String id) =>
    NoteRef(id: id, path: '$id.typ', title: id, outgoingLinks: const []);

void main() {
  test('simple tree is top down and centered', () {
    final layout = layoutTree('a', {
      'a': [node('b'), node('c')],
      'b': [node('d')],
    });
    expect(layout.positions.length, 4);
    expect(layout.positions['a']!.y, lessThan(layout.positions['b']!.y));
    expect(
      layout.positions['a']!.x,
      (layout.positions['b']!.x + layout.positions['c']!.x) / 2,
    );
    expect(layout.edges.length, 3);
  });
  test('shared child appears once with both parent edges', () {
    final layout = layoutTree('a', {
      'a': [node('b'), node('c')],
      'b': [node('d')],
      'c': [node('d')],
    });
    expect(layout.positions.keys.where((id) => id == 'd'), hasLength(1));
    expect(layout.edges.where((e) => e.to == 'd').map((e) => e.from), [
      'b',
      'c',
    ]);
  });
  test('cycle terminates and retains edges', () {
    final layout = layoutTree('a', {
      'a': [node('b')],
      'b': [node('a')],
    });
    expect(layout.positions.length, 2);
    expect(layout.edges.length, 2);
  });
}
