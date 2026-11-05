import 'dart:convert';
import 'dart:io';

import 'package:tylog_core/tylog_core.dart';
import 'package:tylog_core/values.dart' show typstString;

import 'tylog.dart' show generateHealthReport;

const _tools = [
  {
    'name': 'daily_append',
    'description': 'Append literal text to an existing daily note.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'date': {'type': 'string', 'description': 'Day in YYYY-MM-DD format'},
        'text': {'type': 'string', 'minLength': 1},
      },
      'required': ['date', 'text'],
    },
  },
  {
    'name': 'incoming_list',
    'description': 'List vault notes with new attention.',
    'inputSchema': {'type': 'object', 'properties': {}},
  },
  {
    'name': 'health_report',
    'description':
        'Read the latest saved health report or generate a fresh one.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'refresh': {'type': 'boolean'},
      },
    },
  },
  {
    'name': 'backlinks',
    'description': 'List notes linking to a uniquely identified note.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'id': {'type': 'string', 'minLength': 1},
      },
      'required': ['id'],
    },
  },
  {
    'name': 'list_tasks',
    'description': 'List tasks in the vault.',
    'inputSchema': {'type': 'object', 'properties': {}},
  },
  {
    'name': 'search',
    'description':
        'Search note source text, ignoring case; returns up to 50 matches.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'query': {'type': 'string', 'minLength': 1},
      },
      'required': ['query'],
    },
  },
  {
    'name': 'get_note',
    'description': 'Read a note by its unique TyLog ID.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'id': {'type': 'string', 'minLength': 1},
      },
      'required': ['id'],
    },
  },
];

Future<void> serveMcp(
  Directory root,
  Stream<List<int>> input,
  IOSink output,
) async {
  if ((await inspectVaultStorage(LocalVaultStorage(root))).kind !=
      VaultStorageKind.validVault) {
    throw StateError('TyLog vault marker is missing or invalid');
  }
  await for (final line
      in input.transform(utf8.decoder).transform(const LineSplitter())) {
    Object? id;
    try {
      final request = jsonDecode(line);
      if (request is! Map ||
          request['jsonrpc'] != '2.0' ||
          request['method'] is! String) {
        throw const FormatException('Invalid request');
      }
      id = request['id'];
      if (!request.containsKey('id')) continue;
      final method = request['method'];
      final params = request['params'];
      Object result;
      switch (method) {
        case 'initialize':
          final version = params is Map ? params['protocolVersion'] : null;
          result = {
            'protocolVersion':
                const ['2024-11-05', '2025-03-26'].contains(version)
                ? version
                : '2025-03-26',
            'capabilities': {'tools': {}},
            'serverInfo': {'name': 'tylog', 'version': '0.1.0'},
          };
        case 'ping':
          result = <String, Object>{};
        case 'tools/list':
          result = {'tools': _tools};
        case 'tools/call':
          result = await _call(root, params);
        default:
          output.writeln(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': id,
              'error': {'code': -32601, 'message': 'Method not found'},
            }),
          );
          continue;
      }
      output.writeln(
        jsonEncode({'jsonrpc': '2.0', 'id': id, 'result': result}),
      );
    } catch (_) {
      output.writeln(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': id,
          'error': {'code': -32600, 'message': 'Invalid request'},
        }),
      );
    }
  }
  await output.flush();
}

