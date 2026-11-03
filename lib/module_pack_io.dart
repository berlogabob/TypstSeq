import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:tylog_core/tylog_core.dart';

export 'package:tylog_core/tylog_core.dart'
    show ModulePack, installModule, moduleRecordPath, uninstallModule;

/// Reads and verifies a `.tylogpack` zip. Throws [FormatException].
Future<ModulePack> readModulePack(File file) async {
  return readModulePackBytes(await file.readAsBytes());
}

ModulePack readModulePackBytes(List<int> bytes) {
  final Archive zip;
  try {
    zip = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw const FormatException('Not a valid .tylogpack archive');
  }
  return ModulePack.parse({
    for (final entry in zip.files)
      if (entry.isFile) entry.name: Uint8List.fromList(entry.content),
  });
}
