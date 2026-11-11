import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/database/tylog_database.dart';
import 'package:tylog/scanner.dart';
import 'package:tylog/task_scheduler.dart';
import 'package:tylog/vault_registry.dart';
import 'package:tylog/vault_storage.dart';
import 'package:tylog/workspace_controller.dart';
import 'support/temp_dir.dart';

class _Inspector implements TypstInspector {
  @override
  Future<List<TypstMetadataRecord>> inspect(TypstDocumentInput input) async =>
      const [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('renameCluster persists in the format the reload reads', () async {
    final root = await Directory.systemTemp.createTemp('tylog-cluster-names-');
    addTearDown(() => deleteTempDir(root));
    final storage = LocalVaultStorage(root);
    final database = TyLogDatabase(NativeDatabase.memory());
    final controller = WorkspaceController(
      taskScheduler: TaskScheduler(),
      inspector: _Inspector(),
      reconcileTasks: (_) async {},
      database: Future.value(database),
    );
    addTearDown(database.close);
    addTearDown(controller.dispose);
    await controller.openVault(
      VaultEntry(id: 'cluster-names', name: 'Names', path: root.path),
      storage: storage,
    );

    await controller.renameCluster('tech-software', '  Tech & AI ');
    expect(controller.clusterNames, {'tech-software': 'Tech & AI'});
    final onDisk = jsonDecode(
      await storage.readText('_system/clusters/names.json'),
    );
    expect(onDisk, {
      'schema': 1,
      'names': {'tech-software': 'Tech & AI'},
    });

    // Survives a reload (what a restart does).
    await controller.reloadClusterSnapshot();
    expect(controller.clusterNames, {'tech-software': 'Tech & AI'});

    await controller.renameCluster('tech-software', ' ');
    await controller.reloadClusterSnapshot();
    expect(controller.clusterNames, isEmpty);
  });
}
