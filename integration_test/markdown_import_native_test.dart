import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tylog/markdown_article_import.dart';
import 'package:tylog/scanner.dart';
import 'package:tylog/tylog_assets.dart';
import 'package:tylog/vault.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('imports, compiles, and queries canonical article metadata', (
    _,
  ) async {
    final root = await Directory.systemTemp.createTemp('tylog_md_native_');
    addTearDown(() => root.delete(recursive: true));
    final vault = Vault(root);
    await vault.ensureCreated();
    final draft = await buildMarkdownArticleDraft(
      bytes: utf8.encode('''---
title: Native import
tags: [markdown, test]
aliases: [Native article]
date: 2026-07-15
url: https://example.com/articles/native
custom:
  nested: true
---
# Native import

Paragraph with **bold**, [relative link](details), and `code`.

- [x] converted

| Key | Value |
| --- | --- |
| kind | article |
'''),
      sourceName: 'native.md',
    );
    final path = await nextMarkdownArticlePath(vault.storage, draft.title);
    await vault.saveNote(path, draft.typstSource);

    final inspector = await FlutterTypstInspector.create();
    try {
      final records = await inspector.inspect(
        TypstDocumentInput(
          path: path,
          source: draft.typstSource,
          files: (await TylogAssets.load()).compilerFiles,
        ),
      );
      final queried = decodeTylogMetadataRecords(records).note;
      expect(queried?['kind'], 'article');
      expect(queried?['date'], '2026-07-15');

      final index = await scanVaultStorage(
        vault.storage,
        inspector: inspector,
        force: true,
      );
      final article = index.notesByPath[path];
      expect(article?.kind, 'article');
      expect(article?.title, 'Native import');
      expect(article?.properties['url'], 'https://example.com/articles/native');
      expect(article?.properties['custom'], {'nested': true});
      expect(article?.metadataSource, 'typst-query');
    } finally {
      inspector.dispose();
    }
  });

  final smokeValue = Platform.environment['TYLOG_MARKDOWN_SMOKE_FILES'];
  testWidgets(
    'smoke converts configured Markdown articles without touching originals',
    (_) async {
      final files = smokeValue!
          .split('|')
          .map((path) => path.trim())
          .where((path) => path.isNotEmpty)
          .map(File.new)
          .toList();
      final root = await Directory.systemTemp.createTemp('tylog_md_smoke_');
      addTearDown(() => root.delete(recursive: true));
      final vault = Vault(root);
      await vault.ensureCreated();
      final inspector = await FlutterTypstInspector.create();
      try {
        for (final file in files) {
          final draft = await buildMarkdownArticleDraft(
            bytes: await file.readAsBytes(),
            sourceName: file.uri.pathSegments.last,
          );
          final path = await nextMarkdownArticlePath(
            vault.storage,
            draft.title,
          );
          await vault.saveNote(path, draft.typstSource);
          List<TypstMetadataRecord> records;
          try {
            records = await inspector.inspect(
              TypstDocumentInput(
                path: path,
                source: draft.typstSource,
                files: (await TylogAssets.load()).compilerFiles,
              ),
            );
          } catch (error) {
            final sourceLines = draft.typstSource.split('\n');
            final excerpts = RegExp(r'\[ERROR\] (\d+):')
                .allMatches(error.toString())
                .map((match) => int.parse(match.group(1)!))
                .map(
                  (line) => sourceLines
                      .skip((line - 3).clamp(0, sourceLines.length))
                      .take(5)
                      .indexed
                      .map((entry) => '${line - 2 + entry.$1}: ${entry.$2}')
                      .join('\n'),
                )
                .join('\n---\n');
            fail('${file.path}: $error\n$excerpts');
          }
          expect(
            decodeTylogMetadataRecords(records).note?['kind'],
            'article',
            reason: file.path,
          );
        }
      } finally {
        inspector.dispose();
      }
      expect(files, isNotEmpty);
    },
    skip: smokeValue == null,
  );
}
