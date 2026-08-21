import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/vault.dart';
import 'package:tylog_core/storage.dart';

/// Fails `readText` for one path, to prove a bad read never authorises a
/// delete.
class _UnreadableStorage extends LocalVaultStorage {
  _UnreadableStorage(super.root);

  final failReadsFor = <String>{};

  @override
  Future<String> readText(String path) async {
    if (failReadsFor.contains(path)) throw const FileSystemException('nope');
    return super.readText(path);
  }
}

/// A single character typed into the Today editor materialises the daily file.
/// Removing that character used to fail forever: `saveNote` refused the write,
/// so a 2-byte file stayed on disk that nothing could clean up, and the editor
/// stayed `dirty` — which also disabled idle maintenance and the midnight
/// rollover. One keystroke, permanently.
void main() {
  late _UnreadableStorage storage;
  late Vault vault;

  setUp(() async {
    final dir = await Directory.systemTemp.createTemp('tylog_empty_note_');
    addTearDown(() => dir.delete(recursive: true));
    storage = _UnreadableStorage(dir);
    vault = Vault.withStorage(storage);
  });

  const stray = 'daily/2026/08/2026-08-20.typ';

  test('emptying a note that only ever held a keystroke removes it', () async {
    await storage.writeText(stray, 'x');
    await vault.saveNote(stray, '');
    expect(await storage.exists(stray), isFalse);
  });

  test('emptying an untouched starter daily removes it', () async {
    final path = await vault.todayNote(DateTime.utc(2026, 8, 20));
    final starter = await storage.readText(path);
    expect(isPristineStarterNote(path, starter), isTrue);

    await vault.saveNote(path, '   \n');
    expect(await storage.exists(path), isFalse);
  });

  test('a real note still refuses to be blanked', () async {
    const path = 'notes/real.typ';
    await storage.writeText(
      path,
      '#import "/_system/tylog.typ" as tylog\n'
      '#show: tylog.note.with(id: "real", title: "Real")\n\n'
      '= Real\n\nSomething worth keeping.\n',
    );
    await expectLater(
      () => vault.saveNote(path, ''),
      throwsA(isA<ArgumentError>()),
    );
    expect(await storage.exists(path), isTrue);
  });

  test('saving an empty buffer never creates a file', () async {
    await vault.saveNote('daily/2026/08/2026-08-21.typ', '');
    expect(await storage.exists('daily/2026/08/2026-08-21.typ'), isFalse);
  });

  test('an unreadable note is never deleted on the strength of a bad read',
      () async {
    const path = 'notes/unreadable.typ';
    await storage.writeText(path, 'x');
    storage.failReadsFor.add(path);
    await expectLater(
      () => vault.saveNote(path, ''),
      throwsA(isA<ArgumentError>()),
    );
    expect(await storage.exists(path), isTrue);
  });

  test('a non-.typ file is untouched by the rule', () async {
    const path = 'assets/notes.txt';
    await storage.writeText(path, 'x');
    await vault.saveNote(path, '');
    expect(await storage.exists(path), isTrue);
    expect(await storage.readText(path), '');
  });
}
