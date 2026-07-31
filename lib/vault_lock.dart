import 'dart:convert';

import 'package:tylog_core/storage.dart';

/// Single-owner gate for a sync+reindex pass over one vault.
///
/// The UI process and the background sync worker are separate Flutter engines
/// (and can be separate processes), so nothing in-memory can arbitrate between
/// them. `.tylog/` never syncs, so the lock file is purely local — exactly the
/// scope a device-level owner needs.
///
/// ponytail: no heartbeat and no atomic compare-and-swap. A crashed owner
/// stalls the other side for [staleAfter] at worst, and the next periodic run
/// recovers; the read-then-write race window is milliseconds wide and losing
/// it means two syncs overlap, which the existing checksum/conflict machinery
/// already survives (it is the same class of race as two devices syncing).
/// Add heartbeats only if a real overlap is ever observed.
class VaultLock {
  static const path = '.tylog/vault.lock';
  static const staleAfter = Duration(minutes: 10);

  /// Takes the lock for [owner]. Returns false if another owner holds a fresh
  /// lock; re-acquiring one's own lock refreshes the timestamp.
  static Future<bool> acquire(VaultStorage storage, String owner) async {
    if (await heldByOther(storage, owner)) return false;
    await storage.writeBytes(
      path,
      utf8.encode(
        jsonEncode({
          'owner': owner,
          'millis': DateTime.now().millisecondsSinceEpoch,
        }),
      ),
    );
    return true;
  }

  static Future<bool> heldByOther(VaultStorage storage, String owner) async {
    final holder = await _read(storage);
    if (holder == null || holder.owner == owner) return false;
    return DateTime.now().difference(holder.at) < staleAfter;
  }

  /// Releases only a lock [owner] actually holds — never someone else's.
  static Future<void> release(VaultStorage storage, String owner) async {
    final holder = await _read(storage);
    if (holder?.owner != owner) return;
    try {
      await storage.delete(path);
    } catch (_) {
      // A failed delete just leaves a lock that goes stale on its own.
    }
  }

  static Future<({String owner, DateTime at})?> _read(
    VaultStorage storage,
  ) async {
    try {
      if (!await storage.exists(path)) return null;
      final json =
          jsonDecode(await storage.readText(path)) as Map<String, Object?>;
      return (
        owner: json['owner'] as String,
        at: DateTime.fromMillisecondsSinceEpoch(json['millis'] as int),
      );
    } catch (_) {
      // Unreadable lock = no lock; the next acquire overwrites it.
      return null;
    }
  }
}
