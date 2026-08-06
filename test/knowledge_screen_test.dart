import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/knowledge_screen.dart';
import 'package:tylog_core/models.dart';

PkmsProblem _broken(String subject, String target) => PkmsProblem(
  code: 'broken-link',
  severity: PkmsSeverity.warning,
  subject: subject,
  message: 'unresolved link: $target',
);

void main() {
  // Shapes taken from the real migrated vault: 2687 broken links over 1350
  // targets, of which 98 still carry escaped brackets and ~150 are really an
  // existing tag under a different casing.
  group('unresolvedLinkTargets', () {
    test('groups by target, most referenced first', () {
      final targets = unresolvedLinkTargets([
        _broken('daily/2022/04/2022-04-01.typ', 'Илья Бирман'),
        _broken('daily/2022/04/2022-04-02.typ', 'Илья Бирман'),
        _broken('notes/trip.typ', 'Дубай'),
      ], const {});

      expect(targets.map((t) => t.target), ['Илья Бирман', 'Дубай']);
      expect(targets.first.count, 2);
      expect(targets.first.referrers, hasLength(2));
    });

    test('a target that is already a tag is folded out, not offered', () {
      // The index stores tags folded, so a raw comparison would miss both of
      // these — `Tutorial` is the single most referenced target in the vault.
      final targets = unresolvedLinkTargets([
        _broken('notes/a.typ', 'Tutorial'),
        _broken('notes/b.typ', 'quick capture'),
        _broken('notes/c.typ', 'Дубай'),
      ], const {'tutorial', 'quick-capture'});

      expect(targets.map((t) => t.target), ['Дубай']);
    });

    test('escaped-bracket import artefacts are dropped', () {
      final targets = unresolvedLinkTargets([
        _broken('articles/x.typ', r'\[\[80.lv\]\]'),
        _broken('notes/c.typ', 'Дубай'),
      ], const {});

      expect(targets.map((t) => t.target), ['Дубай']);
    });

    test('other problem codes are ignored', () {
      final targets = unresolvedLinkTargets([
        const PkmsProblem(
          code: 'ambiguous-link',
          severity: PkmsSeverity.warning,
          subject: 'notes/a.typ',
          message: 'ambiguous link: Дубай',
        ),
      ], const {});

      expect(targets, isEmpty);
    });
  });

  test('person-shaped targets default to the person kind', () {
    expect(defaultKindForTarget('Илья Бирман'), 'person');
    expect(defaultKindForTarget('Grant Abbitt'), 'person');
    // One word, or a lowercase second word, is not a name.
    expect(defaultKindForTarget('Дубай'), 'note');
    expect(defaultKindForTarget('quick capture'), 'note');
  });
}
