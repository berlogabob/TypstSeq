import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/models.dart';
import 'package:tylog/report.dart';

void main() {
  const index = VaultIndex(
    notesByPath: {
      'daily/2026/07/2026-07-01.typ': NoteRef(
        id: '2026-07-01',
        path: 'daily/2026/07/2026-07-01.typ',
        title: '2026-07-01',
        kind: 'daily',
        date: '2026-07-01',
        project: 'phd',
        tags: ['research'],
        outgoingLinks: [],
      ),
      'articles/paper.typ': NoteRef(
        id: 'paper',
        path: 'articles/paper.typ',
        title: 'Paper',
        kind: 'article',
        project: 'phd',
        tags: ['research'],
        properties: {'status': 'summarized'},
        outgoingLinks: [],
      ),
      'notes/personal.typ': NoteRef(
        id: 'personal',
        path: 'notes/personal.typ',
        title: 'Personal',
        kind: 'note',
        outgoingLinks: [],
      ),
    },
    backlinksByTarget: {},
  );

  test('report filters project, kind, tag, date, and article status', () {
    expect(
      selectReportNotes(
        index,
        const ReportFilter(project: 'phd', tags: {'research'}),
      ).map((note) => note.id),
      ['paper', '2026-07-01'],
    );
    expect(
      selectReportNotes(
        index,
        const ReportFilter(kinds: {'article'}, articleStatus: 'summarized'),
      ).single.id,
      'paper',
    );
    expect(
      selectReportNotes(
        index,
        const ReportFilter(from: '2026-07-01', to: '2026-07-31'),
      ).single.id,
      '2026-07-01',
    );
  });

  test('report source is ordinary deterministic Typst', () {
    final source = generateReportSource(
      'July report',
      selectReportNotes(index, const ReportFilter(project: 'phd')),
    );
    expect(source, startsWith('#import "/_system/export.typ" as export'));
    expect(source, contains('#export.report("July report", ['));
    expect(
      source.indexOf('articles/paper.typ'),
      lessThan(source.indexOf('daily/2026')),
    );
    // No citations in these notes: no bibliography section.
    expect(source, isNot(contains('#bibliography')));
  });

  test('report with cited notes appends the vault bibliography', () {
    const cited = NoteRef(
      id: 'paper',
      path: 'articles/paper.typ',
      title: 'Paper',
      kind: 'article',
      citations: ['smith-2026'],
      outgoingLinks: [],
    );
    final source = generateReportSource('Cited report', const [cited]);
    expect(source, contains('#bibliography("/_system/bibliography.yml")'));
  });
}
