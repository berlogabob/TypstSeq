import 'dart:io';
import 'dart:collection';
import 'package:test/test.dart';
import 'package:tylog_core/tylog_core.dart';

class _CountedLines extends ListBase<String> {
  _CountedLines(this.lines);
  final List<String> lines;
  int traversals = 0;
  @override
  int get length => lines.length;
  @override
  set length(int value) => throw UnsupportedError('read only');
  @override
  String operator [](int index) => lines[index];
  @override
  void operator []=(int index, String value) =>
      throw UnsupportedError('read only');
  @override
  Iterator<String> get iterator {
    traversals++;
    return lines.iterator;
  }
}

void main() {
  test('configured markers skip discovery over cached daily lines', () async {
    final dir = await Directory.systemTemp.createTemp('issue-discovery');
    addTearDown(() => dir.delete(recursive: true));
    final storage = LocalVaultStorage(dir);
    await storage.writeText(
      '_system/settings/ai.json',
      '{"tasks":{"enrich":{"markers":["fixit"]}}}',
    );
    await storage.writeText(
      'notes/project.typ',
      '#show: tylog.note.with(id: "project", title: "Project", kind: "project")',
    );
    await storage.writeText('daily/2026-01-01.typ', '- fixit Project bug');
    final first = await scanVaultStorage(storage);
    final lines = _CountedLines(first.issueLines['daily/2026-01-01.typ']!);
    final cached = VaultIndex(
      notesByPath: first.notesByPath,
      backlinksByTarget: first.backlinksByTarget,
      issueLines: {...first.issueLines, 'daily/2026-01-01.typ': lines},
    );
    final second = await scanVaultStorage(storage, previous: cached);
    expect(second.issues.map((issue) => issue.marker), ['fixit']);
    expect(lines.traversals, 1);
  });

  test('status is inserted before a comment', () {
    const text = '- issue // #metadata(("tylog-issue-status": "done"))';
    const issue = IssueRef(
      notePath: 'x',
      line: 1,
      text: text,
      projectId: 'p',
      marker: 'fixit',
    );
    expect(
      setIssueStatus(text, issue, 'doing'),
      '- issue #metadata(("tylog-issue-status": "doing")) // #metadata(("tylog-issue-status": "done"))',
    );
  });
  test('detects linked and plain markers only with project links', () async {
    final dir = await Directory.systemTemp.createTemp('issues');
    addTearDown(() => dir.delete(recursive: true));
    final storage = LocalVaultStorage(dir);
    await storage.writeText(
      '_system/settings/ai.json',
      '{"tasks":{"enrich":{"markers":["fixit"]}}}',
    );
    await storage.writeText(
      'notes/project.typ',
      '#show: tylog.note.with(id: "project", title: "Project", kind: "project")',
    );
    await storage.writeText(
      'notes/person.typ',
      '#show: tylog.note.with(id: "person", title: "Person", kind: "person")',
    );
    await storage.writeText(
      'notes/fixit.typ',
      '#show: tylog.note.with(id: "fixit", title: "fixit")',
    );
    await storage.writeText(
      'notes/log.typ',
      '- #tylog.ref-note("project")[Project] #tylog.ref-note("fixit")[fixit] bug // #metadata(("tylog-issue-status": "done"))\n- fixit #tylog.ref-note("project")[Project] bug\n- #tylog.ref-note("person")[Person] #tylog.ref-note("fixit")[fixit] no\n',
    );
    final index = await scanVaultStorage(storage);
    expect(index.issues.map((i) => i.line), [1, 2]);
    expect(index.issues.first.status, 'todo');
    expect(VaultIndex.fromJson(index.toJson()).issues.length, 2);
  });
  test(
    'detects plain project names and markers and upgrades cached candidates',
    () async {
      final dir = await Directory.systemTemp.createTemp('plain-issues');
      addTearDown(() => dir.delete(recursive: true));
      final storage = LocalVaultStorage(dir);
      await storage.writeText(
        '_system/settings/ai.json',
        '{"tasks":{"enrich":{"markers":["fixit"]}}}',
      );
      await storage.writeText(
        'notes/project.typ',
        '#show: tylog.note.with(id: "project", title: "TyLog", kind: "project", aliases: ("TLApp",))',
      );
      await storage.writeText(
        'notes/person.typ',
        '#show: tylog.note.with(id: "person", title: "Alice", kind: "person")',
      );
      const source =
          '- 10:44 fixit TyLog audio and screenshots...\n'
          '- 20:19 fixit TyLog@fixit add feature...\n'
          '- 11:40 TyLog fixit screenshots library...\n'
          '- FIXIT tlapp alias\n'
          '- fixity TyLog no\n'
          '- fixit Alice no';
      await storage.writeText('daily/2026-01-01.typ', source);
      final first = await scanVaultStorage(storage);
      expect(first.issues.map((i) => i.line), [1, 2, 3, 4]);
      final old = first.toJson();
      old['version'] = kVaultIndexVersion - 1;
      old['issueLines'] = <String, Object>{};
      final rebuilt = await scanVaultStorage(
        storage,
        previous: VaultIndex.fromJson(old),
      );
      expect(rebuilt.issues.map((i) => i.line), [1, 2, 3, 4]);
      expect(
        setIssueStatus(source, rebuilt.issues.first, 'done'),
        source.replaceFirst(
          'screenshots...',
          'screenshots... #metadata(("tylog-issue-status": "done"))',
        ),
      );
    },
  );

  test('cached notes without issue lines are read before reuse', () async {
    final dir = await Directory.systemTemp.createTemp('issue-cache');
    addTearDown(() => dir.delete(recursive: true));
    final storage = LocalVaultStorage(dir);
    await storage.writeText(
      '_system/settings/ai.json',
      '{"tasks":{"enrich":{"markers":["fixit"]}}}',
    );
    await storage.writeText(
      'notes/project.typ',
      '#show: tylog.note.with(id: "project", title: "Project", kind: "project")',
    );
    await storage.writeText(
      'notes/log.typ',
      '- fixit #tylog.ref-note("project")[Project] bug',
    );
    final first = await scanVaultStorage(storage);
    final oldCache = VaultIndex(
      notesByPath: first.notesByPath,
      backlinksByTarget: first.backlinksByTarget,
      tasks: first.tasks,
    );
    final rebuilt = await scanVaultStorage(storage, previous: oldCache);
    expect(rebuilt.issues.map((i) => i.marker), ['fixit']);
  });

  test(
    'maintenance publishes issue changes when only marker settings change',
    () async {
      final dir = await Directory.systemTemp.createTemp('issue-settings');
      addTearDown(() => dir.delete(recursive: true));
      final storage = LocalVaultStorage(dir);
      await storage.writeText(
        'notes/project.typ',
        '#show: tylog.note.with(id: "project", title: "Project", kind: "project")',
      );
      await storage.writeText(
        'notes/log.typ',
        '- fixit #tylog.ref-note("project")[Project] bug',
      );
      await storage.writeText(
        '_system/settings/ai.json',
        '{"tasks":{"enrich":{"markers":[]}}}',
      );
      final maintenance = VaultMaintenance(storage, publishDonor: false);
      expect((await maintenance.buildIndex()).issues, isEmpty);
      await storage.writeText(
        '_system/settings/ai.json',
        '{"tasks":{"enrich":{"markers":["fixit"]}}}',
      );
      expect((await maintenance.buildIndex()).issues.map((i) => i.marker), [
        'fixit',
      ]);
      expect((await loadVaultIndex(storage))!.issues.map((i) => i.marker), [
        'fixit',
      ]);
    },
  );

  test('donor carries issue candidates for unchanged notes', () async {
    final dir = await Directory.systemTemp.createTemp('issue-donor');
    addTearDown(() => dir.delete(recursive: true));
    final storage = LocalVaultStorage(dir);
    await storage.writeText(
      '_system/settings/ai.json',
      '{"tasks":{"enrich":{"markers":["fixit"]}}}',
    );
    await storage.writeText(
      'notes/project.typ',
      '#show: tylog.note.with(id: "project", title: "Project", kind: "project")',
    );
    await storage.writeText(
      'notes/log.typ',
      '- fixit #tylog.ref-note("project")[Project] bug',
    );
    final first = await scanVaultStorage(storage);
    final donors = IndexDonorStore(storage);
    await donors.publish('one', first);
    final donor = await donors.load('two');
    expect(donor, isNotNull);
    expect(donor!.issueLines['notes/log.typ'], isNotEmpty);
    final rebuilt = await scanVaultStorage(storage, donor: donor);
    expect(rebuilt.issues.map((issue) => issue.marker), ['fixit']);
  });

  test('status edits preserve the line and reject stale source', () {
    const text =
        '- #tylog.ref-note("p")[P] #tylog.ref-note("fixit")[fixit] bug';
    const issue = IssueRef(
      notePath: 'x',
      line: 1,
      text: text,
      projectId: 'p',
      marker: 'fixit',
    );
    final result = setIssueStatus('$text\nnext', issue, 'doing');
    expect(result, '$text #metadata(("tylog-issue-status": "doing"))\nnext');
    expect(
      () => setIssueStatus('changed\n$text', issue, 'done'),
      throwsStateError,
    );
    final updated = IssueRef(
      notePath: 'x',
      line: 1,
      text: result.split('\n').first,
      projectId: 'p',
      marker: 'fixit',
    );
    expect(
      setIssueStatus(result, updated, 'done'),
      '$text #metadata(("tylog-issue-status": "done"))\nnext',
    );
  });
  test('scope follows descendants', () {
    const index = VaultIndex(
      notesByPath: {
        'p': NoteRef(id: 'p', path: 'p', title: 'P', outgoingLinks: []),
        'c': NoteRef(
          id: 'c',
          path: 'c',
          title: 'C',
          outgoingLinks: [],
          partOf: ['p'],
        ),
        'g': NoteRef(
          id: 'g',
          path: 'g',
          title: 'G',
          outgoingLinks: [],
          partOf: ['c'],
        ),
      },
      backlinksByTarget: {},
      issues: [
        IssueRef(
          notePath: 'x',
          line: 1,
          text: 'a',
          projectId: 'p',
          marker: 'fixit',
        ),
        IssueRef(
          notePath: 'x',
          line: 2,
          text: 'b',
          projectId: 'g',
          marker: 'fixit',
        ),
        IssueRef(
          notePath: 'x',
          line: 3,
          text: 'c',
          projectId: 'other',
          marker: 'fixit',
        ),
      ],
    );
    expect(issuesForEntity('p', index).map((i) => i.line), [1, 2]);
    expect(hasBoardItems('p', index), isTrue);
    expect(
      hasBoardItems(
        'other',
        const VaultIndex(notesByPath: {}, backlinksByTarget: {}),
      ),
      isFalse,
    );
  });
}
