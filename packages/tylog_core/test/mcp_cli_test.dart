import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
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
    await process.stdin.close();
    expect(await process.exitCode, 0);
    await done;
    expect(rows.map((r) => r['id']), [1, 2, 3, 4, 5]);
    expect(rows[0]['result']['protocolVersion'], '2024-11-05');
    expect(
      (rows[1]['result']['tools'] as List).map((t) => t['name']),
      containsAll(['search', 'get_note']),
    );
    expect(rows[2]['result']['content'][0]['text'], contains('Apple'));
    expect(rows[3]['result']['content'][0]['text'], source);
    expect(rows[4]['result']['isError'], true);
    expect(await note.readAsString(), source);
  });
}
