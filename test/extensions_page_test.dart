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
import 'package:tylog_core/tylog_core.dart'
    show Mount, MountSource, InstalledModule;
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
  int releaseChecks = 0;
  bool offline = false;
  @override
  Future<({String tag, List<({String name, String url})> assets})>
  latestRelease(String repo) async {
    releaseChecks++;
    if (offline) throw const SocketException('offline');
    return (tag: '1.0.0', assets: <({String name, String url})>[]);
  }

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

  testWidgets('shows a persisted pack update and opens its installer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late Directory root;
    late WorkspaceController workspace;
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('pack-extension');
      final storage = LocalVaultStorage(Directory('${root.path}/vault'));
      workspace = WorkspaceController(
        taskScheduler: TaskScheduler(),
        inspector: _Inspector(),
        reconcileTasks: (_) async {},
      );
      await workspace.openVault(
        VaultEntry(id: 'test', name: 'Test', path: '${root.path}/vault'),
        storage: storage,
      );
      expect(workspace.vault, isNotNull, reason: workspace.status);
      await storage.writeText(
        '_system/modules/course.json',
        jsonEncode({
          'name': 'A long research methods course pack',
          'version': '1.0.0',
          'source': {'github': 'owner/repo'},
          'updateAvailableVersion': '2.0.0',
          'updateCheckedAt': DateTime.now().toIso8601String(),
        }),
      );
    });
    InstalledModule? selected;
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: ExtensionsPage(
            workspace: workspace,
            onUpdateModule: (module) async {
              selected = module;
            },
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.text('A long research methods course pack')).width,
      greaterThan(200),
    );
    expect(find.text('Update to 2.0.0'), findsOneWidget);
    await tester.tap(find.text('Update to 2.0.0'));
    expect(selected?.id, 'course');
    await tester.pumpWidget(const SizedBox());
    workspace.dispose();
    await tester.runAsync(() => root.delete(recursive: true));
  });

  testWidgets('shows GitHub mount source details on a phone', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late Directory root;
    late WorkspaceController workspace;
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('github-mount-details');
      workspace = WorkspaceController(
        taskScheduler: TaskScheduler(),
        inspector: _Inspector(),
        reconcileTasks: (_) async {},
        githubClientFactory: (_) => _GitHub(),
        mountCacheDirectory: Directory('${root.path}/cache'),
      );
      await workspace.openVault(
        VaultEntry(id: 'test', name: 'Test', path: '${root.path}/vault'),
        storage: LocalVaultStorage(Directory('${root.path}/vault')),
      );
      await workspace.addMount(
        Mount(
          id: 'repo',
          name: 'Research materials',
          source: MountSource(
            kind: 'github',
            repo: 'owner/research-materials',
            ref: 'release/2026',
            subdir: 'course/notes',
          ),
          push: false,
        ),
      );
    });
    await tester.pumpWidget(
      MaterialApp(home: ExtensionsPage(workspace: workspace)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('owner/research-materials'), findsOneWidget);
    expect(find.textContaining('release/2026'), findsOneWidget);
    expect(find.textContaining('course/notes'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      workspace.dispose();
      await root.delete(recursive: true);
    });
  });

  testWidgets('checks each GitHub pack at most weekly even offline', (
    tester,
  ) async {
    late Directory root;
    late WorkspaceController workspace;
    final client = _GitHub()..offline = true;
    var now = DateTime(2026, 11, 4);
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('pack-weekly');
      final storage = LocalVaultStorage(Directory('${root.path}/vault'));
      workspace = WorkspaceController(
        taskScheduler: TaskScheduler(),
        inspector: _Inspector(),
        reconcileTasks: (_) async {},
        githubClientFactory: (_) => client,
        now: () => now,
      );
      await workspace.openVault(
        VaultEntry(id: 'test', name: 'Test', path: '${root.path}/vault'),
        storage: storage,
      );
      expect(workspace.vault, isNotNull, reason: workspace.status);
      await storage.writeText(
        '_system/modules/course.json',
        jsonEncode({
          'version': '1.0.0',
          'source': {'github': 'owner/repo'},
          'updateAvailableVersion': '2.0.0',
        }),
      );
      await workspace.checkModuleUpdates();
      await workspace.checkModuleUpdates();
      expect(client.releaseChecks, 1);
      expect(
        (jsonDecode(await storage.readText('_system/modules/course.json'))
            as Map)['updateAvailableVersion'],
        '2.0.0',
      );
      now = now.add(const Duration(days: 7));
      client.offline = false;
      await workspace.checkModuleUpdates();
      expect(client.releaseChecks, 2);
      expect(
        (jsonDecode(await storage.readText('_system/modules/course.json'))
            as Map)['updateAvailableVersion'],
        isNull,
      );
      workspace.dispose();
      await root.delete(recursive: true);
    });
  });

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
  testWidgets('mounts and reads a versioned bot vault without changing it', (
    tester,
  ) async {
    late Directory root;
    late Directory bot;
    late WorkspaceController workspace;
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('bot-vault');
      bot = await Directory('${root.path}/Bot').create();
      await File('${bot.path}/bot-vault.json').writeAsString('{"schema":1}');
      await File(
        '${bot.path}/item.typ',
      ).writeAsString('= Bot item\nOriginal text');
      final vault = Directory('${root.path}/vault');
      workspace = WorkspaceController(
        taskScheduler: TaskScheduler(),
        inspector: _Inspector(),
        reconcileTasks: (_) async {},
      );
      await workspace.openVault(
        VaultEntry(id: 'test', name: 'Test', path: vault.path),
        storage: LocalVaultStorage(vault),
      );
    });
    await tester.pumpWidget(
      MaterialApp(
        home: ExtensionsPage(
          workspace: workspace,
          pickDirectory: () async => bot.path,
        ),
      ),
    );
    await tester.runAsync(() async {
      await tester.tap(find.text('Add bot vault'));
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (workspace.index?.notesByPath['ext/bot/item.typ'] == null) {
        if (DateTime.now().isAfter(deadline)) {
          throw TimeoutException('bot item not indexed');
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    expect(workspace.mounts.single.push, isFalse);
    await tester.runAsync(() async {
      await tester.tap(find.text('Bot'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.text('item'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.text('item'));
      await tester.pump();
      await Future<void>.delayed(const Duration(seconds: 2));
    });
    await tester.pumpAndSettle();
    expect(
      tester.widget<SelectableText>(find.byType(SelectableText)).data,
      contains('Original text'),
    );
    expect(
      await tester.runAsync(() => File('${bot.path}/item.typ').readAsString()),
      '= Bot item\nOriginal text',
    );
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      workspace.dispose();
      await root.delete(recursive: true);
    });
  });

  testWidgets('reviews a bot draft and returns a decision', (tester) async {
    late Directory root;
    late Directory bot;
    late WorkspaceController workspace;
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('review-bot');
      bot = await Directory('${root.path}/Bot').create();
      await File('${bot.path}/bot-vault.json').writeAsString('{"schema":1}');
      await Directory('${bot.path}/items').create();
      await File('${bot.path}/items/item-123.typ').writeAsString('= Draft');
      final vault = Directory('${root.path}/vault');
      workspace = WorkspaceController(
        taskScheduler: TaskScheduler(),
        inspector: _Inspector(),
        reconcileTasks: (_) async {},
      );
      await workspace.openVault(
        VaultEntry(id: 'test', name: 'Test', path: vault.path),
        storage: LocalVaultStorage(vault),
      );
    });
    await tester.pumpWidget(
      MaterialApp(
        home: ExtensionsPage(
          workspace: workspace,
          pickDirectory: () async => bot.path,
        ),
      ),
    );
    await tester.runAsync(() async {
      await tester.tap(find.text('Add bot vault'));
      while (workspace.index?.notesByPath['ext/bot/items/item-123.typ'] ==
          null) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.text('Bot'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('item-123'));
      await tester.pump();
      await Future<void>.delayed(const Duration(seconds: 2));
    });
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Accept'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    final lines = await tester.runAsync(
      () => File('${bot.path}/outbox/decisions.jsonl').readAsLines(),
    );
    expect((jsonDecode(lines!.single) as Map)['action'], 'accepted');
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      workspace.dispose();
      await Future<void>.delayed(const Duration(seconds: 1));
      await root.delete(recursive: true);
    });
  });

  testWidgets('refreshes a compatible bot vault and rejects a newer schema', (
    tester,
  ) async {
    late Directory root;
    late Directory bot;
    late WorkspaceController workspace;
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('refresh-bot');
      bot = await Directory('${root.path}/Bot').create();
      await File('${bot.path}/bot-vault.json').writeAsString('{"schema":1}');
      final vault = Directory('${root.path}/vault');
      workspace = WorkspaceController(
        taskScheduler: TaskScheduler(),
        inspector: _Inspector(),
        reconcileTasks: (_) async {},
      );
      await workspace.openVault(
        VaultEntry(id: 'test', name: 'Test', path: vault.path),
        storage: LocalVaultStorage(vault),
      );
    });
    await tester.pumpWidget(
      MaterialApp(
        home: ExtensionsPage(
          workspace: workspace,
          pickDirectory: () async => bot.path,
        ),
      ),
    );
    await tester.runAsync(() async {
      await tester.tap(find.text('Add bot vault'));
      while (workspace.mounts.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await File('${bot.path}/new.typ').writeAsString('= New item');
    });
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Refresh Bot'));
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (workspace.index?.notesByPath['ext/bot/new.typ'] == null) {
        if (DateTime.now().isAfter(deadline))
          throw TimeoutException('new bot item not indexed');
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await File('${bot.path}/bot-vault.json').writeAsString('{"schema":2}');
    });
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Refresh Bot'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    expect(find.textContaining('needs newer TyLog'), findsOneWidget);
    await tester.runAsync(() async {
      await workspace.reloadMounts();
      expect(workspace.status, contains('needs newer TyLog'));
      expect(workspace.index?.notesByPath['ext/bot/new.typ'], isNull);
      await File('${bot.path}/bot-vault.json').writeAsString('{"schema":1}');
      await workspace.reloadMounts();
      expect(workspace.index?.notesByPath['ext/bot/new.typ'], isNotNull);
    });
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      workspace.dispose();
      await root.delete(recursive: true);
    });
  });

  testWidgets('rejects a bot vault requiring a newer TyLog', (tester) async {
    late Directory root;
    late WorkspaceController workspace;
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('new-bot-vault');
      await File('${root.path}/bot-vault.json').writeAsString('{"schema":2}');
      final vault = Directory('${root.path}/vault');
      workspace = WorkspaceController(
        taskScheduler: TaskScheduler(),
        inspector: _Inspector(),
        reconcileTasks: (_) async {},
      );
      await workspace.openVault(
        VaultEntry(id: 'test', name: 'Test', path: vault.path),
        storage: LocalVaultStorage(vault),
      );
    });
    await tester.pumpWidget(
      MaterialApp(
        home: ExtensionsPage(
          workspace: workspace,
          pickDirectory: () async => root.path,
        ),
      ),
    );
    await tester.runAsync(() async {
      await tester.tap(find.text('Add bot vault'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    expect(find.textContaining('needs newer TyLog'), findsOneWidget);
    expect(workspace.mounts, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      workspace.dispose();
      await root.delete(recursive: true);
    });
  });

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
