import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/scanner.dart';
import 'package:tylog/github/github_client.dart';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:tylog_core/tylog_core.dart' show Mount, MountSource;
import 'package:tylog/task_scheduler.dart';
import 'package:tylog/vault_registry.dart';
import 'package:tylog/vault_storage.dart';
import 'package:tylog/widgets/settings/extensions_page.dart';
import 'package:tylog/workspace_controller.dart';

class _Inspector implements TypstInspector {
  @override
  Future<List<TypstMetadataRecord>> inspect(TypstDocumentInput input) async {
    final note = scanNote(input.path, input.source);
    return [
      TypstMetadataRecord(
        label: '<tylog-note>',
        value: {
          'schema': 1,
          'entity': 'note',
          'id': note.id,
          'title': note.title,
          'kind': note.kind,
          'date': note.date,
          'tags': note.tags,
          'aliases': note.aliases,
          'properties': note.properties,
        },
      ),
    ];
  }
}

class _GitHub extends GitHubClient {
  _GitHub({this.pushAllowed = false});
  final bool pushAllowed;
  int pushes = 0;
  @override
  Future<Map<String, dynamic>> repoPermissions(String repo) async => {
    'push': pushAllowed,
  };
  @override
  Future<String> putContent(
    String repo,
    String path,
    List<int> bytes,
    String message, {
    String? sha,
    required String branch,
  }) async {
    pushes++;
    return 'newsha';
  }

  @override
  Future<String> defaultBranch(String repo) async => 'main';
  @override
  Future<String> commitSha(String repo, String ref) async => '123456789';
  @override
  Future<Uint8List> downloadZipball(String repo, String ref) async =>
      Uint8List.fromList(
        ZipEncoder().encode(
          Archive()
            ..addFile(ArchiveFile.string('root/typst/lesson.typ', '= Lesson')),
        ),
      );
}

