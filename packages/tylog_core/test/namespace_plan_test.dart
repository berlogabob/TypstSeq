import 'package:test/test.dart';

import 'package:tylog_core/src/namespace_plan.dart';

void main() {
  group('planNamespaces', () {
    test(
      'creates a page change and two missing ancestors for three levels',
      () {
        final NamespacePlan plan = planNamespaces(<NamespacePage>[
          const NamespacePage('page', 'A/B/C', <String>[]),
        ]);

        expect(plan.changes.map((change) => change.fullPath).toList(), <String>[
          'A',
          'A/B',
          'A/B/C',
        ]);
        expect(
          plan.changes.map((change) => change.existingId).toList(),
          <String?>[null, null, 'page'],
        );
        expect(plan.changes[0].newTitle, 'A');
        expect(plan.changes[0].parentPath, isNull);
        expect(plan.changes[1].newTitle, 'B');
        expect(plan.changes[1].parentPath, 'A');
        expect(plan.changes[2].newTitle, 'C');
        expect(plan.changes[2].parentPath, 'A/B');
        expect(plan.skipped, isEmpty);
      },
    );

    test('does not reuse a descendant as its own ancestor', () {
      final plan = planNamespaces([
        const NamespacePage('child', 'A/B', ['A']),
      ]);
      expect(plan.changes.first.existingId, isNull);
      expect(plan.changes.last.existingId, 'child');
    });

    test('reuses an existing ancestor by title', () {
      final NamespacePlan plan = planNamespaces(<NamespacePage>[
        const NamespacePage('ancestor', 'A/B', <String>[]),
        const NamespacePage('child', 'A/B/C', <String>[]),
      ]);

      final NamespaceChange change = plan.changes.singleWhere(
        (item) => item.fullPath.toLowerCase() == 'a/b',
      );
      expect(change.existingId, 'ancestor');
    });

    test('reuses an existing ancestor by alias', () {
      final NamespacePlan plan = planNamespaces(<NamespacePage>[
        const NamespacePage('ancestor', 'B', <String>['A/B']),
        const NamespacePage('child', 'A/B/C', <String>[]),
      ]);

      final NamespaceChange change = plan.changes.singleWhere(
        (item) => item.fullPath.toLowerCase() == 'a/b',
      );
      expect(change.existingId, 'ancestor');
    });

    test(
      'skips URLs, academic years, special prefixes, and empty segments',
      () {
        final List<String> titles = <String>[
          'https://example.com/path',
          '2026/2027',
          'r/foo',
          'A//B',
        ];
        final NamespacePlan plan = planNamespaces(
          titles.indexed
              .map(
                (entry) =>
                    NamespacePage('page-${entry.$1}', entry.$2, <String>[]),
              )
              .toList(),
        );

        expect(plan.changes, isEmpty);
        expect(plan.skipped, titles);
      },
    );

    test('creates a shared ancestor only once', () {
      final NamespacePlan plan = planNamespaces(<NamespacePage>[
        const NamespacePage('one', 'A/B/One', <String>[]),
        const NamespacePage('two', 'A/B/Two', <String>[]),
      ]);

      expect(
        plan.changes
            .where((change) => change.fullPath.toLowerCase() == 'a/b')
            .length,
        1,
      );
    });

    test('deduplicates paths case-insensitively', () {
      final NamespacePlan plan = planNamespaces(<NamespacePage>[
        const NamespacePage('one', 'A/B/C', <String>[]),
        const NamespacePage('two', 'a/b/c', <String>[]),
      ]);

      expect(
        plan.changes
            .where((change) => change.fullPath.toLowerCase() == 'a/b/c')
            .length,
        1,
      );
    });

    test('preserves Cyrillic titles and sorts the paths', () {
      final NamespacePlan plan = planNamespaces(<NamespacePage>[
        const NamespacePage('page', 'poplar bear/Проект/Мебель', <String>[]),
      ]);

      expect(plan.changes.map((change) => change.fullPath).toList(), <String>[
        'poplar bear',
        'poplar bear/Проект',
        'poplar bear/Проект/Мебель',
      ]);
      expect(plan.changes.last.newTitle, 'Мебель');
      expect(plan.changes.last.parentPath, 'poplar bear/Проект');
    });
  });
}
