import 'package:test/test.dart';
import 'package:tylog_core/scanner.dart';

void main() {
  test('fallback scanner keeps ref-note target before heading', () {
    final note = scanNote(
      'notes/source.typ',
      '''#show: tylog.note.with(id: "source", title: "Source")
#tylog.ref-note("other", heading: "Deep dive")[link]
''',
    );

    expect(note.outgoingLinks, ['other']);
  });
}
