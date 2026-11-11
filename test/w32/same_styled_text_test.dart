import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/rich_editor.dart';

// The per-character list comparison sameStyledText replaced.
bool _reference(TyLogDocument a, TyLogDocument b) {
  List<Object> chars(TyLogDocument d) => d.blocks
      .expand((block) => block.parts)
      .expand(
        (p) => p.text
            .split('')
            .where((c) => c != '\n')
            .map((c) => (c, p.style, p.source)),
      )
      .toList();
  return listEquals(chars(a), chars(b));
}

void main() {
  const header =
      '#import "/_system/tylog.typ" as tylog\n'
      '#show: tylog.note.with(id: "n", title: "N")\n\n';

  test('agrees with the per-character comparison', () {
    final sources = [
      '${header}plain text\n',
      '${header}plain text\n\n\n',
      '${header}plain *bold* text\n',
      '${header}plain _bold_ text\n',
      '${header}plain text!\n',
      '$header- one\n- two\n',
      '$header- one\n- two\n\n',
      '${header}see #link("https://a.io")[a] here\n',
      '${header}see #link("https://b.io")[a] here\n',
      header,
    ];
    final docs = [for (final s in sources) TyLogDocument.parse(s)];
    for (final a in docs) {
      for (final b in docs) {
        expect(sameStyledText(a, b), _reference(a, b));
      }
    }
  });

  test('a 200k-character note compares in well under a frame budget x10', () {
    final body = List.filled(
      4000,
      'Some *styled* words and a plain tail here.',
    ).join('\n');
    expect(body.length, greaterThan(160000));
    final a = TyLogDocument.parse('$header$body\n');
    final b = TyLogDocument.parse('$header$body\n\n');
    final watch = Stopwatch()..start();
    expect(sameStyledText(a, b), isTrue);
    final fast = watch.elapsedMicroseconds;
    watch
      ..reset()
      ..start();
    expect(_reference(a, b), isTrue);
    final slow = watch.elapsedMicroseconds;
    // ignore: avoid_print
    print(
      'sameStyledText ${fast / 1000} ms, per-character lists ${slow / 1000} ms',
    );
    expect(fast, lessThan(160000));
  });
}
