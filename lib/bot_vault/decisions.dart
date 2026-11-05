import 'dart:convert';
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

class BotVaultDecisions {
  BotVaultDecisions(this.root);
  final Directory root;

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
    final file = await File(
      '${dir.path}/decisions.jsonl',
    ).open(mode: FileMode.append);
    try {
      await file.lock(FileLock.exclusive);
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
  }
}
