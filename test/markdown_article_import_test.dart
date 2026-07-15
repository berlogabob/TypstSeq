import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/markdown_article_import.dart';
import 'package:tylog_core/models.dart';
import 'package:tylog_core/storage.dart';
import 'package:typst_flutter/typst_flutter.dart';

void main() {
  Future<MarkdownTypstResult> fakeConverter({
    required String markdown,
    required String title,
    String? baseUrl,
  }) async => MarkdownTypstResult(
    typst: '= $title\n\n$markdown\n',
    diagnostics: const [],
  );

  test('maps YAML metadata and preserves nested values', () async {
    final draft = await buildMarkdownArticleDraft(
      bytes: utf8.encode('''---
title: Imported
aliases: [One, Two]
tags: ["#research", typst]
type: article
journal_day: 2026-07-14
url: https://example.com/post
custom:
  nested: [1, null, true]
nullable: null
---
# Imported

Body.
'''),
      sourceName: 'article.md',
      converter: fakeConverter,
    );

    expect(draft.title, 'Imported');
    expect(draft.date, '2026-07-14');
    expect(draft.tags, ['research', 'typst']);
    expect(draft.aliases, ['One', 'Two']);
    expect(draft.properties['custom'], {
      'nested': [1, null, true],
    });
    expect(draft.properties, containsPair('nullable', null));
    expect(draft.properties['import_format'], 'markdown');
    expect(draft.properties['import_source_name'], 'article.md');
    expect(draft.id, 'md-061128ccde4ce470');
    expect(draft.typstSource, contains('"custom": ("nested":'));
  });

  test('uses H1 and filename fallbacks and normalizes compact date', () async {
    final fromHeading = await buildMarkdownArticleDraft(
      bytes: utf8.encode('''---
date: 20260714
---
# **Fallback** title
'''),
      sourceName: 'ignored.md',
      converter: fakeConverter,
    );
    final fromFilename = await buildMarkdownArticleDraft(
      bytes: utf8.encode('Plain body'),
      sourceName: 'Filename title.markdown',
      converter: fakeConverter,
    );

    expect(fromHeading.title, 'Fallback title');
    expect(fromHeading.date, '2026-07-14');
    expect(fromFilename.title, 'Filename title');
    expect(fromFilename.id, startsWith('md-'));
  });

  test('warns and preserves a non-article source type', () async {
    final draft = await buildMarkdownArticleDraft(
      bytes: utf8.encode('''---
title: Place
type: castle
---
Body
'''),
      sourceName: 'place.md',
      converter: fakeConverter,
    );

    expect(draft.properties['source_type'], 'castle');
    expect(draft.diagnostics.single.code, 'source-type');
    expect(draft.typstSource, contains('kind: "article"'));
  });

  test('rejects malformed UTF-8 and YAML independently', () async {
    expect(
      () => buildMarkdownArticleDraft(
        bytes: [0xC3, 0x28],
        sourceName: 'bad.md',
        converter: fakeConverter,
      ),
      throwsFormatException,
    );
    expect(
      () => buildMarkdownArticleDraft(
        bytes: utf8.encode('---\ntitle: [broken\n---\nBody'),
        sourceName: 'bad-yaml.md',
        converter: fakeConverter,
      ),
      throwsFormatException,
    );
  });

  test('classifies duplicates by stable ID or URL and source hash', () async {
    final draft = await buildMarkdownArticleDraft(
      bytes: utf8.encode('''---
title: Article
url: https://example.com/same
---
Body
'''),
      sourceName: 'article.md',
      converter: fakeConverter,
    );
    final unchanged = _note(
      id: 'older-id',
      url: 'https://example.com/same',
      hash: draft.sourceHash,
    );
    final changed = _note(id: draft.id, hash: 'old-hash');

    expect(
      classifyMarkdownDuplicate(draft, [unchanged]).kind,
      MarkdownDuplicateKind.unchanged,
    );
    expect(
      classifyMarkdownDuplicate(draft, [changed]).kind,
      MarkdownDuplicateKind.changed,
    );
    expect(
      classifyMarkdownDuplicate(draft, const []).kind,
      MarkdownDuplicateKind.newArticle,
    );
  });

  test('adds collision suffixes without overwriting files', () async {
    final root = await Directory.systemTemp.createTemp('tylog-md-path-');
    addTearDown(() => root.delete(recursive: true));
    final storage = LocalVaultStorage(root);
    await storage.writeText('articles/Title.typ', 'one');
    await storage.writeText('articles/Title (2).typ', 'two');

    expect(
      await nextMarkdownArticlePath(storage, 'Title'),
      'articles/Title (3).typ',
    );
  });
}

NoteRef _note({required String id, String? url, required String hash}) =>
    NoteRef(
      id: id,
      path: 'articles/article.typ',
      title: 'Article',
      kind: 'article',
      outgoingLinks: const [],
      properties: {'url': ?url, 'import_sha256': hash},
    );
