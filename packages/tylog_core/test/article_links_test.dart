import 'dart:io';

import 'package:test/test.dart';
import 'package:tylog_core/tylog_core.dart';

void main() {
  const day =
      '= 2026-10-24\n\n'
      '- 10:27 \n'
      r'+ https://www.reddit.com/r/unsloth/comments/1wz/google\_releases\_gemma/'
      '\n'
      '+ see https://github.com/VERT-sh/VERT.\n'
      '+ #link("https://kept.example/x")[kept]\n'
      '// https://comment.example/\n'
      '+ #tylog.ref-note("a")[done https://inside.example/]\n';
  final article = NoteRef(
    id: 'art-1',
    path: 'articles/a.typ',
    title: 'Google releases [Gemma]',
    outgoingLinks: const [],
  );

  test('finds bare links only, unescaped, without trailing punctuation', () {
    expect(bareLinks(day).map((l) => l.url), [
      'https://www.reddit.com/r/unsloth/comments/1wz/google_releases_gemma/',
      'https://github.com/VERT-sh/VERT',
    ]);
  });

  test('replaces the bare link with a titled article link, once', () {
    const url =
        'https://www.reddit.com/r/unsloth/comments/1wz/google_releases_gemma/';
    final out = linkArticle(day, url, article);
    expect(
      out,
      contains(
        r'+ #tylog.ref-note("art-1")[Google releases \[Gemma\]]'
        '\n',
      ),
    );
    expect(linkArticle(out, url, article), out);
    expect(linkArticle(day, 'https://nowhere.example/', article), day);
  });

  test('the result compiles', () {
    if (Process.runSync('which', ['typst']).exitCode != 0) {
      markTestSkipped('typst not on PATH');
      return;
    }
    final root = Directory.current.path.endsWith('packages/tylog_core')
        ? Directory.current.parent.parent.path
        : Directory.current.path;
    final dir = Directory('$root/.dart_tool/tylog_article_links_test')
      ..createSync(recursive: true);
    addTearDown(() => dir.deleteSync(recursive: true));
    final out = linkArticle(day, 'https://github.com/VERT-sh/VERT', article);
    final file = File('${dir.path}/d.typ')
      ..writeAsStringSync('#import "/typst/tylog/lib.typ" as tylog\n$out');
    final result = Process.runSync('typst', [
      'compile',
      '--root',
      root,
      file.path,
      '${file.path}.pdf',
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}\n$out');
  });
}
