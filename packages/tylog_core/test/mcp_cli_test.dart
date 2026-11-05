import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('daily_append writes literal text and rejects non-notes', () async {
    final vault = await Directory.systemTemp.createTemp('tylog_mcp_daily_');
    addTearDown(() => vault.delete(recursive: true));
    final settings = File('${vault.path}/.tylog/settings.json');
    await settings.parent.create(recursive: true);
    await settings.writeAsString('{"version":5}');
    final note = File('${vault.path}/daily/2026/11/2026-11-05.typ');
    await note.parent.create(recursive: true);
    const source =
        '#let tylog = (note: (..args) => body => body)\n'
        '#show: tylog.note.with(id: "2026-11-05", title: "Day", kind: "daily", date: "2026-11-05")\n'
        'Existing\n\n// tylog:auto-entities\n';
    await note.writeAsString(source);
    final process = await Process.start(Platform.resolvedExecutable, [
      'run',
      'bin/tylog.dart',
      'mcp',
      vault.path,
    ]);
    final responses = StreamIterator(
      process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
    );
    Future<Map> call(int id, String text) async {
      process.stdin.writeln(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': id,
          'method': 'tools/call',
          'params': {
            'name': 'daily_append',
            'arguments': {'date': '2026-11-05', 'text': text},
          },
        }),
      );
      expect(await responses.moveNext(), true);
      return (jsonDecode(responses.current) as Map)['result'] as Map;
    }

    expect((await call(1, r'Literal # [ ] \ " $'))['isError'], isNot(true));
    final written = await note.readAsString();
    expect(written, contains('Existing\n#text('));
    expect(
      written.indexOf('#text('),
      lessThan(written.indexOf('// tylog:auto-entities')),
    );
    final compile = await Process.run('typst', [
      'compile',
      '--root',
      vault.path,
      note.path,
      '${vault.path}/out.pdf',
    ]);
    expect(compile.exitCode, 0, reason: '${compile.stderr}');
    final ledger = File('${vault.path}/_system/decisions/mcp.jsonl');
    final lines = const LineSplitter().convert(await ledger.readAsString());
    expect(lines, hasLength(1));
    expect(
      jsonDecode(lines.single),
      containsPair('target', 'daily/2026/11/2026-11-05.typ'),
    );
    const bad = '{"revision":{},"node":{}}';
    await note.writeAsString(bad);
    expect((await call(2, 'no'))['isError'], true);
    expect(await note.readAsString(), bad);
    expect(
      const LineSplitter().convert(await ledger.readAsString()),
      hasLength(1),
    );
    await process.stdin.close();
    expect(await process.exitCode, 0);
    await responses.cancel();
  });

  test('incoming_list returns new-attention notes without writing', () async {
    final vault = await Directory.systemTemp.createTemp('tylog_mcp_incoming_');
    addTearDown(() => vault.delete(recursive: true));
    final settings = File('${vault.path}/.tylog/settings.json');
    await settings.parent.create(recursive: true);
    await settings.writeAsString('{"version":5}');
    final notes = Directory('${vault.path}/notes');
    await notes.create();
    final fresh = File('${notes.path}/a.typ');
    const source =
        '#show: tylog.note.with(id: "a", title: "Idea", kind: "idea", date: "2026-11-05")\n';
    await fresh.writeAsString(source);
    await File('${notes.path}/b.typ').writeAsString(
      '#show: tylog.note.with(id: "b", title: "Kept", kind: "idea", properties: (attention: "kept"))\n',
    );
    await File(
      '${notes.path}/c.typ',
    ).writeAsString('#show: tylog.note.with(id: "c", title: "Ordinary")\n');
    final process = await Process.start(Platform.resolvedExecutable, [
      'run',
      'bin/tylog.dart',
      'mcp',
      vault.path,
    ]);
    process.stdin.writeln(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'tools/call',
        'params': {'name': 'incoming_list', 'arguments': <String, Object>{}},
      }),
    );
    await process.stdin.close();
    final rows = await process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .toList();
    expect(await process.exitCode, 0);
    final result = (jsonDecode(rows.single) as Map)['result'];
    expect(result['isError'], isNot(true));
    expect(jsonDecode(result['content'][0]['text'] as String), [
      {
        'id': 'a',
        'title': 'Idea',
        'path': 'notes/a.typ',
        'kind': 'idea',
        'date': '2026-11-05',
      },
    ]);
    expect(await fresh.readAsString(), source);
    expect(await Directory('${vault.path}/_system').exists(), false);
  });
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

  test('health_report can generate a fresh report', () async {
    final vault = await Directory.systemTemp.createTemp('tylog_mcp_refresh_');
    addTearDown(() => vault.delete(recursive: true));
    final settings = File('${vault.path}/.tylog/settings.json');
    await settings.parent.create(recursive: true);
    await settings.writeAsString('{"version":5}');
    final note = File('${vault.path}/notes/broken.typ');
    await note.parent.create(recursive: true);
    await note.writeAsString('missing header');
    final process = await Process.start(Platform.resolvedExecutable, [
      'run',
      'bin/tylog.dart',
      'mcp',
      vault.path,
    ]);
    process.stdin.writeln(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'tools/call',
        'params': {
          'name': 'health_report',
          'arguments': {'refresh': true},
        },
      }),
    );
    await process.stdin.close();
    final rows = await process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .toList();
    expect(await process.exitCode, 0);
    final result = (jsonDecode(rows.single) as Map)['result'];
    expect(result['isError'], isNot(true));
    final report = jsonDecode(result['content'][0]['text'] as String) as Map;
    expect(report['scanned'], 1);
    expect(
      report['issues'],
      contains(
        predicate(
          (issue) =>
              issue is Map &&
              issue['path'] == 'notes/broken.typ' &&
              issue['code'] == 'missing-note-header',
        ),
      ),
    );
    expect(
      await File(
        '${vault.path}/_system/health/${report['date']}.json',
      ).exists(),
      true,
    );
  });

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
        'incoming_list',
        'daily_append',
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
