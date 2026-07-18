import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tylog_core/tylog_core.dart';

void main() {
  test('Format v1 and legacy records decode to the same values', () {
    final v1 = decodeTylogMetadataRecords(const [
      TypstMetadataRecord(
        label: '<tylog-note>',
        value: {'schema': 1, 'entity': 'note', 'id': 'n1', 'title': 'Note'},
      ),
      TypstMetadataRecord(
        label: '<tylog-tag>',
        value: {'schema': 1, 'entity': 'tag', 'name': 'core'},
      ),
    ]);
    final legacy = decodeTylogMetadataRecords(const [
      TypstMetadataRecord(
        label: '<tylog-note>',
        value: {'id': 'n1', 'title': 'Note'},
      ),
      TypstMetadataRecord(label: '<tylog-tag>', value: 'core'),
    ]);

    expect(v1.note?['id'], legacy.note?['id']);
    expect(v1.tags, legacy.tags);
  });

  test(
    'scanVaultStorage queries once and matches fallback index content',
    () async {
      final root = await Directory.systemTemp.createTemp('tylog_core_scan_');
      addTearDown(() => root.delete(recursive: true));
      final storage = LocalVaultStorage(root);
      await storage.writeText(
        'notes/a.typ',
        '''#show: tylog.note.with(id: "a", title: "A", tags: ("core",))
#tylog.ref-note("b")[B]
''',
      );
      await storage.writeText(
        'notes/b.typ',
        '#show: tylog.note.with(id: "b", title: "B")',
      );
      final inspector = _SourceInspector();

      final inspected = await scanVaultStorage(storage, inspector: inspector);
      final fallback = await scanVaultStorage(storage);

      expect(inspector.calls, 2);
      expect(inspected.backlinksByTarget, fallback.backlinksByTarget);
      expect(_stableNotes(inspected), _stableNotes(fallback));
    },
  );

  test('inspector failure warns and retains fallback backlinks', () async {
    final root = await Directory.systemTemp.createTemp('tylog_core_bad_');
    addTearDown(() => root.delete(recursive: true));
    final storage = LocalVaultStorage(root);
    await storage.writeText(
      'notes/bad.typ',
      '#show: tylog.note.with(id: "bad", title: "Bad"\n'
          '#tylog.ref-note("target")[Target]',
    );

    final index = await scanVaultStorage(
      storage,
      inspector: _FailingInspector(),
    );

    expect(index.notes.single.outgoingLinks, ['target']);
    final problem = index.problems.singleWhere(
      (problem) => problem.code == 'metadata-query-failed',
    );
    expect(problem.message, "A note's formatting couldn't be read.");
    expect(
      problem.detail,
      'Typst metadata query failed: Bad state: fixture does not compile',
    );
    expect(
      VaultIndex.fromJson(index.toJson()).problems
          .singleWhere((problem) => problem.code == 'metadata-query-failed')
          .detail,
      problem.detail,
    );
  });

  test('a hanging inspector times out and the scan still completes', () async {
    final root = await Directory.systemTemp.createTemp('tylog_core_hang_');
    final previousTimeout = typstInspectTimeout;
    typstInspectTimeout = const Duration(milliseconds: 100);
    addTearDown(() async {
      typstInspectTimeout = previousTimeout;
      await root.delete(recursive: true);
    });
    final storage = LocalVaultStorage(root);
    await storage.writeText(
      'notes/poison.typ',
      '#show: tylog.note.with(id: "poison", title: "Poison")',
    );
    await storage.writeText(
      'notes/fine.typ',
      '#show: tylog.note.with(id: "fine", title: "Fine")',
    );
    // Sorted after poison.typ: must NOT be queried once the inspector is
    // considered dead (a wedged native worker would idle out every later
    // query too), but still lands in the index via the source-based scan.
    await storage.writeText(
      'notes/z-after.typ',
      '#show: tylog.note.with(id: "z", title: "After")',
    );
    final inspector = _HangingInspector('notes/poison.typ');

    final index = await scanVaultStorage(
      storage,
      inspector: inspector,
    ).timeout(const Duration(seconds: 10));

    expect(index.notes, hasLength(3));
    expect(
      index.problems
          .where((problem) => problem.code == 'metadata-query-failed')
          .map((problem) => problem.subject),
      ['notes/poison.typ'],
    );
    // fine.typ (sorted first) was queried; z-after.typ was skipped.
    expect(inspector.queried, ['notes/fine.typ', 'notes/poison.typ']);
    expect(
      index.problems
          .where((problem) => problem.code == 'metadata-fallback')
          .map((problem) => problem.subject),
      contains('notes/z-after.typ'),
    );
  });

  test(
    'a fallback note is re-inspected once a healthy inspector is available',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'tylog_core_reinspect_',
      );
      final previousTimeout = typstInspectTimeout;
      typstInspectTimeout = const Duration(milliseconds: 100);
      addTearDown(() async {
        typstInspectTimeout = previousTimeout;
        await root.delete(recursive: true);
      });
      final storage = LocalVaultStorage(root);
      await storage.writeText(
        'notes/poison.typ',
        '#show: tylog.note.with(id: "poison", title: "Poison")',
      );
      // Sorted after poison.typ: the dead-inspector shortcut skips a real
      // query and falls back to legacy parsing, recording the flood-causing
      // 'metadata-fallback' problem this fix is about.
      await storage.writeText(
        'notes/z-after.typ',
        '#show: tylog.note.with(id: "z", title: "After")',
      );

      final first = await scanVaultStorage(
        storage,
        inspector: _HangingInspector('notes/poison.typ'),
      ).timeout(const Duration(seconds: 10));
      expect(
        first.problems
            .where((problem) => problem.code == 'metadata-fallback')
            .map((problem) => problem.subject),
        contains('notes/z-after.typ'),
      );

      // Same fingerprints (files untouched) but this pass's inspector is
      // healthy — the cached fallback note must not shortcut past it.
      final healthyInspector = _SourceInspector();
      final second = await scanVaultStorage(
        storage,
        inspector: healthyInspector,
        previous: first,
      );

      expect(healthyInspector.calls, 2);
      expect(
        second.problems.where(
          (problem) => problem.code == 'metadata-fallback',
        ),
        isEmpty,
      );
    },
  );

  test('inspection files exclude other note sources', () async {
    final root = await Directory.systemTemp.createTemp('tylog_core_files_');
    addTearDown(() => root.delete(recursive: true));
    final storage = LocalVaultStorage(root);
    await storage.writeText(
      'notes/a.typ',
      '#show: tylog.note.with(id: "a", title: "A")',
    );
    await storage.writeText(
      'articles/big.typ',
      '#show: tylog.note.with(id: "big", title: "Big")',
    );
    await storage.writeText('_system/tylog.typ', '// helper');
    await storage.writeBytes('files/photo.jpg', [1, 2, 3]);
    final inspector = _FileCapturingInspector();

    await scanVaultStorage(storage, inspector: inspector);

    expect(inspector.fileKeys, contains('_system/tylog.typ'));
    expect(inspector.fileKeys, contains('files/photo.jpg'));
    expect(inspector.fileKeys, isNot(contains('notes/a.typ')));
    expect(inspector.fileKeys, isNot(contains('articles/big.typ')));
  });

  test('fallback re-inspection is capped per scan', () async {
    final root = await Directory.systemTemp.createTemp('tylog_core_cap_');
    final previousCap = maxMetadataReinspectionsPerScan;
    maxMetadataReinspectionsPerScan = 2;
    addTearDown(() async {
      maxMetadataReinspectionsPerScan = previousCap;
      await root.delete(recursive: true);
    });
    final storage = LocalVaultStorage(root);
    for (var index = 0; index < 4; index++) {
      await storage.writeText(
        'notes/n$index.typ',
        '#show: tylog.note.with(id: "n$index", title: "N$index")',
      );
    }
    // First scan without an inspector: everything lands as fallback.
    final first = await scanVaultStorage(storage);
    // Second scan with a healthy inspector: only the cap's worth of notes
    // may be re-inspected; the rest stay cached fallbacks for later scans.
    final inspector = _SourceInspector();
    final second = await scanVaultStorage(
      storage,
      inspector: inspector,
      previous: first,
    );

    expect(inspector.calls, 2);
    expect(second.problems.where((p) => p.code == 'metadata-fallback'), hasLength(2));
  });

  test('local storage rejects traversal', () async {
    final root = await Directory.systemTemp.createTemp('tylog_core_paths_');
    addTearDown(() => root.delete(recursive: true));
    final storage = LocalVaultStorage(root);

    expect(() => storage.writeText('../outside', 'no'), throwsArgumentError);
    expect(await File('${root.parent.path}/outside').exists(), isFalse);
  });

  test(
    'suggestLinkTargets matches tags/citations/properties against note ids and titles',
    () {
      final index = VaultIndex(
        notesByPath: {
          'articles/new.typ': const NoteRef(
            id: 'md-new',
            path: 'articles/new.typ',
            title: 'New import',
            outgoingLinks: [],
            tags: ['PKM'],
            citations: ['old'],
            properties: {'related': 'Related Target'},
          ),
          'notes/pkm.typ': const NoteRef(
            id: 'PKM',
            path: 'notes/pkm.typ',
            title: 'PKM Concept',
            outgoingLinks: [],
          ),
          'articles/old.typ': const NoteRef(
            id: 'old',
            path: 'articles/old.typ',
            title: 'Old Note',
            outgoingLinks: [],
          ),
          'notes/related-target.typ': const NoteRef(
            id: 'related-target',
            path: 'notes/related-target.typ',
            title: 'Related Target',
            outgoingLinks: [],
          ),
          'notes/unrelated.typ': const NoteRef(
            id: 'unrelated',
            path: 'notes/unrelated.typ',
            title: 'Unrelated',
            outgoingLinks: [],
          ),
        },
        backlinksByTarget: const {},
      );

      final note = index.notesByPath['articles/new.typ']!;
      final targets = suggestLinkTargets(note, index);

      expect(targets, [
        'articles/old.typ',
        'notes/pkm.typ',
        'notes/related-target.typ',
      ]);
    },
  );

  test('suggestLinkTargets never suggests the note itself', () {
    final index = VaultIndex(
      notesByPath: {
        'articles/a.typ': const NoteRef(
          id: 'a',
          path: 'articles/a.typ',
          title: 'A',
          outgoingLinks: [],
          tags: ['a'],
        ),
      },
      backlinksByTarget: const {},
    );

    final note = index.notesByPath['articles/a.typ']!;
    expect(suggestLinkTargets(note, index), isEmpty);
  });
}

