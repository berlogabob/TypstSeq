import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

/// Write via a unique sibling `.tmp` file then rename. POSIX rename replaces
/// the target atomically, so a crash never leaves the file missing and
/// concurrent writers never share a temp file.
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
  String get location;
  String get displayName;
  bool get materializedFilesAreTemporary;

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
  Future<void> importFile(String path, File source);
  Future<File> materialize(String path);
  Future<void> open(String path);

  Future<String> readText(String path) async =>
      utf8.decode(await readBytes(path));
  Future<void> writeText(String path, String value) =>
      writeBytes(path, utf8.encode(value));
}

class LocalVaultStorage extends VaultStorage {
  LocalVaultStorage(this.root);

  final Directory root;

  @override
  String get location => root.absolute.path;

  @override
  String get displayName =>
      root.path.replaceAll(RegExp(r'[/\\]+$'), '').split(RegExp(r'[/\\]')).last;

  @override
  bool get materializedFilesAreTemporary => false;

  String _path(String path) => path.isEmpty
      ? root.path
      : '${root.path}${Platform.pathSeparator}${path.replaceAll('/', Platform.pathSeparator)}';

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
          .substring(root.absolute.path.length + 1)
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
    final type = await FileSystemEntity.type(_path(path));
    if (type == FileSystemEntityType.directory) {
      await Directory(_path(path)).delete(recursive: true);
    } else if (type != FileSystemEntityType.notFound) {
      await File(_path(path)).delete();
    }
  }

  @override
  Future<String> hash(String path) async =>
      (await sha256.bind(File(_path(path)).openRead()).first).toString();

  @override
  Future<void> importFile(String path, File source) async =>
      writeBytes(path, await source.readAsBytes());

  @override
  Future<File> materialize(String path) async => File(_path(path));

  @override
  Future<void> open(String path) async {
    throw UnsupportedError(
      'Local files are opened by the platform file opener',
    );
  }
}

class AndroidTreeSelection {
  const AndroidTreeSelection({required this.uri, required this.name});

  final String uri;
  final String name;
}

class AndroidTreeVaultStorage extends VaultStorage {
  AndroidTreeVaultStorage({required this.uri, required this.name});

  static const _channel = MethodChannel('org.tylog.tylog/saf');

  // ponytail: Dart-side watchdog only; the native single-thread executor in
  // SafBridge stays wedged until app restart. Per-call native watchdogs if
  // a stalled DocumentsProvider recurs in practice.
  static Duration safCallTimeout = const Duration(seconds: 120);

  static Future<T> _invoke<T>(Future<T> call, String op) async {
    try {
      return await call.timeout(safCallTimeout);
    } on TimeoutException {
      throw PlatformException(
        code: 'saf_timeout',
        message: 'Folder provider did not respond: $op',
      );
    }
  }

  final String uri;
  final String name;

  static Future<AndroidTreeSelection?> pick() async {
    // No watchdog: the system folder picker waits on the user.
    final result = await _channel.invokeMapMethod<String, Object?>('pickTree');
    if (result == null) return null;
    return AndroidTreeSelection(
      uri: result['uri']! as String,
      name: result['name']! as String,
    );
  }

  Map<String, Object?> _args([Map<String, Object?> values = const {}]) => {
    'uri': uri,
    ...values,
  };

  @override
  String get location => uri;

  @override
  String get displayName => name;

  @override
  bool get materializedFilesAreTemporary => true;

  @override
  Future<bool> exists(String path) async =>
      await _invoke<bool?>(
        _channel.invokeMethod<bool>('exists', _args({'path': path})),
        'exists',
      ) ??
      false;

  @override
  Future<void> createDirectory(String path) => _invoke(
    _channel.invokeMethod<void>('createDirectory', _args({'path': path})),
    'createDirectory',
  );

  @override
  Future<List<VaultStorageEntry>> list({
    String path = '',
    bool recursive = false,
  }) async {
    final values =
        await _invoke(
          _channel.invokeListMethod<Map<Object?, Object?>>(
            'list',
            _args({'path': path, 'recursive': recursive}),
          ),
          'list',
        ) ??
        const [];
    return values
        .map(
          (value) => VaultStorageEntry(
            path: value['path']! as String,
            isDirectory: value['isDirectory']! as bool,
            size: value['size'] as int?,
            modified: value['modified'] == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(
                    value['modified']! as int,
                  ),
          ),
        )
        .toList();
  }

  @override
  Future<VaultStorageEntry?> stat(String path) async {
    final value = await _invoke(
      _channel.invokeMapMethod<Object?, Object?>('stat', _args({'path': path})),
      'stat',
    );
    if (value == null) return null;
    return VaultStorageEntry(
      path: path,
      isDirectory: value['isDirectory']! as bool,
      size: value['size'] as int?,
      modified: value['modified'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(value['modified']! as int),
    );
  }

  @override
  Future<Uint8List> readBytes(String path) async =>
      await _invoke<Uint8List?>(
        _channel.invokeMethod<Uint8List>('read', _args({'path': path})),
        'read',
      ) ??
      Uint8List(0);

  @override
  Future<void> writeBytes(String path, List<int> bytes) => _invoke(
    _channel.invokeMethod<void>(
      'write',
      _args({'path': path, 'bytes': Uint8List.fromList(bytes)}),
    ),
    'write',
  );

  @override
  Future<void> delete(String path) => _invoke(
    _channel.invokeMethod<void>('delete', _args({'path': path})),
    'delete',
  );

  @override
  Future<String> hash(String path) async =>
      (await _invoke<String?>(
        _channel.invokeMethod<String>('hash', _args({'path': path})),
        'hash',
      ))!;

  @override
  Future<void> importFile(String path, File source) => _invoke(
    _channel.invokeMethod<void>(
      'import',
      _args({'path': path, 'source': source.path}),
    ),
    'import',
  );

  @override
  Future<File> materialize(String path) async => File(
    (await _invoke(
      _channel.invokeMethod<String>('materialize', _args({'path': path})),
      'materialize',
    ))!,
  );

  @override
  Future<void> open(String path) => _invoke(
    _channel.invokeMethod<void>('open', _args({'path': path})),
    'open',
  );
}
