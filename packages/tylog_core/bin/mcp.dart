import 'dart:convert';
import 'dart:io';

import 'package:tylog_core/tylog_core.dart';

const _tools = [
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
  final value = args[name == 'search' ? 'query' : 'id'];
  if (name == 'list_tasks' || name == 'backlinks') {
    if (name == 'backlinks' && (value is! String || value.trim().isEmpty)) {
      return reply('Invalid arguments', error: true);
    }
    try {
      final index = await scanVaultStorage(
        ReadOnlyVaultStorage(LocalVaultStorage(root)),
      );
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
