import 'dart:convert';

import 'package:tylog_core/storage.dart';

/// Single-owner gate for a sync+reindex pass over one vault.
///
/// The UI process and the background sync worker are separate Flutter engines
/// (and can be separate processes), so nothing in-memory can arbitrate between
/// them. `.tylog/` never syncs, so the lock file is purely local — exactly the
/// scope a device-level owner needs.
///
/// ponytail: no heartbeat and no atomic compare-and-swap. The holder declares
/// how long it may run and the lock expires on its own; the read-then-write
/// race window is milliseconds wide and losing it means two syncs overlap,
/// which the existing checksum/conflict machinery already survives.
///
/// The declared deadline replaced a fixed 10-minute staleness rule, because
/// that rule and the holder's actual lifetime were unrelated constants in two
/// languages. WorkManager destroys the background engine at 9 minutes
/// (`VaultSyncWorker.TIMEOUT_MILLIS`) without unwinding Dart, so [release]
/// never ran and the lock sat for the remaining minute — or, on a hard kill
/// during the cheap etag probe, for the full ten. In the other direction a
/// rebuild longer than ten minutes let the UI take a lock the service was
/// still using, and both then wrote the same index, the same donor and the
/// same search index.
///
/// A heartbeat would fix neither cleanly: it costs periodic writes on the
/// single fair-locked SAF write thread — least likely to land exactly when a
/// long scan is saturating it — and it only shrinks both windows. A declared
/// deadline costs nothing extra and, for the one holder that can be hard
/// killed, is a fact rather than an estimate.
class VaultLock {
  static const path = '.tylog/vault.lock';

  /// How long a holder is believed when it does not say. Also the fallback for
  /// a lock written before deadlines existed.
  static const staleAfter = Duration(minutes: 10);

  /// Takes the lock for [owner], for at most [validFor]. Returns false if
  /// another owner holds an unexpired lock; re-acquiring one's own lock
  /// re-declares the deadline.
  static Future<bool> acquire(
    VaultStorage storage,
    String owner, {
    Duration validFor = staleAfter,
  }) async {
    if (await heldByOther(storage, owner)) return false;
    final now = DateTime.now();
    await storage.writeBytes(
      path,
      utf8.encode(
        jsonEncode({
          'owner': owner,
          'millis': now.millisecondsSinceEpoch,
          'expiresAt': now.add(validFor).millisecondsSinceEpoch,
        }),
      ),
    );
    return true;
  }

  static Future<bool> heldByOther(VaultStorage storage, String owner) async {
    final holder = await _read(storage);
    if (holder == null || holder.owner == owner) return false;
    return DateTime.now().isBefore(holder.expiresAt);
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

  static Future<({String owner, DateTime expiresAt})?> _read(
    VaultStorage storage,
  ) async {
    try {
      if (!await storage.exists(path)) return null;
      final json =
          jsonDecode(await storage.readText(path)) as Map<String, Object?>;
      final millis = json['millis'] as int;
      // A lock written before deadlines existed still expires, on the old
      // rule. Absent means "written by an older build", not "never expires".
      final expiresAt =
          json['expiresAt'] as int? ?? millis + staleAfter.inMilliseconds;
      return (
        owner: json['owner'] as String,
        expiresAt: DateTime.fromMillisecondsSinceEpoch(expiresAt),
      );
    } catch (_) {
      // Unreadable lock = no lock; the next acquire overwrites it.
      return null;
    }
  }
}
