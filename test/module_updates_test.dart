import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/github/github_client.dart';
import 'package:tylog/github/module_updates.dart';
import 'package:tylog_core/tylog_core.dart';

class FakeClient extends GitHubClient {
  FakeClient(this.tag, this.assets, this.bytes);
  final String tag;
  final List<({String name, String url})> assets;
  final Uint8List bytes;
  int downloads = 0;
  @override
  Future<({String tag, List<({String name, String url})> assets})>
  latestRelease(String repo) async => (tag: tag, assets: assets);
  @override
  Future<Uint8List> downloadAsset(String url) async {
    downloads++;
    return bytes;
  }
}

Uint8List packBytes() {
  final content = utf8.encode('lesson');
  final manifest = utf8.encode(
    jsonEncode({
      'schema': 1,
      'id': 'course',
      'version': '1.10.0',
      'files': [
        {'path': 'notes/a.typ', 'sha256': sha256.convert(content).toString()},
      ],
    }),
  );
  final archive = Archive()
    ..addFile(ArchiveFile('manifest.json', manifest.length, manifest))
    ..addFile(ArchiveFile('notes/a.typ', content.length, content));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  test('compares semantic versions and v prefix', () {
    expect(compareModuleVersions('1.2.0', '1.10.0'), lessThan(0));
    expect(compareModuleVersions('v1.2.0', '1.2.0'), 0);
  });
  test('checks newer releases only and handles missing assets', () async {
    const module = InstalledModule(
      id: 'course',
      name: 'Course',
      version: '1.2.0',
      github: 'owner/repo',
    );
    const assets = [(name: 'course.tylogpack', url: 'asset')];
    for (final tag in ['v1.2.0', 'v1.1.0']) {
      final client = FakeClient(tag, assets, packBytes());
      expect(await checkModuleUpdate(client, module), isNull);
      expect(client.downloads, 0);
    }
    final missing = FakeClient('v1.10.0', [], packBytes());
    expect(await checkModuleUpdate(missing, module), isNull);
    expect(missing.downloads, 0);
    final newer = FakeClient('v1.10.0', assets, packBytes());
    expect((await checkModuleUpdate(newer, module))!.version, '1.10.0');
    expect(newer.downloads, 1);
  });
  test(
    'GitHub pack installs files and preserves source and unknown keys',
    () async {
      final dir = await Directory.systemTemp.createTemp('module_update_');
      try {
        final storage = LocalVaultStorage(dir);
        await storage.writeText(
          moduleRecordPath('course'),
          jsonEncode({
            'files': {},
            'extra': 42,
            'source': {'other': true},
          }),
        );
        final client = FakeClient('v1.10.0', [
          (name: 'course.tylogpack', url: 'asset'),
        ], packBytes());
        final pack = await downloadGitHubModule(client, 'owner/repo');
        await installModule(
          storage,
          pack,
          DateTime(2026),
          github: 'owner/repo',
        );
        expect(await storage.readText('projects/course/a.typ'), 'lesson');
        await installModule(storage, pack, DateTime(2026));
        final record =
            jsonDecode(await storage.readText(moduleRecordPath('course')))
                as Map;
        expect(record['extra'], 42);
        expect(record['source'], {'github': 'owner/repo', 'other': true});
        expect(
          (await listInstalledModules(storage)).single.github,
          'owner/repo',
        );
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
}
