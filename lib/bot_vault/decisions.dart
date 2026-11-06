import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';

Future<void> checkBotManifest(String path) async {
  final file = File('$path/bot-vault.json');
  if (!await file.exists()) {
    throw const FormatException('Missing bot-vault.json');
  }
  final manifest = jsonDecode(await file.readAsString());
  if (manifest is! Map ||
      manifest['schema'] is! int ||
      manifest['schema'] < 1) {
    throw const FormatException('Invalid bot vault manifest');
  }
  if (manifest['schema'] > 1) {
    throw const FormatException('Bot vault needs newer TyLog');
  }
}

// Record locks are process-scoped on POSIX; flock also serializes isolates.
Future<T> _withIsolateLock<T>(String path, Future<T> Function() action) async {
  if (Platform.isWindows) return action();
  final libc = DynamicLibrary.process();
  final malloc = libc
      .lookupFunction<
        Pointer<Uint8> Function(IntPtr),
        Pointer<Uint8> Function(int)
      >('malloc');
  final free = libc
      .lookupFunction<
        Void Function(Pointer<Uint8>),
        void Function(Pointer<Uint8>)
      >('free');
  final open = libc
      .lookupFunction<
        Int32 Function(Pointer<Uint8>, Int32),
        int Function(Pointer<Uint8>, int)
      >('open');
  final flock = libc
      .lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>(
        'flock',
      );
  final close = libc.lookupFunction<Int32 Function(Int32), int Function(int)>(
    'close',
  );
  final errno = libc
      .lookupFunction<Pointer<Int32> Function(), Pointer<Int32> Function()>(
        Platform.isMacOS || Platform.isIOS
            ? '__error'
            : Platform.isAndroid
            ? '__errno'
            : '__errno_location',
      );
  await File(path).create();
  final bytes = utf8.encode(path);
  final pointer = malloc(bytes.length + 1);
  if (pointer == nullptr) throw StateError('Could not allocate lock path');
  pointer.asTypedList(bytes.length + 1).setAll(0, [...bytes, 0]);
  final fd = open(pointer, 0);
  free(pointer);
  if (fd < 0) throw FileSystemException('Could not open bot lock', path);
  try {
    while (flock(fd, 2 | 4) != 0) {
      final error = errno().value;
      // EWOULDBLOCK is 35 on Darwin and 11 on Linux/Android.
      if (error != (Platform.isMacOS || Platform.isIOS ? 35 : 11)) {
        throw FileSystemException(
          'Could not lock bot outbox (errno $error)',
          path,
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    try {
      return await action();
    } finally {
      flock(fd, 8);
    }
  } finally {
    close(fd);
  }
}

class BotVaultDecisions {
  BotVaultDecisions(this.root);
  final Directory root;

  Future<Set<String>> decidedItems() async {
    await checkBotManifest(root.path);
    final file = File('${root.path}/outbox/decisions.jsonl');
    if (!await file.exists()) return {};
    final content = await file.readAsString();
    final lines = content.split('\n')..removeLast();
    final result = <String>{};
    for (final line in lines) {
      try {
        final row = jsonDecode(line);
        if (row is Map &&
            row['schema'] is int &&
            row['schema'] == 1 &&
            row['id'] is String &&
            (row['id'] as String).isNotEmpty &&
            row['at'] is String &&
            (row['at'] as String).isNotEmpty &&
            row['item_id'] is String &&
            {'accepted', 'rejected', 'dismissed'}.contains(row['action'])) {
          result.add(row['item_id'] as String);
        }
      } on FormatException {
        // Ignore rows the bot cannot consume.
      }
    }
    return result;
  }

  Future<void> record(String itemId, String action) async {
    if (!RegExp(r'^item-[a-zA-Z0-9_-]+$').hasMatch(itemId) ||
        !{'accepted', 'rejected', 'dismissed'}.contains(action)) {
      throw const FormatException('Invalid bot item or decision');
    }
    await checkBotManifest(root.path);
    final item = File('${root.path}/items/$itemId.typ');
    if (!await item.exists()) {
      throw FileSystemException('Bot item not found', item.path);
    }
    final dir = Directory('${root.path}/outbox');
    await dir.create(recursive: true);
    return _withIsolateLock('${dir.path}/.decisions.lock', () async {
      final file = await File(
        '${dir.path}/decisions.jsonl',
      ).open(mode: FileMode.append);
      try {
        await file.lock(FileLock.blockingExclusive);
        await checkBotManifest(root.path);
        await file.setPosition(0);
        final content = utf8.decode(await file.read(await file.length()));
        if (content.isNotEmpty && !content.endsWith('\n')) {
          throw const FormatException('Incomplete bot outbox row');
        }
        for (final line in const LineSplitter().convert(content)) {
          try {
            final row = jsonDecode(line);
            if (row is Map &&
                row['schema'] == 1 &&
                row['item_id'] == itemId &&
                row['action'] == action &&
                row['id'] is String &&
                (row['id'] as String).isNotEmpty &&
                row['at'] is String &&
                (row['at'] as String).isNotEmpty) {
              return;
            }
          } on FormatException {
            /* Preserve unrecognized rows. */
          }
        }
        final random = Random.secure();
        final id = List.generate(
          16,
          (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join();
        await file.setPosition(await file.length());
        await file.writeString(
          '${jsonEncode({'schema': 1, 'id': id, 'item_id': itemId, 'at': DateTime.now().toUtc().toIso8601String(), 'action': action})}\n',
        );
        await file.flush();
      } finally {
        await file.close();
      }
    });
  }
}
