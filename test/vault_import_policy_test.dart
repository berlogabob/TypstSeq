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

  test('durable adapter keeps deterministic IDs and final note content', () {
    final job = legacyImportJobId('logseq', 'manifest');
    expect(job, legacyImportJobId('logseq', 'manifest'));
    expect(
      legacyImportNodeId(job, 'pages/a.md', 'sha'),
      legacyImportNodeId(job, 'pages/a.md', 'sha'),
    );
    expect(
      legacyImportNodeId(job, 'pages/a.md', 'sha'),
      isNot(legacyImportNodeId(job, 'pages/a.md', 'other')),
    );
    expect(
      materializeLegacyImportNote(
        typst: '#import "x"\n\n= A\n\nBody\n',
        current: null,
        sourceHash: 'sha',
        dialect: 'logseq',
      ),
      (content: '#import "x"\n\n= A\n\nBody\n', appended: false),
    );
    expect(
      materializeLegacyImportNote(
        typst: '#import "x"\n\n= A\n\nBody\n',
        current: '= Existing\n\nOld\n',
        sourceHash: 'sha',
        dialect: 'logseq',
      ),
      (
        content: '= Existing\n\nOld\n\n== From Logseq\n\nBody\n',
        appended: true,
      ),
    );
  });

  test('completed import rerun reports unchanged notes', () {
    expect(
      completedImportUnchangedCount(
        sourcePaths: ['pages/a.md', 'journals/2025_01_01.md'],
        sourceHashes: {'pages/a.md': 'a', 'journals/2025_01_01.md': 'b'},
        imported: {
          'a.md': {'a'},
          '2025_01_01.md': {'b'},
        },
      ),
      2,
    );
  });

  test(
    'resumed imports recover unique asset references from committed nodes',
    () {
      expect(
        legacyImportedAssetPaths([
          '{"referenced_assets":["assets/logo.png","assets/x.png"]}',
          '{"referenced_assets":["assets/x.png","assets/diagram.svg"]}',
        ]),
        {'assets/logo.png', 'assets/x.png', 'assets/diagram.svg'},
      );
    },
  );

  test('resumed imports reconstruct full note counters', () {
    expect(
      legacyImportedCounts([
        '{"import_is_journal":false,"import_changed_copy":true}',
        '{"import_is_journal":true,"import_appended":true}',
        '{"import_is_journal":true,"import_appended":false}',
      ]),
      (pages: 1, journals: 2, appended: 1, changedCopies: 1),
    );
  });

  test('partial import report is not labelled complete', () {
    expect(vaultImportReportTitle(true), 'Vault import complete');
    expect(vaultImportReportTitle(false), 'Vault import paused');
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
