import 'dart:async';
import 'dart:convert';

import '../nextcloud_sync.dart';
import '../vault.dart';

final startupClock = Stopwatch();
final _entries = <Map<String, Object?>>[];
bool _flushing = false;
bool _flushed = false;
Timer? _flushTimer;

void startupMark(String event, [Map<String, Object?> extra = const {}]) {
  if (_entries.length >= 200) return;
  final ms = startupClock.elapsedMilliseconds;
  _entries.add({'event': 'startup', 'mark': event, 'ms': ms, ...extra});
  // print is intentional: startup diagnostics must reach release logcat.
  // ignore: avoid_print
  print('TYLOG_STARTUP $event ${ms}ms ${jsonEncode(extra)}');
}

/// Called after opening a vault and after either completion mark is recorded.
void flushStartupTraceWhenReady(Vault vault) {
  if (_flushed || _flushing) return;
  final opens = _entries.where((entry) => entry['mark'] == 'open-start');
  if (opens.isEmpty) return;
  final elapsed = startupClock.elapsedMilliseconds - (opens.first['ms'] as int);
  _flushTimer ??= Timer(
    Duration(milliseconds: (90000 - elapsed).clamp(0, 90000)),
    () => unawaited(flushStartupTrace(vault)),
  );
  if (_entries.any((entry) => entry['mark'] == 'index-published') &&
      _entries.any((entry) => entry['mark'] == 'sync-done')) {
    unawaited(flushStartupTrace(vault));
  }
}

Future<void> flushStartupTrace(Vault vault) async {
  if (_flushed || _flushing || _entries.isEmpty) return;
  _flushing = true;
  _flushTimer?.cancel();
  try {
    final timestamp = DateTime.now().toUtc().toIso8601String();
    await appendVaultTrace(vault, [
      for (final entry in _entries) {...entry, 'timestamp': timestamp},
    ]);
  } catch (_) {
    // Diagnostics must never interrupt startup.
  } finally {
    _flushed = true;
    _flushing = false;
  }
}
