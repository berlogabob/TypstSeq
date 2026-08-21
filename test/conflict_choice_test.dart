import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/nextcloud_sync.dart';
import 'package:tylog/nextcloud_sync/conflict_choice.dart';

/// The real record that motivated this: on the A24 at 02:47,
/// `daily/2026-08-21.typ` was local 184 bytes against remote 221 — the remote
/// being local plus the appended line "today we will play concert with Flor".
/// The dialog preselected keep-local unconditionally, so accepting the default
/// would have silently deleted that line.
void main() {
  const base = '#import "/_system/tylog.typ" as tylog\n\n= 2026-08-21\n';
  const extended = '$base\ntoday we will play concert with Flor\n';

  group('conflictShape', () {
    test('identical bytes', () {
      expect(
        conflictShape(local: base, remote: base),
        ConflictShape.identical,
      );
    });

    test('an append on either side is a superset, not a disagreement', () {
      expect(
        conflictShape(local: extended, remote: base),
        ConflictShape.localSuperset,
      );
      expect(
        conflictShape(local: base, remote: extended),
        ConflictShape.remoteSuperset,
      );
    });

    test('independent edits diverge', () {
      expect(
        conflictShape(local: '${base}local line\n', remote: '${base}other\n'),
        ConflictShape.diverged,
      );
    });

    test('a missing or binary side cannot be compared', () {
      expect(
        conflictShape(local: base, remote: null),
        ConflictShape.incomparable,
      );
      expect(conflictShape(local: null, remote: null),
          ConflictShape.incomparable);
    });
  });

  group('defaultResolution', () {
    test('offers the superset, never the side that would lose a line', () {
      expect(
        defaultResolution(ConflictShape.remoteSuperset),
        SyncConflictResolution.keepRemote,
      );
      expect(
        defaultResolution(ConflictShape.localSuperset),
        SyncConflictResolution.keepLocal,
      );
    });

    test('the A24 record no longer defaults to destroying the newer side', () {
      final shape = conflictShape(local: base, remote: extended);
      expect(defaultResolution(shape), SyncConflictResolution.keepRemote);
      expect(defaultResolution(shape), isNot(SyncConflictResolution.keepLocal));
    });

    test('forces an explicit choice wherever a default could discard data', () {
      expect(defaultResolution(ConflictShape.diverged), isNull);
      expect(defaultResolution(ConflictShape.incomparable), isNull);
    });

    test('identical content may default — either choice is lossless', () {
      expect(defaultResolution(ConflictShape.identical), isNotNull);
    });
  });

  group('conflictSideLabel', () {
    test('describes each side against the other, not in raw bytes', () {
      expect(
        conflictSideLabel(
          ConflictShape.remoteSuperset,
          isLocal: false,
          text: extended,
          byteLength: 221,
        ),
        contains('plus more'),
      );
      expect(
        conflictSideLabel(
          ConflictShape.remoteSuperset,
          isLocal: true,
          text: base,
          byteLength: 184,
        ),
        contains('Missing what the other side added'),
      );
    });

    test('a deleted side says so', () {
      expect(
        conflictSideLabel(
          ConflictShape.incomparable,
          isLocal: true,
          text: null,
          byteLength: null,
        ),
        'File deleted',
      );
    });
  });

  test('the diverged hint warns that something will be lost', () {
    expect(conflictShapeHint(ConflictShape.diverged), contains('lose changes'));
    expect(conflictShapeHint(ConflictShape.incomparable), isNull);
  });
}