class _SourceInspector implements TypstInspector {
  int calls = 0;

  @override
  Future<List<TypstMetadataRecord>> inspect(TypstDocumentInput input) async {
    calls++;
    final note = scanNote(input.path, input.source);
    return [
      TypstMetadataRecord(
        label: '<tylog-note>',
        value: {
          'schema': 1,
          'entity': 'note',
          'id': note.id,
          'title': note.title,
          'kind': note.kind,
          'tags': note.tags,
          'aliases': note.aliases,
          'properties': note.properties,
        },
      ),
      for (final target in note.outgoingLinks)
        TypstMetadataRecord(
          label: '<tylog-link>',
          value: {'schema': 1, 'entity': 'link', 'target': target},
        ),
    ];
  }
}

class _FailingInspector implements TypstInspector {
  @override
  Future<List<TypstMetadataRecord>> inspect(TypstDocumentInput input) =>
      throw StateError('fixture does not compile');
}

Map<String, Object?> _stableNotes(VaultIndex index) => {
  for (final note in index.notes)
    note.path: {
      'id': note.id,
      'title': note.title,
      'kind': note.kind,
      'tags': note.tags,
      'aliases': note.aliases,
      'links': note.outgoingLinks,
      'attachments': note.attachments.map((item) => item.toJson()).toList(),
    },
};

class _HangingInspector implements TypstInspector {
  _HangingInspector(this.hangOn);
  final String hangOn;
  final queried = <String>[];
  final _delegate = _SourceInspector();

  @override
  Future<List<TypstMetadataRecord>> inspect(TypstDocumentInput input) {
    queried.add(input.path);
    if (input.path == hangOn) {
      // Simulates a Typst compile that never terminates.
      return Completer<List<TypstMetadataRecord>>().future;
    }
    return _delegate.inspect(input);
  }
}

class _FileCapturingInspector implements TypstInspector {
  final fileKeys = <String>{};
  final _delegate = _SourceInspector();

  @override
  Future<List<TypstMetadataRecord>> inspect(TypstDocumentInput input) {
    fileKeys.addAll(input.files.keys);
    return _delegate.inspect(input);
  }
}
