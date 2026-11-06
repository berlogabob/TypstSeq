import 'dart:async';
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

/// Reject invalid UTF-8 and revision envelopes before they replace note text.
void guardNoteWrite(String path, List<int> bytes) {
  if (!path.endsWith('.typ') ||
      path.startsWith('_system/') ||
      path.startsWith('_index/') ||
      path.startsWith('.tylog/')) {
    return;
  }
  String text;
  try {
    text = utf8.decode(bytes);
  } on FormatException {
    stderr.writeln('Refusing invalid UTF-8 at note path: $path');
    rethrow;
  }
  if (!text.trimLeft().startsWith('{')) return;
  Object? value;
  try {
    value = jsonDecode(text);
  } on FormatException {
    return;
  }
  if (value is Map &&
      value['revision'] is Map &&
      value['revision']['id'] is String &&
      value['node'] is Map &&
      value['node']['content'] is String) {
    stderr.writeln('Refusing revision envelope at note path: $path');
    throw FormatException('Refusing revision envelope at note path: $path');
  }
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
  Future<void> appendBytes(String path, List<int> bytes) async {
    final existing = await exists(path) ? await readBytes(path) : <int>[];
    await writeBytes(path, [...existing, ...bytes]);
  }

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
  static final _appends = <String, Future<void>>{};

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
    guardNoteWrite(path, bytes);
    final marker = await markIndexDirty(path);
    await writeFileAtomic(File(_path(path)), bytes);
    await commitIndexWrite(marker, path);
  }

  @override
  Future<void> appendBytes(String path, List<int> bytes) async {
    final target = _path(path);
    final previous = _appends[target];
    final done = Completer<void>();
    _appends[target] = done.future;
    try {
      if (previous != null) await previous;
      final file = File(target);
      if (path.endsWith('.typ')) {
        final existing = await file.exists()
            ? await file.readAsBytes()
            : <int>[];
        guardNoteWrite(path, [...existing, ...bytes]);
      }
      final marker = await markIndexDirty(path);
      await file.parent.create(recursive: true);
      final sink = file.openWrite(mode: FileMode.append);
      try {
        sink.add(bytes);
        await sink.flush();
      } finally {
        await sink.close();
      }
      await commitIndexWrite(marker, path);
    } finally {
      done.complete();
      if (identical(_appends[target], done.future)) _appends.remove(target);
    }
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

class ReadOnlyVaultStorage extends VaultStorage {
  ReadOnlyVaultStorage(this.inner);
  final VaultStorage inner;

  @override
  Object get syncIdentity => inner.syncIdentity;
  @override
  Future<bool> exists(String path) => inner.exists(path);
  @override
  Future<bool> existsNow(String path) => inner.existsNow(path);
  @override
  Future<List<VaultStorageEntry>> list({
    String path = '',
    bool recursive = false,
  }) => inner.list(path: path, recursive: recursive);
  @override
  Future<List<VaultStorageEntry>> listNow({String path = ''}) =>
      inner.listNow(path: path);
  @override
  Future<VaultStorageEntry?> stat(String path) => inner.stat(path);
  @override
  Future<Uint8List> readBytes(String path) => inner.readBytes(path);
  @override
  Future<Uint8List> readBytesNow(String path) => inner.readBytesNow(path);
  @override
  Stream<List<int>>? openRead(String path, [int? start, int? end]) =>
      inner.openRead(path, start, end);
  @override
  Future<String> hash(String path) => inner.hash(path);
  @override
  Future<void> createDirectory(String path) async =>
      throw UnsupportedError('Read-only storage');
  @override
  Future<void> writeBytes(String path, List<int> bytes) async =>
      throw UnsupportedError('Read-only storage');
  @override
  Future<void> appendBytes(String path, List<int> bytes) async =>
      throw UnsupportedError('Read-only storage');
  @override
  Future<void> delete(String path) async =>
      throw UnsupportedError('Read-only storage');
  @override
  Future<void> deleteEmptyDirectory(String path) async =>
      throw UnsupportedError('Read-only storage');
}

class CompositeVaultStorage extends VaultStorage {
  CompositeVaultStorage(
    this.main,
    Map<String, VaultStorage> mounts, {
    Set<String> writableMounts = const {},
  }) : mounts = Map.of(mounts),
       writableMounts = Set.of(writableMounts) {
    for (final id in mounts.keys) {
      if (!RegExp(r'^[a-z0-9][a-z0-9-]{0,40}$').hasMatch(id)) {
        throw ArgumentError.value(id, 'mounts', 'Invalid mount id');
      }
    }
  }
  final VaultStorage main;
  final Map<String, VaultStorage> mounts;
  final Set<String> writableMounts;

  void replaceMounts(
    Map<String, VaultStorage> next, {
    Set<String> writableMounts = const {},
  }) {
    mounts
      ..clear()
      ..addAll(CompositeVaultStorage(main, next).mounts);
    this.writableMounts
      ..clear()
      ..addAll(writableMounts);
  }

  @override
  Object get syncIdentity => main.syncIdentity;

  (VaultStorage, String)? _mount(String path) {
    final parts = path.split('/');
    if (parts.length < 2 || parts[0] != 'ext') return null;
    final storage = mounts[parts[1]];
    return storage == null ? null : (storage, parts.skip(2).join('/'));
  }

  VaultStorageEntry _prefix(String id, VaultStorageEntry entry) =>
      VaultStorageEntry(
        path: 'ext/$id/${entry.path}',
        isDirectory: entry.isDirectory,
        size: entry.size,
        modified: entry.modified,
      );
  bool _virtual(String path) =>
      mounts.isNotEmpty &&
      (path == 'ext' || (path.startsWith('ext/') && _mount(path)?.$2 == ''));

  @override
  Future<bool> exists(String path) => _virtual(path)
      ? Future.value(true)
      : (_mount(path)?.$1 ?? main).exists(_mount(path)?.$2 ?? path);
  @override
  Future<bool> existsNow(String path) => _virtual(path)
      ? Future.value(true)
      : (_mount(path)?.$1 ?? main).existsNow(_mount(path)?.$2 ?? path);
  @override
  Future<VaultStorageEntry?> stat(String path) async {
    if (_virtual(path)) return VaultStorageEntry(path: path, isDirectory: true);
    final mount = _mount(path);
    final entry = await (mount?.$1 ?? main).stat(mount?.$2 ?? path);
    return entry == null || mount == null
        ? entry
        : _prefix(path.split('/')[1], entry);
  }

  @override
  Future<List<VaultStorageEntry>> list({
    String path = '',
    bool recursive = false,
  }) async {
    final mount = _mount(path);
    if (mount != null) {
      return [
        for (final entry in await mount.$1.list(
          path: mount.$2,
          recursive: recursive,
        ))
          _prefix(path.split('/')[1], entry),
      ];
    }
    final entries = await main.list(path: path, recursive: recursive);
    if (mounts.isEmpty || (path != '' && path != 'ext')) return entries;
    final result = entries
        .where((entry) => !(entry.path == 'ext' || _mount(entry.path) != null))
        .toList();
    if (path == '') {
      result.add(const VaultStorageEntry(path: 'ext', isDirectory: true));
    }
    if (path == 'ext' || recursive) {
      for (final id in mounts.keys) {
        result.add(VaultStorageEntry(path: 'ext/$id', isDirectory: true));
        if (recursive) {
          result.addAll([
            for (final entry in await mounts[id]!.list(recursive: true))
              _prefix(id, entry),
          ]);
        }
      }
    }
    return result;
  }

  @override
  Future<Uint8List> readBytes(String path) =>
      (_mount(path)?.$1 ?? main).readBytes(_mount(path)?.$2 ?? path);
  @override
  Future<Uint8List> readBytesNow(String path) =>
      (_mount(path)?.$1 ?? main).readBytesNow(_mount(path)?.$2 ?? path);
  @override
  Future<String> readText(String path) =>
      (_mount(path)?.$1 ?? main).readText(_mount(path)?.$2 ?? path);
  @override
  Future<void> writeText(String path, String value) async =>
      _writable(path).$1.writeText(_writable(path).$2, value);
  @override
  Stream<List<int>>? openRead(String path, [int? start, int? end]) =>
      (_mount(path)?.$1 ?? main).openRead(_mount(path)?.$2 ?? path, start, end);
  @override
  Future<String> hash(String path) =>
      (_mount(path)?.$1 ?? main).hash(_mount(path)?.$2 ?? path);
  @override
  Future<void> createDirectory(String path) async =>
      _writable(path).$1.createDirectory(_writable(path).$2);
  @override
  Future<void> writeBytes(String path, List<int> bytes) async =>
      _writable(path).$1.writeBytes(_writable(path).$2, bytes);
  @override
  Future<void> appendBytes(String path, List<int> bytes) async =>
      _writable(path).$1.appendBytes(_writable(path).$2, bytes);
  @override
  Future<void> delete(String path) async =>
      _writable(path).$1.delete(_writable(path).$2);
  @override
  Future<void> deleteEmptyDirectory(String path) async =>
      _writable(path).$1.deleteEmptyDirectory(_writable(path).$2);

  (VaultStorage, String) _writable(String path) {
    if (path == 'ext' || path.startsWith('ext/')) {
      final mount = _mount(path);
      if (mount != null &&
          mount.$2.isNotEmpty &&
          writableMounts.contains(path.split('/')[1])) {
        return mount;
      }
      throw UnsupportedError('Read-only extension storage');
    }
    return (main, path);
  }
}
