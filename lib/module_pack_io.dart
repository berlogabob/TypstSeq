import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:tylog_core/tylog_core.dart';

export 'package:tylog_core/tylog_core.dart'
    show ModulePack, installModule, moduleRecordPath, uninstallModule;

/// Reads and verifies a `.tylogpack` zip. Throws [FormatException].
Future<ModulePack> readModulePack(File file) async {
  final Archive zip;
  try {
    zip = ZipDecoder().decodeBytes(await file.readAsBytes());
  } catch (_) {
    throw const FormatException('Not a valid .tylogpack archive');
  }
  return ModulePack.parse({
    for (final entry in zip.files)
      if (entry.isFile) entry.name: Uint8List.fromList(entry.content),
  });
}
