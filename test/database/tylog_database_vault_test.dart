import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/database/tylog_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('tylog_vault_db_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          pathProvider,
          (call) async => call.method == 'getApplicationSupportDirectory'
              ? directory.path
              : null,
        );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('claimVault persists one owner and rejects another', () async {
    final database = TyLogDatabase(NativeDatabase.memory());
    addTearDown(database.close);

    expect(await database.claimVault('vault-a'), isTrue);
    expect(await database.claimVault('vault-a'), isTrue);
    expect(await database.claimVault('vault-b'), isFalse);
    expect(
      (await database.select(database.databaseMetadata).getSingle()).value,
      'vault-a',
    );
  });

  test(
    'vault opener keeps the first vault in legacy DB and isolates others',
    () async {
      final first = await openDatabaseForVault('vault-a');
      await first.commitNodeEdit(
        node: _node('same-node', 'first'),
        revision: _revision('first-revision', 'first'),
      );
      await first.close();

      final second = await openDatabaseForVault('vault-b');
      expect(await second.select(second.nodes).get(), isEmpty);
      await second.commitNodeEdit(
        node: _node('same-node', 'second'),
        revision: _revision('second-revision', 'second'),
      );
      expect((await second.select(second.nodes).getSingle()).title, 'second');
      await second.close();

      expect(await File('${directory.path}/tylog.db').exists(), isTrue);
      final files = await directory
          .list()
          .where((entity) => entity is File)
          .cast<File>()
          .map((file) => file.uri.pathSegments.last)
          .where((name) => name.startsWith('tylog-') && name.endsWith('.db'))
          .toList();
      expect(files, hasLength(1));
    },
  );

  test('empty vault ids are rejected before opening a database', () async {
    await expectLater(openDatabaseForVault(''), throwsArgumentError);
  });
}

NodeData _node(String id, String content) => NodeData(
  id: id,
  type: 'note',
  title: content,
  content: content,
  attributesJson: '{}',
  eventStartMs: null,
  eventEndMs: null,
  createdAtMs: 1,
  updatedAtMs: 1,
);

RevisionData _revision(String id, String content) => RevisionData(
  id: id,
  entityKind: 'node',
  entityId: 'same-node',
  parentRevisionId: null,
  payloadJson: '{"content":"$content"}',
  createdAtMs: 1,
);
