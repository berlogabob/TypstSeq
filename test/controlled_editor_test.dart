import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/controlled_editor.dart';

void main() {
  test('controlled parser hides source behind clean block previews', () {
    const source = '''#import "/_system/tylog.typ" as tylog
#show: tylog.note.with(id: "a", title: "A", kind: "note")

= Heading

#strong[Visible] and #tylog.tag("topic")

#custom-function()[Keep exactly]
''';
    final document = parseControlledTypst(source);
    expect(document.blocks.map((block) => block.kind), [
      ControlledBlockKind.heading,
      ControlledBlockKind.paragraph,
      // Cleanly delimited unknown calls stay in an editable paragraph.
      ControlledBlockKind.paragraph,
    ]);
    expect(document.blocks.map(controlledBlockPreview), [
      'Heading',
      'Visible and topic',
      'Keep exactly',
    ]);
    expect(
      document.replaceBlock(1, '#strong[Changed]'),
      contains('#custom-function()[Keep exactly]'),
    );
  });

  test('adjacent heading and task remain separate styled blocks', () {
    const source = '''== header from mac
#tylog.task(
  id: "task-1",
  text: "Launch update",
  due: "2026-07-06",
  project: none,
)
= Next heading''';

    final document = parseControlledTypst(source);

    expect(document.blocks.map((block) => block.kind), [
      ControlledBlockKind.heading,
      ControlledBlockKind.task,
      ControlledBlockKind.heading,
    ]);
    expect(document.blocks.map(controlledBlockPreview), [
      'header from mac',
      'Launch update',
      'Next heading',
    ]);
    expect(document.blocks[1].source, startsWith('#tylog.task('));
    expect(document.blocks[1].source, endsWith(')'));
  });

  test('Magic actions emit escaped valid TyLog Typst', () {
    final linked = applyMagicEdit(
      'Amazon',
      const TextSelection(baseOffset: 0, extentOffset: 6),
      const MagicRequest(
        action: MagicAction.noteLink,
        id: 'amazon',
        value: 'Amazon',
      ),
    );
    expect(linked.text, '#tylog.ref-note("amazon")[Amazon]');

    final task = applyMagicEdit(
      'write "report"',
      const TextSelection(baseOffset: 0, extentOffset: 14),
      const MagicRequest(
        action: MagicAction.task,
        id: 'task-1',
        due: '2026-07-13',
        project: 'phd',
      ),
    );
    expect(task.text, contains(r'text: "write \"report\""'));
    expect(task.text, contains('due: "2026-07-13"'));
    expect(task.text, contains('project: "phd"'));
  });

  test(
    'format, date, attachment, table, and citation actions are deterministic',
    () {
      SourceEdit edit(MagicRequest request, [String source = 'x']) =>
          applyMagicEdit(
            source,
            TextSelection(baseOffset: 0, extentOffset: source.length),
            request,
          );

      expect(
        edit(const MagicRequest(action: MagicAction.bold)).text,
        '#strong[x]',
      );
      expect(
        edit(const MagicRequest(action: MagicAction.italic)).text,
        '#emph[x]',
      );
      expect(
        edit(
          const MagicRequest(action: MagicAction.date, value: '2026-07-13'),
        ).text,
        '#tylog.date-ref("2026-07-13")[x]',
      );
      expect(
        edit(
          const MagicRequest(action: MagicAction.citation, value: 'smith-2026'),
        ).text,
        '@smith-2026',
      );
      expect(
        edit(
          const MagicRequest(
            action: MagicAction.attachment,
            value: '/assets/a.pdf',
          ),
        ).text,
        '#tylog.attachment("/assets/a.pdf", kind: "file")[x]',
      );
      expect(
        edit(
          const MagicRequest(action: MagicAction.table, rows: 2, columns: 2),
        ).text,
        '#table(columns: 2, [], [], [], [])',
      );
    },
  );
}
