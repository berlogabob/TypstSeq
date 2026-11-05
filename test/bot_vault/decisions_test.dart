import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/bot_vault/decisions.dart';

void main() {
  late Directory root;
  const item = 'item-123';
  setUp(() async {
    root = await Directory.systemTemp.createTemp('bot-decisions');
    await File('${root.path}/bot-vault.json').writeAsString('{"schema":1}');
    await Directory('${root.path}/items').create();
    await File('${root.path}/items/$item.typ').writeAsString('draft');
  });
  tearDown(() => root.delete(recursive: true));

  test(
    'writes one complete, retry-safe advisory decision per action',
    () async {
      final decisions = BotVaultDecisions(root);
      await decisions.record(item, 'accepted');
      await decisions.record(item, 'accepted');
      await decisions.record(item, 'dismissed');
      final lines = await File(
        '${root.path}/outbox/decisions.jsonl',
      ).readAsLines();
      expect(lines, hasLength(2));
      final row = jsonDecode(lines.first) as Map<String, dynamic>;
      expect(row['schema'], 1);
      expect(row['item_id'], item);
      expect(row['action'], 'accepted');
      expect(row['id'], isNotEmpty);
      expect(DateTime.parse(row['at'] as String).isUtc, isTrue);
    },
  );

  test('ignores an incomplete existing decision when retrying', () async {
    final dir = await Directory('${root.path}/outbox').create();
    final file = File('${dir.path}/decisions.jsonl');
    await file.writeAsString(
      '${jsonEncode({'schema': 1, 'id': 'old', 'item_id': item, 'action': 'accepted'})}\n',
    );
    await BotVaultDecisions(root).record(item, 'accepted');
    expect(await file.readAsLines(), hasLength(2));
  });

  test(
    'refuses incompatible vaults, missing items and partial outbox rows',
    () async {
      final decisions = BotVaultDecisions(root);
      await expectLater(
        decisions.record('../other', 'accepted'),
        throwsFormatException,
      );
      await expectLater(
        decisions.record('item-missing', 'accepted'),
        throwsA(isA<FileSystemException>()),
      );
      final outbox = await Directory('${root.path}/outbox').create();
      final file = File('${outbox.path}/decisions.jsonl');
      await file.writeAsString('{"partial":');
      await expectLater(
        decisions.record(item, 'accepted'),
        throwsFormatException,
      );
      expect(await file.readAsString(), '{"partial":');
      await File('${root.path}/bot-vault.json').writeAsString('{"schema":2}');
      await expectLater(
        decisions.record(item, 'accepted'),
        throwsFormatException,
      );
      expect(await file.readAsString(), '{"partial":');
    },
  );
}
