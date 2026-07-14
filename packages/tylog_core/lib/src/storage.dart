import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

Future<void> writeFileAtomic(File file, List<int> bytes) async {
  await file.parent.create(recursive: true);
  final temporary = File(
    '${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
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

abstract class VaultStorage {
  Future<bool> exists(String path);
  Future<void> createDirectory(String path);
  Future<List<VaultStorageEntry>> list({
    String path = '',
    bool recursive = false,
  });
  Future<VaultStorageEntry?> stat(String path);
  Future<Uint8List> readBytes(String path);
  Future<void> writeBytes(String path, List<int> bytes);
  Future<void> delete(String path);
  Future<String> hash(String path);

  Future<String> readText(String path) async =>
      utf8.decode(await readBytes(path));
  Future<void> writeText(String path, String value) =>
      writeBytes(path, utf8.encode(value));
}

class LocalVaultStorage extends VaultStorage {
  LocalVaultStorage(Directory root) : _root = root.absolute;

  final Directory _root;

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
  Future<Uint8List> readBytes(String path) => File(_path(path)).readAsBytes();

  @override
  Future<void> writeBytes(String path, List<int> bytes) =>
      writeFileAtomic(File(_path(path)), bytes);

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
  Future<String> hash(String path) async =>
      (await sha256.bind(File(_path(path)).openRead()).first).toString();
}

String validateVaultPath(String path, {bool allowEmpty = false}) {
  if (path.isEmpty && allowEmpty) return path;
  if (path.isEmpty ||
      path.startsWith('/') ||
      path.startsWith('\\') ||
      path.contains('\\') ||
      path.split('/').any((part) => part.isEmpty || part == '..')) {
    throw ArgumentError.value(
      path,
      'path',
      'must be a safe vault-relative path',
    );
  }
  return path;
}
