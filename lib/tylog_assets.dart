import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class TylogAssets {
  TylogAssets._(this._bytes);

  static Future<TylogAssets>? _cached;

  final Map<String, Uint8List> _bytes;

  /// Read from the bundled typst.toml, so the package version has exactly
  /// one source of truth and a version bump cannot ship half-applied.
  String get packageVersion {
    final toml = text('typst/tylog/typst.toml');
    final match = RegExp(
      r'^version\s*=\s*"(\d+\.\d+\.\d+)"',
      multiLine: true,
    ).firstMatch(toml);
    if (match == null) {
      throw StateError('typst/tylog/typst.toml has no version field');
    }
    return match[1]!;
  }

  static Future<TylogAssets> load() => _cached ??= _load();

  static Future<TylogAssets> _load() async {
    WidgetsFlutterBinding.ensureInitialized();
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final paths =
        manifest
            .listAssets()
            .where((path) => path.startsWith('typst/'))
            .toList()
          ..sort();
    final bytes = <String, Uint8List>{};
    for (final path in paths) {
      final data = await rootBundle.load(path);
      bytes[path] = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
    }
    return TylogAssets._(bytes);
  }

  String text(String path) => utf8.decode(_bytes[path]!);

  Map<String, Uint8List> get managedVaultFiles {
    final files = <String, Uint8List>{
      '_system/tylog.typ': _bytes['typst/vault/tylog.typ']!,
      '_system/theme.typ': _bytes['typst/vault/theme.typ']!,
      '_system/export.typ': _bytes['typst/vault/export.typ']!,
    };
    for (final entry in _bytes.entries) {
      if (!entry.key.startsWith('typst/tylog/')) continue;
      final relative = entry.key.substring('typst/tylog/'.length);
      files['_system/packages/tylog/$packageVersion/$relative'] = entry.value;
    }
    return files;
  }

  Map<String, Uint8List> get compilerFiles {
    final files = <String, Uint8List>{};
    for (final entry in managedVaultFiles.entries) {
      files[entry.key] = entry.value;
      files['/${entry.key}'] = entry.value;
    }
    return files;
  }
}
