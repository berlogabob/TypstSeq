import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tylog/vault_registry.dart';
import 'package:tylog/vault_storage.dart';

/// Profile-only SAF contention harness for the real Android tree vault.
///
/// Run against the release-signed profile app with
/// `flutter drive --profile --keep-app-running --driver=test_driver/integration_test.dart`
/// and this file as the target. The active vault must be the disposable audit
/// fixture named `TyLogAuditVault`; this test never touches any other subtree.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('SAF idle versus attachment contention profile', (_) async {
    final registry = await VaultRegistry.load();
    final entry = registry.active;
    expect(entry.storageKind, 'android-tree');
    expect(entry.name, 'TyLogAuditVault');
    final storage = entry.storage;
    expect(storage, isA<AndroidTreeVaultStorage>());
    final saf = storage as AndroidTreeVaultStorage;
    expect(await saf.hasAccess(), isTrue);

    // Coordinator-created marker: do not mutate the tree until the exact
    // disposable audit fixture has been positively identified.
    const auditMarker = 'TyLogAuditVault\n';
    expect(
      await storage.readText('README-AUDIT.txt'),
      auditMarker,
      reason: 'missing exact coordinator marker; refusing device writes',
    );

    const root = '.tylog/device-audit';
    final expected = <String, Uint8List>{};

    Future<void> cleanup() async {
      try {
        final entries = await storage.list(path: root, recursive: true);
        final paths = <String>{
          for (final item in entries) item.path,
          root,
        }.toList()..sort((a, b) => b.length.compareTo(a.length));
        for (final path in paths) {
          await storage.delete(path);
        }
      } catch (error) {
        // Keep cleanup bounded to the dedicated subtree; never fall back to
        // deleting the vault root when a provider call fails.
        // ignore: avoid_print
        print('SAF-CONTENTION cleanup failed: $error');
      }
    }

    addTearDown(cleanup);
    await storage.createDirectory('$root/notes');

    for (var i = 0; i < 30; i++) {
      final path = '$root/notes/note-${i.toString().padLeft(2, '0')}.typ';
      final bytes = Uint8List.fromList('T26 deterministic note $i\n'.codeUnits);
      await storage.writeBytes(path, bytes);
      expected[path] = bytes;
    }

    final idleSamples = <Duration>[];
    final notePaths = expected.keys.toList();
    for (var cycle = 0; cycle < 30; cycle++) {
      final path = notePaths[cycle];
      final stopwatch = Stopwatch()..start();
      final current = await storage.readBytes(path);
      final next = Uint8List.fromList([
        ...current,
        ...'cycle=$cycle\n'.codeUnits,
      ]);
      await storage.writeBytes(path, next);
      expected[path] = next;
      stopwatch.stop();
      idleSamples.add(stopwatch.elapsed);
    }

    final attachment = Uint8List.fromList(
      List<int>.generate(8 * 1024 * 1024, (i) => i & 0xff),
    );
    final transferStopwatch = Stopwatch()..start();
    final transfer = () async {
      await storage.createDirectory('$root/attachments');
      for (var round = 0; round < 3; round++) {
        await storage.writeBytes(
          '$root/attachments/large-$round.bin',
          attachment,
        );
      }
    }();

    var overlappingSamples = 0;
    var transferActive = true;
    final contendedSamples = <Duration>[];
    for (var cycle = 0; cycle < 30; cycle++) {
      final path = notePaths[cycle];
      final stopwatch = Stopwatch()..start();
      final current = await storage.readBytes(path);
      final next = Uint8List.fromList([
        ...current,
        ...'contended=$cycle\n'.codeUnits,
      ]);
      await storage.writeBytes(path, next);
      expected[path] = next;
      stopwatch.stop();
      contendedSamples.add(stopwatch.elapsed);
      if (transferActive) overlappingSamples++;
    }
    await transfer;
    transferActive = false;
    transferStopwatch.stop();

    String summary(List<Duration> samples) {
      final micros = samples.map((sample) => sample.inMicroseconds).toList()
        ..sort();
      int percentile(double value) =>
          micros[(micros.length * value).ceil() - 1];
      return 'p50=${percentile(.50) / 1000}ms '
          'p95=${percentile(.95) / 1000}ms '
          'max=${micros.last / 1000}ms';
    }

    // ignore: avoid_print
    print('SAF-CONTENTION idle ${summary(idleSamples)}');
    // ignore: avoid_print
    print('SAF-CONTENTION contended ${summary(contendedSamples)}');
    // ignore: avoid_print
    print(
      'SAF-CONTENTION transfer=${transferStopwatch.elapsed.inMilliseconds}ms '
      'bytes=${attachment.length * 3} overlapSamples=$overlappingSamples/30',
    );

    for (final entry in expected.entries) {
      final bytes = await storage.readBytes(entry.key);
      expect(bytes, orderedEquals(entry.value));
      expect(
        sha256.convert(bytes).toString(),
        sha256.convert(entry.value).toString(),
      );
      expect(utf8.decode(bytes), utf8.decode(entry.value));
    }
  }, skip: !Platform.isAndroid);
}
