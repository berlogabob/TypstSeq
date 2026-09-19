import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/database/portable_merge.dart';

void main() {
  test('classifies an incoming row with no local key as insert', () {
    final plan = planPortableMerge(
      localRows: const [],
      incomingRows: const [
        PortableRow(
          table: 'nodes',
          id: 'n1',
          value: {'title': 'New', 'attributes': <String, Object?>{}},
        ),
      ],
    );

    expect(plan.rows.single.kind, PortableMergeKind.insert);
    expect(plan.rows.single.localHash, isNull);
    expect(plan.rows.single.conflictId, isNull);
  });

  test('canonical key ordering makes an exact row re-import unchanged', () {
    final plan = planPortableMerge(
      localRows: const [
        PortableRow(
          table: 'nodes',
          id: 'n1',
          value: {
            'title': 'Same',
            'attributes': {'z': 2, 'a': 1},
          },
        ),
      ],
      incomingRows: const [
        PortableRow(
          table: 'nodes',
          id: 'n1',
          value: {
            'attributes': {'a': 1, 'z': 2},
            'title': 'Same',
          },
        ),
      ],
    );

    expect(plan.rows.single.kind, PortableMergeKind.unchanged);
    expect(plan.rows.single.localHash, plan.rows.single.incomingHash);
  });

  test('node, edge, and revision payload changes are conflicts', () {
    const localRows = [
      PortableRow(
        table: 'nodes',
        id: 'n1',
        value: {
          'title': 'old',
          'attributes': {'kind': 'note'},
        },
      ),
      PortableRow(
        table: 'edges',
        id: 'e1',
        value: {'from': 'n1', 'to': 'n2', 'type': 'supports'},
      ),
      PortableRow(
        table: 'revisions',
        id: 'r1',
        value: {
          'entityId': 'n1',
          'payload': {'content': 'old'},
        },
      ),
    ];
    final incomingRows = [
      PortableRow(
        table: 'nodes',
        id: 'n1',
        value: {
          'title': 'old',
          'attributes': {'kind': 'claim'},
        },
      ),
      const PortableRow(
        table: 'edges',
        id: 'e1',
        value: {'from': 'n1', 'to': 'n2', 'type': 'refutes'},
      ),
      const PortableRow(
        table: 'revisions',
        id: 'r1',
        value: {
          'entityId': 'n1',
          'payload': {'content': 'new'},
        },
      ),
    ];

    final plan = planPortableMerge(
      localRows: localRows,
      incomingRows: incomingRows,
    );

    expect(plan.rows.map((decision) => decision.kind), [
      PortableMergeKind.conflict,
      PortableMergeKind.conflict,
      PortableMergeKind.conflict,
    ]);
    expect(plan.rows.every((decision) => decision.conflictId != null), isTrue);

    final repeated = planPortableMerge(
      localRows: localRows,
      incomingRows: incomingRows,
    );
    expect(
      repeated.rows.map((decision) => decision.conflictId),
      plan.rows.map((decision) => decision.conflictId),
    );
  });

  test('same attachment hash with different bytes is a conflict', () {
    final plan = planPortableMerge(
      localRows: const [],
      incomingRows: const [],
      localAttachments: [
        PortableAttachment(
          path: 'assets/a.bin',
          sha256: 'claimed-hash',
          bytes: [1, 2],
        ),
      ],
      incomingAttachments: [
        PortableAttachment(
          path: 'assets/a.bin',
          sha256: 'claimed-hash',
          bytes: [1, 3],
        ),
      ],
    );

    final decision = plan.attachments.single;
    expect(decision.kind, PortableMergeKind.conflict);
    expect(
      decision.conflictId,
      portableConflictId(
        table: 'attachment',
        id: 'assets/a.bin',
        localHash: 'claimed-hash',
        incomingHash: 'claimed-hash',
      ),
    );
  });

  test('same attachment hash and bytes is unchanged', () {
    final plan = planPortableMerge(
      localRows: const [],
      incomingRows: const [],
      localAttachments: [
        PortableAttachment(path: 'assets/a.bin', bytes: [1, 2]),
      ],
      incomingAttachments: [
        PortableAttachment(path: 'assets/a.bin', bytes: [1, 2]),
      ],
    );

    expect(plan.attachments.single.kind, PortableMergeKind.unchanged);
  });
}
