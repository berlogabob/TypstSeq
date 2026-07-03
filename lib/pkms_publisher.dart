import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:typst_flutter/typst_flutter.dart';

import 'models.dart';
import 'pkms_registry.dart';
import 'scanner.dart';

Future<void> exportPkmsCollection({
  required Directory root,
  required VaultIndex index,
  required PkmsFileRegistry files,
  required PkmsCollectionEntry collection,
  required File output,
}) async {
  final byId = <String, NoteRef>{for (final note in index.notes) note.id: note};
  final notes = collection.noteIds.map((id) {
    final note = byId[id];
    if (note == null) throw StateError('Collection note is missing: $id');
    return note;
  }).toList();
  final virtual = <String, Uint8List>{};

  Future<void> add(String relative) async {
    if (!isSafeVaultPath(relative)) {
      throw StateError('Unsafe collection path: $relative');
    }
    final bytes = await File('${root.path}/$relative').readAsBytes();
    virtual[relative] = bytes;
    virtual['/$relative'] = bytes;
  }

  final helperFile = File('${root.path}/.tylog/tylog.typ');
  final helper = Uint8List.fromList(
    utf8.encode(
      await helperFile.exists()
          ? await helperFile.readAsString()
          : tylogHelperSource,
    ),
  );
  virtual['.tylog/tylog.typ'] = helper;
  virtual['/.tylog/tylog.typ'] = helper;
  for (final note in notes) {
    await add(note.path);
    for (final id in note.fileRefs) {
      final file = files.files[id];
      if (file != null) await add(file.path);
    }
  }
  final bibliography = collection.bibliographyPath;
  if (bibliography != null && bibliography.isNotEmpty) await add(bibliography);

  final source = StringBuffer()
    ..writeln('#heading(level: 1, ${_typstString(collection.title)})')
    ..writeln();
  for (final note in notes) {
    source.writeln('#include "/${_escape(note.path)}"');
    source.writeln('#pagebreak()');
  }
  if (bibliography != null && bibliography.isNotEmpty) {
    source.writeln('#bibliography("/${_escape(bibliography)}")');
  }

  final compiler = await TypstCompiler.create();
  try {
    final document = await compiler.compile(
      source: source.toString(),
      files: FileSource.bytes(virtual),
    );
    try {
      await output.parent.create(recursive: true);
      final tmp = File('${output.path}.tmp');
      await tmp.writeAsBytes(await document.exportPdf(), flush: true);
      if (await output.exists()) await output.delete();
      await tmp.rename(output.path);
    } finally {
      document.dispose();
    }
  } finally {
    compiler.dispose();
  }
}

String _escape(String value) =>
    value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

String _typstString(String value) => '"${_escape(value)}"';
