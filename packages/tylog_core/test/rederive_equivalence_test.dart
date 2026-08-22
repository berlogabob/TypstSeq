import 'dart:io';

import 'package:test/test.dart';
import 'package:tylog_core/models.dart';
import 'package:tylog_core/scanner.dart';
import 'package:tylog_core/storage.dart';

/// Re-derivation is only safe if it produces *exactly* what a full recompile
/// would. If it drifts, a derive-only bump would leave the fleet quietly
/// disagreeing about tags and links — worse than the recompile it replaces,
/// because nothing would report it.
class _Inspector implements TypstInspector {
  var inspected = 0;

  @override
  Future<List<TypstMetadataRecord>> inspect(TypstDocumentInput input) async {
    inspected++;
    final id = input.path.split('/').last.replaceFirst('.typ', '');
    return [
      TypstMetadataRecord(
        label: '<tylog-note>',
        value: {
          'schema': 1,
          'entity': 'note',
          'id': id,
          'title': 'Title $id',
          'kind': 'article',
          'tags': ['Queried', 'shared'],
          'properties': <String, Object?>{},
        },
      ),
      const TypstMetadataRecord(
        label: '<tylog-link>',
        value: {'schema': 1, 'entity': 'link', 'target': 'queried-target'},
      ),
      const TypstMetadataRecord(
        label: '<tylog-tag>',
        value: {'schema': 1, 'entity': 'tag', 'name': 'from-tag-record'},
      ),
      const TypstMetadataRecord(
        label: '<tylog-date>',
        value: {
          'schema': 1,
          'entity': 'date',
          'date': '2026-08-21',
          'text': 'a date',
        },
      ),
      const TypstMetadataRecord(
        label: '<tylog-attachment>',
        value: {
          'schema': 1,
          'entity': 'attachment',
          'path': 'assets/a.png',
          'kind': 'image',
          'title': 'Pic',
        },
      ),
    ];
  }
}

void main() {
  test('a re-derived note is identical to a recompiled one', () async {
    final root = await Directory.systemTemp.createTemp('tylog_rederive_');
    addTearDown(() => root.delete(recursive: true));
    final storage = LocalVaultStorage(root);

    // Source carrying every source-parsed contribution: legacy tags, a legacy
    // source link, a wiki link, a legacy date and a citation — the fields whose
    // unions with the query output cannot be taken apart afterwards.
    await storage.writeText(
      'notes/a.typ',
      '#import "/_system/tylog.typ" as tylog\n'
      'tags:: #Alpha #beta\n'
      'source:: [[Origin Note]]\n'
      'journal-day:: [[2026-08-19]]\n'
      '\n'
      '= Title\n'
      'A link to [[Another Note]] and a citation @somekey here.\n',
    );

    final inspector = _Inspector();
    final full = await scanVaultStorage(storage, inspector: inspector);
    expect(inspector.inspected, 1);

    // Same vault, same bytes, but the derivation version moved on.
    final older = VaultIndex(
      version: kVaultIndexVersion - 1,
      notesByPath: full.notesByPath,
      backlinksByTarget: full.backlinksByTarget,
      tasks: full.tasks,
    );
    inspector.inspected = 0;
    final rederived = await scanVaultStorage(
      storage,
      inspector: inspector,
      previous: older,
    );
    expect(inspector.inspected, 0, reason: 'no Typst compile may happen');

    final a = full.notesByPath['notes/a.typ']!;
    final b = rederived.notesByPath['notes/a.typ']!;
    expect(b.tags, a.tags);
    expect(b.outgoingLinks, a.outgoingLinks);
    expect(b.citations, a.citations);
    expect(b.dateRefs.map((d) => d.date), a.dateRefs.map((d) => d.date));
    expect(b.attachments.map((x) => x.path), a.attachments.map((x) => x.path));
    expect(b.fileRefs, a.fileRefs);
    expect(b.title, a.title);
    expect(b.kind, a.kind);
    expect(b.metadataSource, 'typst-query');
    // The whole serialised form, so a field added later cannot quietly escape
    // this check.
    expect(b.toJson(), a.toJson());
  });

  test('queryVersion survives a round trip through the index file', () {
    // It used to be defaulted on read rather than persisted, so a cached index
    // written before a query bump would read back as *current* and its stale
    // facts would be trusted for re-derivation. Found on the P30, whose
    // index.json carried 6,208 sets of queryFacts and no queryVersion at all.
    final index = VaultIndex(
      notesByPath: const {},
      backlinksByTarget: const {},
    );
    expect(index.queryVersion, kVaultQueryVersion);
    expect(
      VaultIndex.fromJson(index.toJson()).queryVersion,
      kVaultQueryVersion,
    );

    // And an index from before the field existed must not claim to be current.
    final legacy = index.toJson()..remove('queryVersion');
    expect(
      VaultIndex.fromJson(legacy).queryVersion,
      isNot(kVaultQueryVersion),
      reason: 'it cannot vouch for which query produced it',
    );
  });

  test('an index whose queryVersion is unknown is not re-derived', () async {
    final root = await Directory.systemTemp.createTemp('tylog_rederive3_');
    addTearDown(() => root.delete(recursive: true));
    final storage = LocalVaultStorage(root);
    await storage.writeText(
      'notes/a.typ',
      '#import "/_system/tylog.typ" as tylog\n\n= Title\n',
    );

    final inspector = _Inspector();
    final full = await scanVaultStorage(storage, inspector: inspector);

    // Exactly what a pre-version-10 index.json deserialises to.
    final legacy = VaultIndex.fromJson(
      VaultIndex(
        version: kVaultIndexVersion - 1,
        notesByPath: full.notesByPath,
        backlinksByTarget: full.backlinksByTarget,
      ).toJson()..remove('queryVersion'),
    );
    inspector.inspected = 0;
    await scanVaultStorage(storage, inspector: inspector, previous: legacy);

    expect(
      inspector.inspected,
      1,
      reason: 'unknown query provenance must force a real inspection',
    );
  });

  test('re-derivation picks up an edit to the source-parsed half', () async {
    final root = await Directory.systemTemp.createTemp('tylog_rederive2_');
    addTearDown(() => root.delete(recursive: true));
    final storage = LocalVaultStorage(root);
    await storage.writeText(
      'notes/a.typ',
      '#import "/_system/tylog.typ" as tylog\ntags:: #Alpha\n\n= Title\n',
    );

    final inspector = _Inspector();
    final full = await scanVaultStorage(storage, inspector: inspector);
    expect(full.notesByPath['notes/a.typ']!.tags, contains('alpha'));

    // A synonym map that folds alpha into omega is exactly the kind of change
    // that used to require recompiling every note in the vault (index v8).
    await storage.writeText(
      '_system/tag-synonyms.json',
      '{"synonyms": {"alpha": "omega"}}',
    );
    final older = VaultIndex(
      version: kVaultIndexVersion - 1,
      notesByPath: full.notesByPath,
      backlinksByTarget: full.backlinksByTarget,
    );
    inspector.inspected = 0;
    final rederived = await scanVaultStorage(
      storage,
      inspector: inspector,
      previous: older,
    );

    expect(inspector.inspected, 0);
    expect(rederived.notesByPath['notes/a.typ']!.tags, contains('omega'));
    expect(
      rederived.notesByPath['notes/a.typ']!.tags,
      isNot(contains('alpha')),
      reason: 'the old folding must not survive the re-derivation',
    );
  });
}
