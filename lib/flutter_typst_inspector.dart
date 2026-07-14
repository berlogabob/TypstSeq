import 'package:tylog_core/scanner.dart';
import 'package:typst_flutter/typst_flutter.dart';

class FlutterTypstInspector implements TypstInspector {
  FlutterTypstInspector._(this._compiler);

  final TypstCompiler _compiler;

  static Future<FlutterTypstInspector> create() async =>
      FlutterTypstInspector._(await TypstCompiler.create());

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
