import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:tylog_core/models.dart';
import 'package:tylog_core/scanner.dart';
import 'package:tylog_core/storage.dart';

/// Rewrites the file between the scan's hash probe and its read, which is the
/// autosave landing in the gap between two SAF round trips.
///
/// The entry used to keep the probe's hash while every field came from the
/// later read — one version's identity on another version's metadata. It then
/// matched on disk forever, was never re-inspected, and travelled to peers
/// through the donor, which pairs entries by exactly this hash.
class _RewriteBetweenHashAndRead extends LocalVaultStorage {
  _RewriteBetweenHashAndRead(super.root);

  String? rewriteOnHash;
  String? rewriteTo;

  @override
  Future<String> hash(String path) async {
    final digest = await super.hash(path);
    if (path == rewriteOnHash) {
      rewriteOnHash = null;
      await super.writeText(path, rewriteTo!);
    }
    return digest;
  }
}

void main() {
  test('the stored hash describes the bytes the entry was built from', () async {
    final root = await Directory.systemTemp.createTemp('tylog_hash_gap_');
    addTearDown(() => root.delete(recursive: true));
    final storage = _RewriteBetweenHashAndRead(root);
    const before = '#import "/_system/tylog.typ" as tylog\n\n= Before\n';
    const after = '#import "/_system/tylog.typ" as tylog\n\n= After\n';
    await storage.writeText('notes/a.typ', before);

    // A cached entry with a stale hash and a stale fingerprint, so the scan
    // takes the hash-probe branch rather than the cheap fingerprint one.
    final first = await scanVaultStorage(storage);
    final seeded = VaultIndex(
      notesByPath: {
        'notes/a.typ': first.notesByPath['notes/a.typ']!.copyWith(
          fingerprint: 'stale:0',
          contentHash: 'not-the-current-hash',
        ),
      },
      backlinksByTarget: const {},
    );

    storage
      ..rewriteOnHash = 'notes/a.typ'
      ..rewriteTo = after;
    final rebuilt = await scanVaultStorage(storage, previous: seeded);
    final note = rebuilt.notesByPath['notes/a.typ']!;

    expect(
      note.contentHash,
      sha256.convert(utf8.encode(after)).toString(),
      reason: 'the hash must match the bytes the entry describes',
    );
    expect(
      note.contentHash,
      isNot(sha256.convert(utf8.encode(before)).toString()),
    );
  });
}
