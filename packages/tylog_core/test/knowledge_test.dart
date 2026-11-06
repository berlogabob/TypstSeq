import 'package:test/test.dart';
import 'package:tylog_core/tylog_core.dart';

void main() {
  group('parseKnowledgeStatus', () {
    test('every status round-trips via parseKnowledgeStatus(s.name)', () {
      for (final status in KnowledgeStatus.values) {
        expect(parseKnowledgeStatus(status.name), status);
      }
    });

    test('unknown name returns null', () {
      expect(parseKnowledgeStatus('x'), isNull);
    });

    test('null name returns null', () {
      expect(parseKnowledgeStatus(null), isNull);
    });
  });

  group('isKnown', () {
    test('true only for accepted and auto', () {
      expect(isKnown(KnowledgeStatus.accepted), isTrue);
      expect(isKnown(KnowledgeStatus.auto), isTrue);
    });

    test('false for all other statuses', () {
      for (final status in KnowledgeStatus.values) {
        if (status == KnowledgeStatus.accepted ||
            status == KnowledgeStatus.auto) {
          continue;
        }
        expect(isKnown(status), isFalse, reason: '$status should not be known');
      }
    });
  });
}
