import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tylog_core/tylog_core.dart';

class _MemoryStorage extends VaultStorage {
  final files = <String, Uint8List>{};

  @override
  Future<bool> exists(String path) async => files.containsKey(path);
  @override
  Future<Uint8List> readBytes(String path) async => files[path]!;
  @override
  Future<void> writeBytes(String path, List<int> bytes) async {
    files[path] = Uint8List.fromList(bytes);
  }

  @override
  Future<List<VaultStorageEntry>> list({
    String path = '',
    bool recursive = false,
  }) async => [
    for (final key in files.keys)
      if (key.startsWith('$path/') &&
          (recursive || !key.substring(path.length + 1).contains('/')))
        VaultStorageEntry(path: key, isDirectory: false),
  ];

  @override
  Future<void> createDirectory(String path) async {}
  @override
  Future<void> delete(String path) async {
    files.remove(path);
  }

  @override
  Future<VaultStorageEntry?> stat(String path) async => null;
  @override
  Future<String> hash(String path) => throw UnimplementedError();
}

NoteRef _note(String kind, [Map<String, Object?> properties = const {}]) =>
    NoteRef(
      id: 'item',
      path: 'item.typ',
      title: 'Item',
      kind: kind,
      outgoingLinks: const [],
      properties: properties,
    );

void main() {
  test('attention maps screenshot statuses', () {
    for (final (status, expected) in <(Object?, String)>[
      (null, 'new'),
      ('inbox', 'new'),
      ('kept', 'kept'),
      ('acted', 'acted'),
      ('archived', 'archived'),
    ]) {
      expect(attentionOf(_note('screenshot', {'status': status})), expected);
    }
  });

  test('attention maps idea statuses', () {
    for (final (status, expected) in <(Object?, String)>[
      (null, 'new'),
      ('new', 'new'),
      ('approved', 'kept'),
      ('archived', 'archived'),
    ]) {
      expect(attentionOf(_note('idea', {'status': status})), expected);
    }
  });

  test('audio attention uses explicit value or defaults to new', () {
    expect(attentionOf(_note('audio')), 'new');
    expect(attentionOf(_note('audio', {'status': 'transcribed'})), 'new');
    expect(attentionOf(_note('audio', {'attention': 'acted'})), 'acted');
  });

  test('explicit valid attention wins and other kinds stay separate', () {
    expect(
      attentionOf(
        _note('screenshot', {'status': 'inbox', 'attention': 'kept'}),
      ),
      'kept',
    );
    expect(attentionOf(_note('screenshot', {'attention': 'unknown'})), 'new');
    for (final kind in ['daily', 'note', 'article', 'task', 'project']) {
      expect(attentionOf(_note(kind, {'status': 'new'})), isNull);
    }
  });

  test('decision log round trips optional fields', () {
    const row = Decision(
      at: '2026-10-29T10:00:00Z',
      device: 'phone',
      item: 'daily/today.typ',
      source: 'enrich',
      action: 'accepted',
      target: 'person/ana.typ',
      context: 'Ana',
    );
    expect(
      Decision.parseLog(encodeDecisions([row])).single.toJson(),
      row.toJson(),
    );
    expect(encodeDecisions([row]), endsWith('\n'));
  });

  test('decision parser skips malformed and unknown action rows', () {
    final valid = const Decision(
      at: '',
      device: '',
      item: 'x',
      source: 'manual',
      action: 'ignored',
    );
    expect(
      Decision.parseLog(
        [
          '{bad json}',
          jsonEncode({...valid.toJson(), 'action': 'invented'}),
          jsonEncode(valid.toJson()),
        ].join('\n'),
      ).map((d) => d.toJson()),
      [valid.toJson()],
    );
  });

  test('loadDecisions merges decision and enrichment ledgers', () async {
    final storage = _MemoryStorage();
    const manual = Decision(
      at: 'now',
      device: 'tablet',
      item: 'idea/one.typ',
      source: 'today',
      action: 'scheduled',
    );
    await storage.writeText(
      '$decisionsDir/device.jsonl',
      encodeDecisions([manual]),
    );
    await storage.writeText(
      '$enrichFeedbackDir/device.jsonl',
      jsonEncode({
        'at': 'then',
        'decision': 'accept',
        'surface': 'Ana',
        'entity': 'ana',
        'note': 'daily/day.typ',
      }),
    );
    await storage.writeText(
      '$enrichShownDir/device.jsonl',
      jsonEncode({
        'at': 'before',
        'decision': 'shown',
        'surface': 'Bob',
        'entity': 'bob',
        'note': 'daily/day.typ',
      }),
    );

    final rows = await loadDecisions(storage);
    expect(rows.map((row) => row.action), ['scheduled', 'accepted', 'seen']);
    expect(rows[1].toJson(), {
      'at': 'then',
      'device': '',
      'item': 'daily/day.typ',
      'source': 'enrich',
      'action': 'accepted',
      'target': 'ana',
      'context': 'Ana',
    });
    expect(rows[2].action, 'seen');
  });
}
