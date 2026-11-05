import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'health_report returns the latest saved report without writing',
    () async {
      final vault = await Directory.systemTemp.createTemp('tylog_mcp_health_');
      addTearDown(() => vault.delete(recursive: true));
      final settings = File('${vault.path}/.tylog/settings.json');
      await settings.parent.create(recursive: true);
      await settings.writeAsString('{"version":5}');
      final process = await Process.start(Platform.resolvedExecutable, [
        'run',
        'bin/tylog.dart',
        'mcp',
        vault.path,
      ]);
      final responses = StreamIterator(
        process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
      );
      addTearDown(() async {
        await responses.cancel();
      });
      Future<Map> call(int id) async {
        process.stdin.writeln(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': id,
            'method': 'tools/call',
            'params': {
              'name': 'health_report',
              'arguments': <String, Object>{},
            },
          }),
        );
        expect(await responses.moveNext(), true);
        return jsonDecode(responses.current) as Map;
      }

      expect((await call(1))['result']['isError'], true);
      final health = Directory('${vault.path}/_system/health');
      await health.create(recursive: true);
      await File(
        '${health.path}/2026-11-01.json',
      ).writeAsString('{"scanned":1}');
      await File(
        '${health.path}/2026-11-05.json',
      ).writeAsString('{"scanned":2}');
      await File('${health.path}/typst-cursor.json').writeAsString('{}');
      final result = (await call(2))['result'];
      expect(jsonDecode(result['content'][0]['text'] as String), {
        'scanned': 2,
      });
      await process.stdin.close();
      expect(await process.exitCode, 0);
      expect(
        await File('${health.path}/2026-11-05.json').readAsString(),
        '{"scanned":2}',
      );
    },
  );

  test('MCP clients discover, search, and retrieve notes over stdio', () async {
    final vault = await Directory.systemTemp.createTemp('tylog_mcp_');
    addTearDown(() => vault.delete(recursive: true));
    final settings = File('${vault.path}/.tylog/settings.json');
    await settings.parent.create(recursive: true);
    await settings.writeAsString('{"version":5}');
    final note = File('${vault.path}/notes/a.typ');
    await note.parent.create(recursive: true);
    const source =
        '#show: tylog.note.with(id: "a", title: "Apple")\n= Apple\nOrchard\n';
    await note.writeAsString(source);
    final linked = File('${vault.path}/notes/b.typ');
    await linked.writeAsString(
      '#show: tylog.note.with(id: "b", title: "Bee")\n#tylog.ref-note("a")[Apple]\n#tylog.task(id: "t1", text: "Call", status: "todo")\n',
    );
    final process = await Process.start(Platform.resolvedExecutable, [
      'run',
      'bin/tylog.dart',
      'mcp',
      vault.path,
    ]);
    final rows = <Map>[];
    final done = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach((line) => rows.add(jsonDecode(line) as Map));
    void send(Object data) => process.stdin.writeln(jsonEncode(data));
    send({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'initialize',
      'params': {
        'protocolVersion': '2024-11-05',
        'capabilities': {},
        'clientInfo': {'name': 'test', 'version': '1'},
      },
    });
    send({'jsonrpc': '2.0', 'method': 'notifications/initialized'});
    send({'jsonrpc': '2.0', 'id': 2, 'method': 'tools/list'});
    send({
      'jsonrpc': '2.0',
      'id': 3,
      'method': 'tools/call',
      'params': {
        'name': 'search',
        'arguments': {'query': 'orchard'},
      },
    });
    send({
      'jsonrpc': '2.0',
      'id': 4,
      'method': 'tools/call',
      'params': {
        'name': 'get_note',
        'arguments': {'id': 'a'},
      },
    });
    send({
      'jsonrpc': '2.0',
      'id': 5,
      'method': 'tools/call',
      'params': {
        'name': 'get_note',
        'arguments': {'id': '../.tylog/settings.json'},
      },
    });
    for (final call in [
      {
        'id': 6,
        'name': 'backlinks',
        'arguments': {'id': 'a'},
      },
      {'id': 7, 'name': 'list_tasks', 'arguments': <String, Object>{}},
      {
        'id': 8,
        'name': 'backlinks',
        'arguments': {'id': 'missing'},
      },
    ]) {
      send({
        'jsonrpc': '2.0',
        'id': call['id'],
        'method': 'tools/call',
        'params': {'name': call['name'], 'arguments': call['arguments']},
      });
    }
    await process.stdin.close();
    expect(await process.exitCode, 0);
    await done;
    expect(rows.map((r) => r['id']), [1, 2, 3, 4, 5, 6, 7, 8]);
    expect(rows[0]['result']['protocolVersion'], '2024-11-05');
    expect(
      (rows[1]['result']['tools'] as List).map((t) => t['name']),
      containsAll([
        'search',
        'get_note',
        'backlinks',
        'list_tasks',
        'health_report',
      ]),
    );
    expect(rows[2]['result']['content'][0]['text'], contains('Apple'));
    expect(rows[3]['result']['content'][0]['text'], source);
    expect(rows[4]['result']['isError'], true);
    final backlinks =
        jsonDecode(rows[5]['result']['content'][0]['text'] as String) as List;
    expect(backlinks.single['id'], 'b');
    expect(backlinks.single['path'], 'notes/b.typ');
    final tasks =
        jsonDecode(rows[6]['result']['content'][0]['text'] as String) as List;
    expect(tasks.single['id'], 't1');
    expect(tasks.single['text'], 'Call');
    expect(rows[7]['result']['isError'], true);
    expect(await note.readAsString(), source);
  });
}
