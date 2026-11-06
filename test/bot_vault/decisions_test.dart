import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

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

  test('writes accepted and rejected contract-v1 events', () async {
    await File('${root.path}/items/item-456.typ').writeAsString('draft');
    final decisions = BotVaultDecisions(root);
    await decisions.record(item, 'accepted');
    await decisions.record('item-456', 'rejected');
    final rows = (await File(
      '${root.path}/outbox/decisions.jsonl',
    ).readAsLines()).map((line) => jsonDecode(line) as Map<String, dynamic>);
    expect(rows.map((row) => row['action']), ['accepted', 'rejected']);
    for (final row in rows) {
      expect(row['schema'], 1);
      expect(row['id'], isNotEmpty);
      expect(DateTime.parse(row['at'] as String).isUtc, isTrue);
    }
  });

  test('review hides only complete, valid decision rows', () async {
    final outbox = await Directory('${root.path}/outbox').create();
    final file = File('${outbox.path}/decisions.jsonl');
    final valid = {
      'schema': 1,
      'id': 'id',
      'at': 'now',
      'item_id': item,
      'action': 'accepted',
    };
    await file.writeAsString(
      jsonEncode({...valid, 'item_id': 'item-partial'}),
    );
    final decisions = BotVaultDecisions(root);
    expect(await decisions.decidedItems(), isEmpty);
    await file.writeAsString(
      'bad\n${jsonEncode({...valid, 'action': 'unknown'})}\n${jsonEncode({...valid, 'schema': 1.0, 'item_id': 'item-float'})}\n${jsonEncode(valid)}\n',
      mode: FileMode.write,
    );
    expect(await decisions.decidedItems(), {item});
    await File('${root.path}/bot-vault.json').writeAsString('{"schema":2}');
    await expectLater(decisions.decidedItems(), throwsFormatException);
  });

  test(
    'review and retries ignore duplicate event IDs and non-integer schemas',
    () async {
      final outbox = await Directory('${root.path}/outbox').create();
      final file = File('${outbox.path}/decisions.jsonl');
      await File('${root.path}/items/item-other.typ').writeAsString('draft');
      final row = {
        'schema': 1,
        'id': 'same',
        'at': 'now',
        'item_id': 'item-other',
        'action': 'accepted',
      };
      await file.writeAsString(
        '${jsonEncode(row)}\n${jsonEncode({...row, 'item_id': item})}\n${jsonEncode({...row, 'schema': 1.0, 'id': 'float', 'item_id': item})}\n',
      );
      final decisions = BotVaultDecisions(root);
      expect(await decisions.decidedItems(), {'item-other'});
      await decisions.record(item, 'accepted');
      expect(await file.readAsLines(), hasLength(4));
      expect(await decisions.decidedItems(), {'item-other', item});
    },
  );

  test('concurrent decisions stay complete and retry-safe', () async {
    await Future.wait(
      List.generate(
        24,
        (_) => BotVaultDecisions(root).record(item, 'accepted'),
      ),
    );
    final lines = await File(
      '${root.path}/outbox/decisions.jsonl',
    ).readAsLines();
    expect(lines, hasLength(1));
    expect((jsonDecode(lines.single) as Map)['action'], 'accepted');
  });

  test('concurrent isolates record one decision', () async {
    await Future.wait(
      List.generate(
        24,
        (_) => Isolate.run(() async {
          await BotVaultDecisions(
            Directory(root.path),
          ).record(item, 'accepted');
        }),
      ),
    );
    final lines = await File(
      '${root.path}/outbox/decisions.jsonl',
    ).readAsLines();
    expect(lines, hasLength(1));
    expect((jsonDecode(lines.single) as Map)['action'], 'accepted');
  }, skip: Platform.isWindows);

  test('waits for another process holding the outbox lock', () async {
    if (Platform.isWindows) return;
    final dir = await Directory('${root.path}/outbox').create();
    final path = '${dir.path}/decisions.jsonl';
    await File(path).writeAsString('');
    final holder = await Process.start('python3', [
      '-u',
      '-c',
      'import fcntl, sys\nf = open(sys.argv[1], "a+")\nfcntl.lockf(f, fcntl.LOCK_EX)\nprint("locked", flush=True)\nsys.stdin.readline()',
      path,
    ]);
    final ready = holder.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    expect(await ready.first, 'locked');
    try {
      final recording = BotVaultDecisions(root).record(item, 'accepted');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(await File(path).readAsString(), isEmpty);
      holder.stdin.writeln('release');
      await recording;
      expect(await File(path).readAsLines(), hasLength(1));
    } finally {
      holder.stdin.writeln('release');
      await holder.stdin.close();
      await holder.exitCode;
    }
  });

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
