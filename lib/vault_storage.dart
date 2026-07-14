import 'dart:async';

import 'package:flutter/services.dart';
import 'package:tylog_core/storage.dart';

export 'package:tylog_core/storage.dart'
    show
        LocalVaultStorage,
        VaultStorage,
        VaultStorageEntry,
        validateVaultPath,
        writeFileAtomic;

class AndroidTreeSelection {
  const AndroidTreeSelection({required this.uri, required this.name});

  final String uri;
  final String name;
}

class AndroidTreeVaultStorage extends VaultStorage {
  AndroidTreeVaultStorage({required this.uri, required this.name});

  static const channel = MethodChannel('org.tylog.tylog/saf');

  // ponytail: Dart-side watchdog only; the native single-thread executor in
  // SafBridge stays wedged until app restart. Per-call native watchdogs if
  // a stalled DocumentsProvider recurs in practice.
  static Duration safCallTimeout = const Duration(seconds: 120);

  static Future<T> invoke<T>(Future<T> call, String op) async {
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

  Future<bool> hasAccess() async =>
      await channel.invokeMethod<bool>('hasAccess', args()) ?? false;

  Future<void> persistAccess() =>
      channel.invokeMethod<void>('persistAccess', args());

  static Future<AndroidTreeSelection?> pick() async {
    final result = await channel.invokeMapMethod<String, Object?>('pickTree');
    if (result == null) return null;
    return AndroidTreeSelection(
      uri: result['uri']! as String,
      name: result['name']! as String,
    );
  }

  Map<String, Object?> args([Map<String, Object?> values = const {}]) => {
    'uri': uri,
    ...values,
  };

  @override
  Future<bool> exists(String path) async =>
      await invoke<bool?>(
        channel.invokeMethod<bool>('exists', args({'path': path})),
        'exists',
      ) ??
      false;

  @override
  Future<void> createDirectory(String path) => invoke(
    channel.invokeMethod<void>('createDirectory', args({'path': path})),
    'createDirectory',
  );

  @override
  Future<List<VaultStorageEntry>> list({
    String path = '',
    bool recursive = false,
  }) async {
    final values =
        await invoke(
          channel.invokeListMethod<Map<Object?, Object?>>(
            'list',
            args({'path': path, 'recursive': recursive}),
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
    final value = await invoke(
      channel.invokeMapMethod<Object?, Object?>('stat', args({'path': path})),
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
      await invoke<Uint8List?>(
        channel.invokeMethod<Uint8List>('read', args({'path': path})),
        'read',
      ) ??
      Uint8List(0);

  @override
  Future<void> writeBytes(String path, List<int> bytes) => invoke(
    channel.invokeMethod<void>(
      'write',
      args({'path': path, 'bytes': Uint8List.fromList(bytes)}),
    ),
    'write',
  );

  @override
  Future<void> delete(String path) => invoke(
    channel.invokeMethod<void>('delete', args({'path': path})),
    'delete',
  );

  @override
  Future<String> hash(String path) async => (await invoke<String?>(
    channel.invokeMethod<String>('hash', args({'path': path})),
    'hash',
  ))!;
}
