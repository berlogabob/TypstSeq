import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/github/github_auth.dart';
import 'package:tylog/github/github_client.dart';
import 'package:tylog/github/github_outbox.dart';
import 'package:tylog/github/mount_fetcher.dart';
import 'package:tylog_core/tylog_core.dart';

class FakeGitHub extends GitHubClient {
  String sha = 'new';
  Uint8List zip = Uint8List(0);
  int downloads = 0;
  int commits = 0;
  bool fail = false;
  @override
  Future<String> commitSha(String repo, String ref) async {
    commits++;
    if (fail) throw StateError('offline');
    return sha;
  }

  @override
  Future<Uint8List> downloadZipball(String repo, String ref) async {
    downloads++;
    return zip;
  }
}

void main() {
  late Directory dir;
  late FakeGitHub client;
  late MountFetcher fetcher;
  var reloads = 0;
  final mount = Mount(
    id: 'repo',
    name: 'Repo',
    source: MountSource(
      kind: 'github',
      repo: 'a/b',
      ref: 'main',
      subdir: 'typst',
    ),
    push: false,
  );
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mount-fetch');
    client = FakeGitHub();
    reloads = 0;
    fetcher = MountFetcher(
      cache: dir,
      client: client,
      reload: () async {
        reloads++;
      },
    );
    await Directory('${dir.path}/repo').create();
    await File('${dir.path}/repo/old').writeAsString('old');
    await File(
      '${dir.path}/repo/.tylog-mount.json',
    ).writeAsString(jsonEncode({'sha': 'old', 'blobs': {}}));
  });
  tearDown(() async => dir.delete(recursive: true));
  Uint8List zip(String path) => Uint8List.fromList(
    ZipEncoder().encode(Archive()..addFile(ArchiveFile.string(path, 'new'))),
  );
  test('refresh resolves current client for each attempt', () async {
    final second = FakeGitHub()..sha = 'old';
    var current = client;
    fetcher = MountFetcher(
      cache: dir,
      clientProvider: () async => current,
      reload: () async {},
    );
    client.sha = 'old';
    await fetcher.refresh(mount);
    current = second;
    await fetcher.refresh(mount);
    expect(second.commits, 1);
    expect(client.commits, 1);
  });
  test('unchanged sha does not download or reload', () async {
    client.sha = 'old';
    await fetcher.refresh(mount);
    expect(client.downloads, 0);
    expect(reloads, 0);
  });
  test('changed sha replaces cache and strips subdirectory', () async {
    client.zip = zip('root/typst/note.typ');
    await fetcher.refresh(mount);
    expect(await File('${dir.path}/repo/note.typ').readAsString(), 'new');
    expect(await File('${dir.path}/repo/old').exists(), false);
    expect(reloads, 1);
    final git = await Process.run('git', [
      'hash-object',
      '${dir.path}/repo/note.typ',
    ]);
    expect(git.exitCode, 0);
    expect(
      (await fetcher.metadata(mount))!['blobs']['note.typ'],
      (git.stdout as String).trim(),
    );
  });
  test('unchanged commit upgrades old metadata', () async {
    client.sha = 'old';
    client.zip = zip('root/typst/note.typ');
    await File(
      '${dir.path}/repo/.tylog-mount.json',
    ).writeAsString(jsonEncode({'sha': 'old'}));
    await fetcher.refresh(mount);
    expect((await fetcher.metadata(mount))!['blobs']['note.typ'], isNotNull);
  });
  test('refresh preserves pending local file and its base sha', () async {
    final outbox = GitHubOutbox(Directory('${dir.path}/outbox'));
    fetcher = MountFetcher(
      cache: dir,
      client: client,
      reload: () async {},
      outbox: outbox,
    );
    await File('${dir.path}/repo/note.typ').writeAsString('mine');
    await File('${dir.path}/repo/.tylog-mount.json').writeAsString(
      jsonEncode({
        'sha': 'old',
        'blobs': {'note.typ': 'base'},
      }),
    );
    await outbox.enqueue(
      mountId: 'repo',
      path: 'note.typ',
      baseSha: 'base',
      message: 'edit',
      device: 'test',
    );
    client.zip = zip('root/typst/note.typ');
    await fetcher.refresh(mount);
    expect(await File('${dir.path}/repo/note.typ').readAsString(), 'mine');
    expect((await fetcher.metadata(mount))!['blobs']['note.typ'], 'base');
  });
  test('recovers interrupted swap before refresh', () async {
    await Directory('${dir.path}/repo').rename('${dir.path}/repo.old');
    client.fail = true;
    await expectLater(fetcher.refresh(mount), throwsStateError);
    expect(await File('${dir.path}/repo/old').readAsString(), 'old');
  });
  test('unsafe archive and network failure preserve cache', () async {
    client.zip = zip('root/typst/../../escape');
    await expectLater(fetcher.refresh(mount), throwsFormatException);
    expect(await File('${dir.path}/repo/old').readAsString(), 'old');
    client.fail = true;
    await expectLater(fetcher.refresh(mount), throwsStateError);
    expect(await File('${dir.path}/repo/old').readAsString(), 'old');
  });
  test('token prefers storage then desktop gh', () async {
    var calls = 0;
    Future<ProcessResult> run(String command, List<String> args) async {
      calls++;
      return ProcessResult(1, 0, ' gh-token\n', '');
    }

    expect(
      await githubToken(
        readToken: () async => 'stored',
        runProcess: run,
        desktop: true,
      ),
      'stored',
    );
    expect(calls, 0);
    expect(
      await githubToken(
        readToken: () async => null,
        runProcess: run,
        desktop: true,
      ),
      'gh-token',
    );
    expect(
      await githubToken(
        readToken: () async => null,
        runProcess: run,
        desktop: false,
      ),
      isNull,
    );
    expect(calls, 1);
  });
}
