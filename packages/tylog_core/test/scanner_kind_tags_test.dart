import 'dart:io';

import 'package:test/test.dart';
import 'package:tylog_core/scanner.dart';
import 'package:tylog_core/storage.dart';

/// Kinds double as tags so the existing tag filter UI can slice by
/// article/person/daily with zero new UI (plan: "Kinds become tags").
/// Index-only — the note's own text is never rewritten. The default kind
/// `note` is deliberately NOT aliased: a mega-tag on every plain note
/// carries no filtering information.
class _Inspector implements TypstInspector {
  @override
  Future<List<TypstMetadataRecord>> inspect(TypstDocumentInput input) async {
    final kind = RegExp(r'kind: "([^"]*)"').firstMatch(input.source)?.group(1);
    return [
      TypstMetadataRecord(
        label: '<tylog-note>',
        value: {
          'schema': 1,
          'entity': 'note',
          'id': input.path.split('/').last.replaceFirst('.typ', ''),
          'title': 'T',
          'kind': kind ?? 'note',
          'tags': ['existing'],
        },
      ),
    ];
  }
}

String _note(String id, String kind) =>
    '#show: tylog.note.with(id: "$id", title: "T", kind: "$kind")\n';

void main() {
  late Directory root;
  late LocalVaultStorage storage;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('tylog-kind-tags');
    storage = LocalVaultStorage(root);
  });

  tearDown(() => root.delete(recursive: true));

  test('queried path: non-default kinds surface as tags, note does not',
      () async {
    await storage.writeText('articles/a.typ', _note('a', 'article'));
    await storage.writeText('notes/p.typ', _note('p', 'person'));
    await storage.writeText('notes/n.typ', _note('n', 'note'));

    final index = await scanVaultStorage(storage, inspector: _Inspector());
    final byId = {for (final n in index.notes) n.id: n};

    expect(byId['a']!.tags, containsAll(['article', 'existing']));
    expect(byId['p']!.tags, contains('person'));
    expect(byId['n']!.tags, isNot(contains('note')));
  });

  test('fallback path: kind aliases into tags too', () async {
    await storage.writeText('articles/f.typ', _note('f', 'article'));

    final index = await scanVaultStorage(storage); // no inspector → fallback
    expect(index.notes.single.tags, contains('article'));
  });

  test('literal wikilinks are indexed as outgoing links', () async {
    // A typed-out [[X]] used to be dead text: shown as a link by the excerpt
    // matcher but invisible to backlinks and the graph. Index-only fix — the
    // note text keeps its literal brackets.
    await storage.writeText(
      'notes/w.typ',
      '${_note('w', 'note')}See [[Target Page]] and [[Other|shown text]].\n',
    );

    final queried = await scanVaultStorage(storage, inspector: _Inspector());
    final withInspector = queried.notes.singleWhere((n) => n.id == 'w');
    expect(withInspector.outgoingLinks, contains('Target Page'));
    expect(withInspector.outgoingLinks, contains('Other'));

    final fallback = await scanVaultStorage(storage); // no inspector
    final parsed = fallback.notes.singleWhere((n) => n.id == 'w');
    expect(parsed.outgoingLinks, contains('Target Page'));
    expect(parsed.outgoingLinks, contains('Other'));
  });

  test('kind respects tag synonyms', () async {
    await storage.writeText(
      '_system/tag-synonyms.json',
      '{"schema": 1, "synonyms": {"article": "paper"}}',
    );
    await storage.writeText('articles/s.typ', _note('s', 'article'));

    final index = await scanVaultStorage(storage, inspector: _Inspector());
    expect(index.notes.single.tags, contains('paper'));
    expect(index.notes.single.tags, isNot(contains('article')));
  });
}
