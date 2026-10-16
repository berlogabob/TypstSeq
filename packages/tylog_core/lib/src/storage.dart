import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

final _tempRandom = Random();

Future<void> writeFileAtomic(File file, List<int> bytes) async {
  await file.parent.create(recursive: true);
  // Short sibling name: `<name>.<micros>.tmp` overflowed the 255-byte name
  // limit for long Cyrillic article titles (errno 36).
  final temporary = File(
    '${file.parent.path}/.tylog-${DateTime.now().microsecondsSinceEpoch}'
    '${_tempRandom.nextInt(1000).toString().padLeft(3, '0')}.tmp',
  );
  await temporary.writeAsBytes(bytes, flush: true);
  await temporary.rename(file.path);
}

class VaultStorageEntry {
  const VaultStorageEntry({
    required this.path,
    required this.isDirectory,
    this.size,
    this.modified,
  });

  final String path;
  final bool isDirectory;
  final int? size;
  final DateTime? modified;
}

const indexDirtyPath = '.tylog/index_dirty';
final _writeMarkerRandom = Random.secure();

abstract class VaultStorage {
  Object get syncIdentity => this;

  /// Persist before writing: unique markers survive crashes and a scanner
  /// only removes writes committed before its scan started.
  Future<String?> markIndexDirty(String path) async {
    if (!path.endsWith('.typ') ||
        path.startsWith('.tylog/') ||
        path.startsWith('_index/') ||
        path.startsWith('_system/')) {
      return null;
    }
    final token =
        '${DateTime.now().microsecondsSinceEpoch}-${_writeMarkerRandom.nextInt(1 << 32)}';
    final marker = '$indexDirtyPath/$token.json';
    await writeText(marker, jsonEncode({'path': path}));
    return marker;
  }

  Future<void> commitIndexWrite(String? marker, String path) async {
    if (marker == null) return;
    await writeText(
      marker,
      jsonEncode({
        'path': path,
        'committedAt': DateTime.now().microsecondsSinceEpoch,
      }),
    );
  }

  Future<bool> exists(String path);
  Future<void> createDirectory(String path);
  Future<List<VaultStorageEntry>> list({
    String path = '',
    bool recursive = false,
  });
  Future<VaultStorageEntry?> stat(String path);
  Future<Uint8List> readBytes(String path);

  /// A user-waiting read (audio playback or small settings files). Providers
  /// with a shared read queue override this to skip it; others just read.
  Future<Uint8List> readBytesNow(String path) => readBytes(path);

  /// [exists] for a user-waiting check; see [readBytesNow].
  Future<bool> existsNow(String path) => exists(path);

  /// Non-recursive [list] for a user-waiting check; see [readBytesNow].
  Future<List<VaultStorageEntry>> listNow({String path = ''}) =>
      list(path: path);

  /// Null when this provider only supports whole-file reads.
  Stream<List<int>>? openRead(String path, [int? start, int? end]) => null;
  Future<void> writeBytes(String path, List<int> bytes);
  Future<void> delete(String path);

  /// Removes an empty directory, leaving files and non-empty directories alone.
  Future<void> deleteEmptyDirectory(String path) async {
    if ((await stat(path))?.isDirectory == true &&
        (await list(path: path)).isEmpty) {
      await delete(path);
    }
  }

  Future<String> hash(String path);

  Future<String> readText(String path) async =>
      utf8.decode(await readBytes(path));
  Future<void> writeText(String path, String value) =>
      writeBytes(path, utf8.encode(value));
}

List<VaultStorageEntry> _listSync(String dir, String root) => [
  for (final entity in Directory(
    dir,
  ).listSync(recursive: true, followLinks: false))
    if (entity.statSync() case final info
        when info.type != FileSystemEntityType.notFound)
      VaultStorageEntry(
        path: entity.absolute.path
            .substring(root.length + 1)
            .replaceAll(Platform.pathSeparator, '/'),
        isDirectory: entity is Directory,
        size: entity is File ? info.size : null,
        modified: info.modified,
      ),
];

