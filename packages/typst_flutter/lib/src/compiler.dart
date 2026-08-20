import 'dart:ffi';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:typst_flutter/src/document.dart';
import 'package:typst_flutter/src/exceptions.dart';
import 'package:typst_flutter/src/rust/api/typst.dart' as api;
import 'package:typst_flutter/src/rust/frb_generated.dart';

/// The Typst compiler bridge.
///
/// Create a single instance per app or per compiler configuration and reuse
/// it — construction is lightweight; the heavy native library is loaded once
/// when [RustLib.init] is called.
///
/// ```dart
/// final compiler = await TypstCompiler.create();
///
/// // Compile to a lightweight document handle
/// final doc = await compiler.compile(source: myMarkup);
///
/// // Lazily render pages or export PDF
/// final pdfBytes = await doc.exportPdf();
/// final result = await doc.renderRaster(pageIndex: 0);
/// ```
class TypstCompiler implements Finalizable {
  TypstCompiler._({required api.TypstEngine engine}) : _engine = engine;

  /// The underlying stateful Rust engine.
  final api.TypstEngine _engine;

  /// Releases the native resources associated with this compiler.
  ///
  /// After calling this, the compiler instance is no longer usable and any
  /// further calls to its methods will throw an error.
  void dispose() {
    _engine.dispose();
  }

  /// Creates a [TypstCompiler] and initialises the native bridge.
  ///
  /// The compiler uses the bundled core fonts (`Libertinus Serif`,
  /// `DejaVu Sans Mono`, and `NewCM Math`).
  ///
  /// This is safe to call multiple times; the native library is only
  /// initialised once.
  // ponytail: no custom-font hook; the engine's addFonts() is still there if a
  // caller ever needs one.
  static Future<TypstCompiler> create() async {
    try {
      await RustLib.init();
      // flutter_rust_bridge throws a StateError if init() is called more than
      // once. We ignore this specific error to remain robust in tests.
      // ignore: avoid_catching_errors
    } on StateError catch (e) {
      if (!e.message.contains('twice')) rethrow;
    }

    return TypstCompiler._(engine: api.TypstEngine());
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  PlatformInt64? _dateTimeToSysTime(DateTime? date) {
    if (date == null) return null;
    return PlatformInt64Util.from((date.millisecondsSinceEpoch / 1000).round());
  }

  /// Compiles Typst [source] markup into a lightweight document handle.
  ///
  /// [files] maps virtual path (exactly the string used in markup, e.g.
  /// `logo.png` for `#image("logo.png")`) to raw file bytes.
  ///
  /// Returns a [TypstDocument] which can be used to query page dimensions,
  /// lazily render raster/SVG pages, or export the full document to PDF.
  Future<TypstDocument> compile({
    required String source,
    Map<String, Uint8List>? files,
    DateTime? date,
    Map<String, String>? inputs,
  }) async {
    final virtualFiles = <api.VirtualFile>[
      for (final e in (files ?? const {}).entries)
        api.VirtualFile(path: e.key, bytes: e.value),
    ];
    try {
      final inner = await _engine.compile(
        markup: source,
        files: virtualFiles,
        sysTime: _dateTimeToSysTime(date),
        inputs: inputs,
      );
      return TypstDocument.fromInner(inner);
    } on api.TypstCompileError catch (e) {
      throw TypstCompileException(
        'Compilation failed',
        diagnostics: e.diagnostics,
      );
    } catch (e) {
      throw TypstCompileException('$e');
    }
  }

  /// Installs a persistent base layer of virtual files that survives
  /// [compile] calls (per-compile [compile] `files` shadow it). Send the
  /// scan-wide support set here once instead of re-serialising it across the
  /// FFI boundary on every compile; an empty map clears the layer.
  ///
  /// Streamed in bounded chunks: one message carrying a whole vault's assets
  /// is a single contiguous allocation of that size, which aborted the app
  /// on a memory-constrained Android device.
  Future<void> setBaseFiles(Map<String, Uint8List> files) async {
    const chunkBytes = 48 << 20;
    var batch = <api.VirtualFile>[];
    var batchSize = 0;
    var first = true;
    Future<void> flush({required bool last}) async {
      await _engine.addBaseFiles(files: batch, first: first, last: last);
      first = false;
      batch = [];
      batchSize = 0;
    }

    for (final e in files.entries) {
      batch.add(api.VirtualFile(path: e.key, bytes: e.value));
      batchSize += e.value.length;
      if (batchSize >= chunkBytes) await flush(last: false);
    }
    await flush(last: true); // Also clears the layer for an empty map.
  }

  /// Queries the compiled [document] using a Typst [selector] string.
  ///
  /// Returns a JSON string containing the queried elements (e.g. headings).
  Future<String> query({
    required TypstDocument document,
    required String selector,
  }) async => _engine.query(document: document.inner, selector: selector);
}
