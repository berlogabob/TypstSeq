import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/diagnostics/startup_trace.dart';
import 'package:tylog/vault.dart';
import 'package:tylog/vault_storage.dart';

void main() {
  test('startup marks are ordered, bounded, and flushed only once', () async {
    final root = await Directory.systemTemp.createTemp('tylog-startup-');
    addTearDown(() => root.delete(recursive: true));
    final vault = Vault.withStorage(LocalVaultStorage(root));
    final trace = File('${root.path}/.tylog/sync_trace.jsonl');
    await flushStartupTrace(vault);
    expect(await trace.exists(), isFalse);

    final printed = <String>[];
    startupClock.start();
    runZoned(
      () {
        startupMark('first', {'trigger': 'test'});
        startupMark('second');
        for (var i = 2; i < 201; i++) {
          startupMark('mark-$i');
        }
      },
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) => printed.add(line),
      ),
    );
    expect(await trace.exists(), isFalse);
    expect(printed, hasLength(200));
    expect(printed.first, matches(r'^TYLOG_STARTUP first \d+ms '));
    expect(jsonDecode(printed.first.split('ms ').last), {'trigger': 'test'});

    await Future.wait([flushStartupTrace(vault), flushStartupTrace(vault)]);
    final contents = await trace.readAsString();
    final entries = const LineSplitter()
        .convert(contents)
        .map((line) => jsonDecode(line) as Map<String, dynamic>)
        .toList();
    expect(entries, hasLength(200));
    expect(entries.map((entry) => entry['mark']), [
      'first',
      'second',
      for (var i = 2; i < 200; i++) 'mark-$i',
    ]);
    expect(entries.first['trigger'], 'test');
    var previousMs = 0;
    for (final entry in entries) {
      expect(entry['event'], 'startup');
      final ms = entry['ms'] as int;
      expect(ms, greaterThanOrEqualTo(previousMs));
      previousMs = ms;
      expect(DateTime.tryParse(entry['timestamp'] as String), isNotNull);
    }
    await flushStartupTrace(vault);
    expect(await trace.readAsString(), contents);
  });
}