class LocalVaultStorage extends VaultStorage {
  LocalVaultStorage(Directory root) : _root = root.absolute;

  final Directory _root;

  @override
  String get syncIdentity => _root.path;

  String _path(String path) {
    final relative = validateVaultPath(path, allowEmpty: true);
    return relative.isEmpty
        ? _root.path
        : '${_root.path}${Platform.pathSeparator}${relative.replaceAll('/', Platform.pathSeparator)}';
  }

  @override
  Future<bool> exists(String path) => FileSystemEntity.type(
    _path(path),
  ).then((type) => type != FileSystemEntityType.notFound);

  @override
  Future<void> createDirectory(String path) =>
      Directory(_path(path)).create(recursive: true);

  @override
  Future<List<VaultStorageEntry>> list({
    String path = '',
    bool recursive = false,
  }) async {
    final directory = Directory(_path(path));
    if (!await directory.exists()) return [];
    if (recursive) {
      // One awaited stat per entry cost 14 s for a 19.5k-file vault on a
      // phone; a sync walk off the calling isolate takes well under a second.
      final dir = directory.path;
      final root = _root.path;
      return Isolate.run(() => _listSync(dir, root));
    }
    final out = <VaultStorageEntry>[];
    await for (final entity in directory.list(
      recursive: recursive,
      followLinks: false,
    )) {
      final relative = entity.absolute.path
          .substring(_root.path.length + 1)
          .replaceAll(Platform.pathSeparator, '/');
      final info = await entity.stat();
      out.add(
        VaultStorageEntry(
          path: relative,
          isDirectory: entity is Directory,
          size: entity is File ? info.size : null,
          modified: info.modified,
        ),
      );
    }
    return out;
  }

  @override
  Future<VaultStorageEntry?> stat(String path) async {
    final type = await FileSystemEntity.type(_path(path));
    if (type == FileSystemEntityType.notFound) return null;
    final info = await FileStat.stat(_path(path));
    return VaultStorageEntry(
      path: path,
      isDirectory: type == FileSystemEntityType.directory,
      size: type == FileSystemEntityType.file ? info.size : null,
      modified: info.modified,
    );
  }

  @override
  Stream<List<int>> openRead(String path, [int? start, int? end]) =>
      File(_path(path)).openRead(start, end);

  @override
  Future<Uint8List> readBytes(String path) => File(_path(path)).readAsBytes();

  @override
  Future<void> writeBytes(String path, List<int> bytes) async {
    final marker = await markIndexDirty(path);
    await writeFileAtomic(File(_path(path)), bytes);
    await commitIndexWrite(marker, path);
  }

  @override
  Future<void> delete(String path) async {
    final target = _path(path);
    final type = await FileSystemEntity.type(target);
    if (type == FileSystemEntityType.directory) {
      await Directory(target).delete(recursive: true);
    } else if (type != FileSystemEntityType.notFound) {
      await File(target).delete();
    }
  }

  @override
  Future<void> deleteEmptyDirectory(String path) async {
    final directory = Directory(_path(path));
    if (await directory.exists() && (await list(path: path)).isEmpty) {
      await directory.delete();
    }
  }

  @override
  Future<String> hash(String path) async =>
      (await sha256.bind(File(_path(path)).openRead()).first).toString();
}

String validateVaultPath(String path, {bool allowEmpty = false}) {
  if (path.isEmpty && allowEmpty) return path;
  if (path.isEmpty ||
      path.startsWith('/') ||
      path.startsWith('\\') ||
      path.contains('\\') ||
      path.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f) ||
      path
          .split('/')
          .any((part) => part.isEmpty || part == '.' || part == '..')) {
    throw ArgumentError.value(
      path,
      'path',
      'must be a safe vault-relative path',
    );
  }
  return path;
}