void main() {
  FlutterSecureStorage.setMockInitialValues({'github_token': 'test-token'});

  testWidgets('saving twice debounces a single outbox push', (tester) async {
    late Directory root;
    late WorkspaceController workspace;
    final client = _GitHub(pushAllowed: true);
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('github-debounce');
      final vault = Directory('${root.path}/vault');
      final cache = Directory(
        '${root.path}/cache/a94a8fe5ccb1/repo-177930ea21',
      );
      await cache.create(recursive: true);
      await File('${cache.path}/note.typ').writeAsString('= Note');
      await File(
        '${cache.path}/.tylog-mount.json',
      ).writeAsString('{"blobs":{"note.typ":"old"}}');
      workspace = WorkspaceController(
        taskScheduler: TaskScheduler(),
        inspector: _Inspector(),
        reconcileTasks: (_) async {},
        githubClientFactory: (_) => client,
        mountCacheDirectory: Directory('${root.path}/cache'),
      );
      await workspace.openVault(
        VaultEntry(id: 'test', name: 'Test', path: vault.path),
        storage: LocalVaultStorage(vault),
      );
      await workspace.addMount(
        Mount(
          id: 'repo',
          name: 'Repo',
          source: MountSource(kind: 'github', repo: 'owner/repo', ref: 'main'),
          push: true,
        ),
      );
      await workspace.mutateNote('ext/repo/note.typ', (text) => '$text first');
      await Future<void>.delayed(const Duration(seconds: 1));
      await workspace.mutateNote('ext/repo/note.typ', (text) => '$text second');
      await Future<void>.delayed(const Duration(milliseconds: 29200));
      expect(client.pushes, 0);
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while ((await (await workspace.githubOutbox).entriesFor(
        'repo',
      )).isNotEmpty) {
        if (DateTime.now().isAfter(deadline)) {
          throw TimeoutException('debounced push did not run');
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(client.pushes, 1);
      workspace.dispose();
      await root.delete(recursive: true);
    });
  }, timeout: const Timeout(Duration(seconds: 50)));

  testWidgets('GitHub editing permission, persisted toggle and Push now', (
    tester,
  ) async {
    late Directory root;
    late WorkspaceController workspace;
    final client = _GitHub(pushAllowed: true);
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('github-push-page');
      final vault = Directory('${root.path}/vault');
      final cache = Directory(
        '${root.path}/cache/a94a8fe5ccb1/repo-177930ea21',
      );
      await cache.create(recursive: true);
      await File('${cache.path}/note.typ').writeAsString('= Note');
      await File(
        '${cache.path}/.tylog-mount.json',
      ).writeAsString('{"blobs":{"note.typ":"old"}}');
      workspace = WorkspaceController(
        taskScheduler: TaskScheduler(),
        inspector: _Inspector(),
        reconcileTasks: (_) async {},
        githubClientFactory: (_) => client,
        mountCacheDirectory: Directory('${root.path}/cache'),
      );
      await workspace.openVault(
        VaultEntry(id: 'test', name: 'Test', path: vault.path),
        storage: LocalVaultStorage(vault),
      );
      await workspace.addMount(
        Mount(
          id: 'repo',
          name: 'Repo',
          source: MountSource(kind: 'github', repo: 'owner/repo', ref: 'main'),
          push: false,
        ),
      );
    });
    await tester.pumpWidget(
      MaterialApp(home: ExtensionsPage(workspace: workspace)),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
      isNotNull,
    );
    await tester.runAsync(() async {
      await tester.tap(find.byType(SwitchListTile));
      while (!workspace.mounts.single.push) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      final json =
          jsonDecode(
                await File(
                  '${root.path}/vault/_system/settings/mounts.json',
                ).readAsString(),
              )
              as List;
      expect(json.single['push'], true);
      await (await workspace.githubOutbox).enqueue(
        mountId: 'repo',
        path: 'note.typ',
        baseSha: 'old',
        message: 'edit',
        device: 'test',
      );
    });
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.text('Push now'));
      while (client.pushes == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      while ((await (await workspace.githubOutbox).entriesFor(
        'repo',
      )).isNotEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();
    expect(client.pushes, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      workspace.dispose();
      await root.delete(recursive: true);
    });
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('GitHub editing switch is disabled without permission', (
    tester,
  ) async {
    late Directory root;
    late WorkspaceController workspace;
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('github-permission');
      final vault = Directory('${root.path}/vault');
      workspace = WorkspaceController(
        taskScheduler: TaskScheduler(),
        inspector: _Inspector(),
        reconcileTasks: (_) async {},
        githubClientFactory: (_) => _GitHub(),
        mountCacheDirectory: Directory('${root.path}/cache'),
      );
      await workspace.openVault(
        VaultEntry(id: 'test', name: 'Test', path: vault.path),
        storage: LocalVaultStorage(vault),
      );
      await workspace.addMount(
        Mount(
          id: 'repo',
          name: 'Repo',
          source: MountSource(kind: 'github', repo: 'owner/repo', ref: 'main'),
          push: false,
        ),
      );
    });
    await tester.pumpWidget(
      MaterialApp(home: ExtensionsPage(workspace: workspace)),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
      isNull,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      workspace.dispose();
      await root.delete(recursive: true);
    });
  }, timeout: const Timeout(Duration(seconds: 30)));
  testWidgets('adds and removes a folder, showing its indexed notes', (
    tester,
  ) async {
    late Directory root;
    late Directory external;
    late File settings;
    late WorkspaceController workspace;
    final pickerCalled = Completer<void>();
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('extensions-page');
      external = await Directory('${root.path}/Reference').create();
      await File('${external.path}/one.typ').writeAsString('= One');
      final vault = Directory('${root.path}/vault');
      settings = File('${vault.path}/_system/settings/mounts.json');
      workspace = WorkspaceController(
        taskScheduler: TaskScheduler(),
        inspector: _Inspector(),
        reconcileTasks: (_) async {},
      );
      await workspace.openVault(
        VaultEntry(id: 'test', name: 'Test', path: vault.path),
        storage: LocalVaultStorage(vault),
      );
      await workspace.refreshIndex(always: true);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: ExtensionsPage(
          workspace: workspace,
          pickDirectory: () async {
            if (!pickerCalled.isCompleted) pickerCalled.complete();
            return external.path;
          },
        ),
      ),
    );
    await tester.runAsync(() async {
      await tester.tap(find.text('Add folder'));
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (workspace.index?.notesByPath['ext/reference/one.typ'] == null) {
        if (DateTime.now().isAfter(deadline)) {
          throw TimeoutException('mounted note was not indexed');
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pump();
    expect(pickerCalled.isCompleted, isTrue);
    expect(workspace.mounts, isNotEmpty);
    expect(find.text('Reference'), findsOneWidget);
    expect(find.textContaining('1 notes'), findsOneWidget);
    expect(
      (jsonDecode(await tester.runAsync(settings.readAsString) as String)
              as List)
          .single['id'],
      'reference',
    );
    await tester.runAsync(() => tester.tap(find.byTooltip('Remove Reference')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(() async {
      await tester.tap(find.text('Remove'));
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (workspace.mounts.isNotEmpty ||
          workspace.index!.notesByPath.containsKey('ext/reference/one.typ')) {
        if (DateTime.now().isAfter(deadline)) {
          throw TimeoutException('mounted note was not removed');
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pump();
    expect(workspace.mounts, isEmpty);
    await tester.pump();
    expect(
      jsonDecode(await tester.runAsync(settings.readAsString) as String),
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      workspace.dispose();
      await root.delete(recursive: true);
    });
  }, timeout: const Timeout(Duration(seconds: 30)));
  testWidgets('adds a GitHub repository to mounts settings', (tester) async {
    late Directory root;
    late WorkspaceController workspace;
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('github-page');
      final vault = Directory('${root.path}/vault');
      workspace = WorkspaceController(
        taskScheduler: TaskScheduler(),
        inspector: _Inspector(),
        reconcileTasks: (_) async {},
        githubClientFactory: (_) => _GitHub(),
        mountCacheDirectory: Directory('${root.path}/cache'),
      );
      await workspace.openVault(
        VaultEntry(id: 'test', name: 'Test', path: vault.path),
        storage: LocalVaultStorage(vault),
      );
    });
    await tester.pumpWidget(
      MaterialApp(home: ExtensionsPage(workspace: workspace)),
    );
    await tester.runAsync(() => tester.tap(find.text('Add GitHub repo')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextField).at(0), 'owner/repo');
    await tester.enterText(find.byType(TextField).at(2), 'typst');
    await tester.runAsync(() async {
      await tester.tap(find.text('Add'));
      final file = File('${root.path}/vault/_system/settings/mounts.json');
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (!await file.exists() ||
          workspace.index?.notesByPath['ext/owner-repo/lesson.typ'] == null) {
        if (DateTime.now().isAfter(deadline)) {
          throw TimeoutException('GitHub mount not indexed');
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      final source =
          (jsonDecode(await file.readAsString()) as List).single['source'];
      expect(source['repo'], 'owner/repo');
      expect(source['ref'], 'main');
      expect(source['subdir'], 'typst');
    });
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      workspace.dispose();
      await root.delete(recursive: true);
    });
  }, timeout: const Timeout(Duration(seconds: 30)));
}