Future<Object> _call(Directory root, Object? params) async {
  Map<String, Object> reply(String text, {bool error = false}) => {
    'content': [
      {'type': 'text', 'text': text},
    ],
    if (error) 'isError': true,
  };
  if (params is! Map || params['arguments'] is! Map) {
    return reply('Invalid arguments', error: true);
  }
  final name = params['name'];
  final args = params['arguments'] as Map;
  if (name == 'daily_append') {
    final date = args['date'];
    final text = args['text'];
    if (date is! String ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
        DateTime.tryParse(date)?.toIso8601String().substring(0, 10) != date ||
        text is! String ||
        text.trim().isEmpty ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(text)) {
      return reply('Invalid arguments', error: true);
    }
    final path =
        'daily/${date.substring(0, 4)}/${date.substring(5, 7)}/$date.typ';
    try {
      for (final part in [
        'daily',
        'daily/${date.substring(0, 4)}',
        'daily/${date.substring(0, 4)}/${date.substring(5, 7)}',
      ]) {
        if (await FileSystemEntity.type(
              '${root.path}/$part',
              followLinks: false,
            ) !=
            FileSystemEntityType.directory) {
          throw const FileSystemException('Unsafe or missing daily directory');
        }
      }
      if (await FileSystemEntity.type(
            '${root.path}/$path',
            followLinks: false,
          ) !=
          FileSystemEntityType.file) {
        throw const FileSystemException('Daily note not found');
      }
      for (final part in [
        '_system',
        '_system/decisions',
        '_system/decisions/mcp.jsonl',
      ]) {
        final type = await FileSystemEntity.type(
          '${root.path}/$part',
          followLinks: false,
        );
        if (type != FileSystemEntityType.notFound &&
            type !=
                (part.endsWith('.jsonl')
                    ? FileSystemEntityType.file
                    : FileSystemEntityType.directory)) {
          throw const FileSystemException('Unsafe decision ledger');
        }
      }
      final storage = LocalVaultStorage(root);
      final source = await storage.readText(path);
      guardNoteWrite(path, utf8.encode(source));
      final note = scanNote(path, source);
      if (!RegExp(
            r'^\s*#show\s*:\s*tylog\.note\.with\s*\([\s\S]*?\)',
            multiLine: true,
          ).hasMatch(source) ||
          note.kind != 'daily' ||
          note.id != date ||
          dailyDayOf(note) != date) {
        throw const FormatException('Target is not the requested daily note');
      }
      final updated = appendAboveAutoBlock(
        source,
        '#text(${typstString(text)})',
      );
      await storage.writeText(path, updated);
      await storage.appendBytes(
        '_system/decisions/mcp.jsonl',
        utf8.encode(
          encodeDecisions([
            Decision(
              at: DateTime.now().toUtc().toIso8601String(),
              device: 'mcp',
              item: date,
              source: 'mcp',
              action: 'added-to-today',
              target: path,
            ),
          ]),
        ),
      );
      return reply(jsonEncode({'path': path}));
    } catch (error) {
      return reply('Unable to append daily note: $error', error: true);
    }
  }
  if (name == 'health_report') {
    if (args.containsKey('refresh') && args['refresh'] is! bool) {
      return reply('Invalid arguments', error: true);
    }
    try {
      if (args['refresh'] == true) {
        final now = DateTime.now();
        final date =
            '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
        for (final path in ['_system', '_system/health']) {
          final type = await FileSystemEntity.type(
            '${root.path}/$path',
            followLinks: false,
          );
          if (type != FileSystemEntityType.notFound &&
              type != FileSystemEntityType.directory) {
            throw const FileSystemException('Unsafe health directory');
          }
        }
        for (final path in [
          'typst-cursor.json',
          '$date.json',
          '$date.json.tmp',
        ]) {
          if (await FileSystemEntity.type(
                '${root.path}/_system/health/$path',
                followLinks: false,
              ) ==
              FileSystemEntityType.link) {
            throw const FileSystemException('Unsafe health file');
          }
        }
        return reply(await generateHealthReport(root));
      }
      final directory = Directory('${root.path}/_system/health');
      if (await FileSystemEntity.type(
                '${root.path}/_system',
                followLinks: false,
              ) !=
              FileSystemEntityType.directory ||
          await FileSystemEntity.type(directory.path, followLinks: false) !=
              FileSystemEntityType.directory) {
        return reply(
          'No health report found; run tylog vault-health first',
          error: true,
        );
      }
      final reports = <File>[];
      await for (final entry in directory.list(followLinks: false)) {
        if (entry is File &&
            RegExp(
              r'^\d{4}-\d{2}-\d{2}\.json$',
            ).hasMatch(entry.uri.pathSegments.last)) {
          reports.add(entry);
        }
      }
      if (reports.isEmpty) {
        return reply(
          'No health report found; run tylog vault-health first',
          error: true,
        );
      }
      reports.sort((a, b) => b.path.compareTo(a.path));
      final source = await reports.first.readAsString();
      if (jsonDecode(source) is! Map) {
        throw const FormatException('Invalid report');
      }
      return reply(source);
    } catch (error) {
      return reply('Unable to read health report: $error', error: true);
    }
  }
  final value = args[name == 'search' ? 'query' : 'id'];
  if (name == 'list_tasks' || name == 'backlinks' || name == 'incoming_list') {
    if (name == 'backlinks' && (value is! String || value.trim().isEmpty)) {
      return reply('Invalid arguments', error: true);
    }
    try {
      final index = await scanVaultStorage(
        ReadOnlyVaultStorage(LocalVaultStorage(root)),
      );
      if (name == 'incoming_list') {
        final notes =
            index.notes.where((note) => attentionOf(note) == 'new').toList()
              ..sort((a, b) => a.path.compareTo(b.path));
        return reply(
          jsonEncode([
            for (final note in notes)
              {
                'id': note.id,
                'title': note.title,
                'path': note.path,
                'kind': note.kind,
                'date': note.date,
              },
          ]),
        );
      }
      if (name == 'list_tasks') {
        return reply(
          jsonEncode([for (final task in index.tasks) task.toJson()]),
        );
      }
      final targets = index.notes.where((note) => note.id == value).toList();
      if (targets.length != 1) {
        return reply(
          targets.isEmpty ? 'Note not found' : 'Note ID is ambiguous',
          error: true,
        );
      }
      return reply(
        jsonEncode([
          for (final path
              in index.backlinksByTarget[targets.single.path] ?? <String>[])
            if (index.notesByPath[path] case final note?)
              {'id': note.id, 'title': note.title, 'path': note.path},
        ]),
      );
    } catch (error) {
      return reply('Unable to read vault: $error', error: true);
    }
  }
  if ((name != 'search' && name != 'get_note') ||
      value is! String ||
      value.trim().isEmpty) {
    return reply('Unknown tool or invalid arguments', error: true);
  }
  try {
    final matches = <({NoteRef note, String source})>[];
    for (final dir in [
      'daily',
      'notes',
      'projects',
      'articles',
      'screenshots',
      'ext',
    ]) {
      final folder = Directory('${root.path}/$dir');
      if (!await folder.exists() ||
          await FileSystemEntity.type(folder.path, followLinks: false) !=
              FileSystemEntityType.directory) {
        continue;
      }
      await for (final entry in folder.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entry is! File || !entry.path.endsWith('.typ')) continue;
        final source = await entry.readAsString();
        final path = entry.path
            .substring(root.path.length + 1)
            .replaceAll(Platform.pathSeparator, '/');
        final note = scanNote(path, source);
        if (name == 'search'
            ? source.toLowerCase().contains(value.toLowerCase())
            : note.id == value) {
          matches.add((note: note, source: source));
        }
      }
    }
    if (name == 'get_note') {
      if (matches.length != 1) {
        return reply(
          matches.isEmpty ? 'Note not found' : 'Note ID is ambiguous',
          error: true,
        );
      }
      return reply(matches.single.source);
    }
    matches.sort((a, b) => a.note.path.compareTo(b.note.path));
    return reply(
      jsonEncode([
        for (final match in matches.take(50))
          {
            'id': match.note.id,
            'title': match.note.title,
            'path': match.note.path,
          },
      ]),
    );
  } catch (error) {
    return reply('Unable to read vault: $error', error: true);
  }
}
