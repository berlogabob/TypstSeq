import 'dart:io';

import 'package:test/test.dart';
import 'package:tylog_core/tylog_core.dart';

const equipment = NoteRef(
  id: 'eq',
  path: 'eq.typ',
  title: 'Microscope',
  kind: 'equipment',
  outgoingLinks: [],
);
const conflict = TaskRef(
  id: 'old',
  notePath: 'old.typ',
  text: 'old',
  status: 'doing',
  properties: {
    'loan': true,
    'equipment': ['eq'],
  },
);
final now = DateTime.utc(2026, 11, 12, 10);

class Fake {
  Fake(this.source)
    : sidecar = {
        'content_sha': enrichContentSha(source),
        'loans': [
          {'line': 1},
          {'line': 2},
        ],
        'mentions': [
          {'line': 2},
        ],
      };
  String source;
  Map<String, Object?> sidecar;
  final calls = <String>[];
  bool confirm = true;
  bool changeBeforeMutation = false;
  Future<bool> accept(EnrichLoanOffer offer, {TaskRef? existing}) => acceptLoan(
    path: 'day.typ',
    offer: offer,
    conflict: existing,
    noteId: () => 'day',
    now: () => now,
    confirmDouble: (_) async {
      calls.add('confirm');
      return confirm;
    },
    recordFeedback: () async {
      calls.add('feedback:${offer.line}');
    },
    readSource: () async {
      calls.add('source');
      return source;
    },
    readMentions: () async {
      calls.add('mentions');
      return EnrichMentions(
        note: 'day',
        contentSha: sidecar['content_sha'] as String,
      );
    },
    mutateNote: (change) async {
      calls.add('mutate');
      if (changeBeforeMutation) source += 'changed';
      source = change(source);
      return true;
    },
    mutationIsCurrent: (tracked) => source == tracked,
    readSidecar: () async {
      calls.add('readSidecar');
      return sidecar;
    },
    writeSidecar: (value) async {
      calls.add('writeSidecar');
      sidecar = value;
    },
  );
}

EnrichLoanOffer offer(int line, String text) => EnrichLoanOffer(
  line: line,
  text: text,
  ledgerSurface: text,
  equipment: [equipment],
);
void main() {
  test('accept writes exact task and shifts later sidecar lines', () async {
    final fake = Fake('- Borrowed Microscope\n- Later\n');
    final loan = offer(1, 'Borrowed Microscope');
    expect(await fake.accept(loan), isTrue);
    expect(
      fake.source,
      '#tylog.task(\n'
      '  id: "${loanTaskId('day', loan)}",\n'
      '  text: "Borrowed Microscope",\n'
      '  properties: ("loan": true, "equipment": ("eq",), "clocked": (("2026-11-12T10:00:00.000Z", none),),),\n'
      '  status: "doing",\n'
      ')\n- Later\n',
    );
    expect(fake.sidecar['loans'], [
      {'line': 1},
      {'line': 7},
    ]);
    expect(fake.sidecar['mentions'], [
      {'line': 7},
    ]);
    expect(fake.sidecar['content_sha'], enrichContentSha(fake.source));
    expect(fake.calls, [
      'feedback:1',
      'source',
      'mentions',
      'mutate',
      'readSidecar',
      'writeSidecar',
    ]);
  });
  test('accept all processes bottom-up and links before each loan', () async {
    final fake = Fake(
      '- Levou Microscope\n- Взял Microscope\n- Borrowed Microscope\n',
    );
    final texts = [
      'Levou Microscope',
      'Взял Microscope',
      'Borrowed Microscope',
    ];
    final decisions = [
      for (var i = 0; i < 3; i++)
        EnrichDecision(
          EnrichMention(surface: 'Microscope', type: 'equipment', line: i + 1),
          EnrichStatus.linked,
          [const EnrichCandidate(equipment, 1, strong: true)],
        ),
    ];
    final cards = enrichLineCards(
      decisions: decisions,
      loans: [for (var i = 0; i < 3; i++) offer(i + 1, texts[i])],
      lines: fake.source.split('\n'),
    );
    for (final card in acceptAllOrder(cards)) {
      await acceptCard(
        card,
        card.rows,
        acceptLink: (mention, target) async {
          fake.calls.add('link:${card.line}');
          final lines = fake.source.split('\n');
          lines[card.line - 1] = lines[card.line - 1].replaceFirst(
            mention.surface,
            '#tylog.ref-note("${target.id}")[${mention.surface}]',
          );
          fake.source = lines.join('\n');
        },
        acceptLoan: (loan) async {
          await fake.accept(loan);
        },
      );
    }
    expect(
      fake.calls.where(
        (s) => s.startsWith('link:') || s.startsWith('feedback:'),
      ),
      ['link:3', 'feedback:3', 'link:2', 'feedback:2', 'link:1', 'feedback:1'],
    );
    expect(locateTypstCalls(fake.source, names: {'tylog.task'}), hasLength(3));
    final dir = await Directory.systemTemp.createTemp('loan_accept_');
    try {
      final daily = await Directory('${dir.path}/daily').create();
      await File('${daily.path}/day.typ').writeAsString(
        '#show: tylog.note.with(id: "day", title: "Day", kind: "daily")\n\n${fake.source}',
      );
      final index = await scanVaultStorage(LocalVaultStorage(dir));
      expect(index.tasks, hasLength(3));
    } finally {
      await dir.delete(recursive: true);
    }
  });
  test(
    'conflict cancellation has no side effects; confirmation proceeds',
    () async {
      final fake = Fake('- Borrowed Microscope\n');
      final loan = offer(1, 'Borrowed Microscope');
      expect(
        openLoanFor(loan, {
          'eq': [conflict],
        }),
        same(conflict),
      );
      fake.confirm = false;
      expect(await fake.accept(loan, existing: conflict), isFalse);
      expect(fake.calls, ['confirm']);
      fake.calls.clear();
      fake.confirm = true;
      expect(await fake.accept(loan, existing: conflict), isTrue);
      expect(fake.calls.first, 'confirm');
      expect(fake.calls, containsAll(['feedback:1', 'mutate', 'writeSidecar']));
    },
  );
  test('guard preserves a concurrent edit', () async {
    final fake = Fake('- Borrowed Microscope\n')..changeBeforeMutation = true;
    await fake.accept(offer(1, 'Borrowed Microscope'));
    expect(fake.source, '- Borrowed Microscope\nchanged');
    expect(fake.calls, isNot(contains('writeSidecar')));
  });

  test('stale sidecar hash prevents a sidecar write', () async {
    final fake = Fake('- Borrowed Microscope\n');
    fake.sidecar['content_sha'] = 'old';
    expect(await fake.accept(offer(1, 'Borrowed Microscope')), isTrue);
    expect(fake.calls, isNot(contains('readSidecar')));
    expect(fake.calls, isNot(contains('writeSidecar')));
  });
}
