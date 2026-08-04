/// A tylog package version bump must be shippable: helpers stamped with an
/// older version are managed (not custom), repair upgrades them, stale
/// vendored package versions are pruned, and the repo's own version
/// references cannot drift apart.
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:tylog_core/tylog_core.dart';

const _currentHelper = '''
// tylog-helper-version: 5
// tylog-package: 0.2.0
#import "packages/tylog/0.2.0/lib.typ" as package
#let note = package.note
''';

const _outdatedHelper = '''
// tylog-helper-version: 5
// tylog-package: 0.1.0
#import "packages/tylog/0.1.0/lib.typ" as package
#let note = package.note
''';

const _legacyHelper = '#let note(..args) = (body) => body\n';

void main() {
  group('classifyTylogHelper', () {
    test('marker with the current version is current', () {
      expect(
        classifyTylogHelper('$_currentHelper\n// user tweak',
            current: _currentHelper, legacy: _legacyHelper),
        TylogHelperKind.current,
      );
    });

    test('marker with an older version is outdated, not custom', () {
      expect(
        classifyTylogHelper(_outdatedHelper,
            current: _currentHelper, legacy: _legacyHelper),
        TylogHelperKind.outdated,
      );
    });

    test('no marker stays custom; exact legacy stays legacy', () {
      expect(
        classifyTylogHelper('#let note = none',
            current: _currentHelper, legacy: _legacyHelper),
        TylogHelperKind.custom,
      );
      expect(
        classifyTylogHelper(_legacyHelper,
            current: _currentHelper, legacy: _legacyHelper),
        TylogHelperKind.legacy,
      );
    });
  });

  group('initializeVaultStorage upgrade path', () {
    late Directory tmp;
    late LocalVaultStorage storage;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('tylog-upgrade-');
      storage = LocalVaultStorage(tmp);
    });

    tearDown(() => tmp.delete(recursive: true));

    Map<String, List<int>> managed() => {
          '_system/tylog.typ': _currentHelper.codeUnits,
          '_system/theme.typ': 'theme'.codeUnits,
          '_system/export.typ': 'export'.codeUnits,
          '_system/packages/tylog/0.2.0/lib.typ': 'lib v2'.codeUnits,
          '_system/packages/tylog/0.2.0/typst.toml': 'toml v2'.codeUnits,
        };

    test('outdated helper is replaced and the old package dir pruned',
        () async {
      await initializeVaultStorage(
        storage,
        managedFiles: managed(),
        currentHelper: _currentHelper,
        legacyHelper: _legacyHelper,
      );
      // Simulate a vault written by the previous release.
      await storage.writeText('_system/tylog.typ', _outdatedHelper);
      await storage.writeText(
          '_system/packages/tylog/0.1.0/lib.typ', 'lib v1');

      await initializeVaultStorage(
        storage,
        managedFiles: managed(),
        currentHelper: _currentHelper,
        legacyHelper: _legacyHelper,
      );

      expect(await storage.readText('_system/tylog.typ'), _currentHelper);
      expect(
          await storage.exists('_system/packages/tylog/0.1.0/lib.typ'), false);
      expect(
          await storage.exists('_system/packages/tylog/0.2.0/lib.typ'), true);
    });

    test('a custom helper is never overwritten', () async {
      await initializeVaultStorage(
        storage,
        managedFiles: managed(),
        currentHelper: _currentHelper,
        legacyHelper: _legacyHelper,
      );
      await storage.writeText('_system/tylog.typ', '#let note = none // mine');

      await initializeVaultStorage(
        storage,
        managedFiles: managed(),
        currentHelper: _currentHelper,
        legacyHelper: _legacyHelper,
      );

      expect(await storage.readText('_system/tylog.typ'),
          '#let note = none // mine');
    });
  });

  group('repo version consistency', () {
    test('typst.toml, helper marker and helper import agree', () {
      final root = _repoRoot();
      final toml =
          File('$root/typst/tylog/typst.toml').readAsStringSync();
      final helper =
          File('$root/typst/vault/tylog.typ').readAsStringSync();

      final tomlVersion = RegExp(r'^version\s*=\s*"(\d+\.\d+\.\d+)"',
              multiLine: true)
          .firstMatch(toml)![1];
      final marker = RegExp(r'^// tylog-package: (\d+\.\d+\.\d+)$',
              multiLine: true)
          .firstMatch(helper)![1];
      final import_ = RegExp(r'packages/tylog/(\d+\.\d+\.\d+)/lib\.typ')
          .firstMatch(helper)![1];

      expect(marker, tomlVersion,
          reason: 'helper marker must match typst.toml');
      expect(import_, tomlVersion,
          reason: 'helper import path must match typst.toml');
    });
  });
}

String _repoRoot() {
  var dir = Directory.current;
  while (!File('${dir.path}/pubspec.yaml').existsSync() ||
      !Directory('${dir.path}/typst/tylog').existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('repository root not found');
    }
    dir = parent;
  }
  return dir.path;
}
