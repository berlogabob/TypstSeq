import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/app_mobile.dart';

void main() {
  test('decideImportAction classifies source imports', () {
    final imported = <String, Set<String>>{
      'known.md': {'same'},
    };

    expect(
      decideImportAction(sourceName: 'new.md', sha: 'same', imported: imported),
      ImportSourceDecision.importNew,
    );
    expect(
      decideImportAction(
        sourceName: 'known.md',
        sha: 'same',
        imported: imported,
      ),
      ImportSourceDecision.skipUnchanged,
    );
    expect(
      decideImportAction(
        sourceName: 'known.md',
        sha: 'different',
        imported: imported,
      ),
      ImportSourceDecision.importChangedCopy,
    );
  });

  test('assignImportOutputPath suffixes existing and batch collisions', () {
    final used = <String>{};
    bool exists(String path) => path == 'notes/example.typ';

    expect(
      assignImportOutputPath('notes/example.typ', used, exists),
      'notes/example (2).typ',
    );
    expect(
      assignImportOutputPath('notes/example.typ', used, exists),
      'notes/example (3).typ',
    );
  });

  test('importedNoteBody strips generated source through the title', () {
    const typst = '''#import "/_system/tylog.typ" as tylog

= Example

First paragraph.
''';
    expect(importedNoteBody(typst), 'First paragraph.\n');
  });

  test('detectVaultDialect recognizes markers and rejects ambiguity', () {
    expect(
      detectVaultDialect(
        hasObsidianDir: true,
        hasLogseqDir: false,
        hasJournalsDir: false,
      ),
      'obsidian',
    );
    expect(
      detectVaultDialect(
        hasObsidianDir: false,
        hasLogseqDir: true,
        hasJournalsDir: false,
      ),
      'logseq',
    );
    expect(
      detectVaultDialect(
        hasObsidianDir: false,
        hasLogseqDir: false,
        hasJournalsDir: true,
      ),
      'logseq',
    );
    expect(
      detectVaultDialect(
        hasObsidianDir: true,
        hasLogseqDir: true,
        hasJournalsDir: true,
      ),
      '',
    );
  });
}
