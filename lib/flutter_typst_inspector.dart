import 'package:tylog_core/scanner.dart';
import 'package:typst_flutter/typst_flutter.dart';

class FlutterTypstInspector
    implements TypstInspector, RecoverableInspector {
  FlutterTypstInspector._(this._compiler);

  TypstCompiler _compiler;

  static Future<FlutterTypstInspector> create() async =>
      FlutterTypstInspector._(await TypstCompiler.create());

  /// Rebuilds the native engine after a compile has wedged it. The old engine
  /// keeps its (leaked) write lock, so we drop it and swap in a fresh one;
  /// `create()` only allocates the engine — `RustLib.init()` already ran — so
  /// this is cheap enough to do mid-scan.
  @override
  Future<void> recover() async {
    final old = _compiler;
    _compiler = await TypstCompiler.create();
    old.dispose();
  }

  @override
  Future<List<TypstMetadataRecord>> inspect(TypstDocumentInput input) async {
    final document = await _compiler.compile(
      source: input.source,
      files: FileSource.bytes(input.files),
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
