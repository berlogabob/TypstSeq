import 'dart:typed_data';

import 'package:tylog_core/scanner.dart';
import 'package:typst_flutter/typst_flutter.dart';

class FlutterTypstInspector
    implements TypstInspector, RecoverableInspector, BaseFilesInspector {
  FlutterTypstInspector._(this._compiler);

  TypstCompiler _compiler;
  Map<String, Uint8List>? _baseFiles;

  static Future<FlutterTypstInspector> create() async =>
      FlutterTypstInspector._(await TypstCompiler.create());

  @override
  Future<void> setBaseFiles(Map<String, Uint8List> files) async {
    _baseFiles = files;
    await _compiler.setBaseFiles(files);
  }

  /// Rebuilds the native engine after a compile has wedged it. The old engine
  /// keeps its (leaked) write lock, so we drop it and swap in a fresh one;
  /// `create()` only allocates the engine — `RustLib.init()` already ran — so
  /// this is cheap enough to do mid-scan. The fresh engine starts with an
  /// empty VFS, so the scan's base files are re-installed before it serves
  /// its next query.
  @override
  Future<void> recover() async {
    final old = _compiler;
    _compiler = await TypstCompiler.create();
    old.dispose();
    final base = _baseFiles;
    if (base != null) await _compiler.setBaseFiles(base);
  }

  @override
  Future<List<TypstMetadataRecord>> inspect(TypstDocumentInput input) async {
    final document = await _compiler.compile(
      source: input.source,
      files: input.files,
    );
    try {
      return decodeTypstMetadataRecords(
        await _compiler.query(document: document, selector: 'metadata'),
      );
    } finally {
      document.dispose();
    }
  }

  void dispose() => _compiler.dispose();
}
