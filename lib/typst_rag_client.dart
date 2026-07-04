import 'dart:convert';
import 'dart:io';

class TypstDocResult {
  const TypstDocResult({
    required this.section,
    required this.sourcePath,
    required this.url,
    required this.version,
    required this.excerpt,
  });

  final String section;
  final String sourcePath;
  final String url;
  final String version;
  final String excerpt;
}

class TypstRagClient {
  Directory? locate() {
    final configured = Platform.environment['TYPST_RAG_DIR'];
    final candidates = [
      if (configured != null) Directory(configured),
      Directory('${Directory.current.parent.path}/TypstRAG'),
    ];
    return candidates
        .where((dir) => File('${dir.path}/pyproject.toml').existsSync())
        .firstOrNull;
  }

  Future<List<TypstDocResult>> search(String query) async {
    final root = locate();
    if (root == null) {
      throw StateError('Set TYPST_RAG_DIR to the local TypstRAG checkout.');
    }
    final result = await Process.run('uv', [
      'run',
      'typst-rag',
      'search',
      query,
      '--limit',
      '5',
      '--json',
    ], workingDirectory: root.path).timeout(const Duration(seconds: 20));
    if (result.exitCode != 0) throw StateError(result.stderr.toString().trim());
    final values = (jsonDecode(result.stdout as String) as List).cast<Map>();
    return values.map((value) {
      final json = value.cast<String, Object?>();
      return TypstDocResult(
        section: json['section'].toString(),
        sourcePath: json['source_path'].toString(),
        url: json['url'].toString(),
        version: json['version'].toString(),
        excerpt: json['excerpt'].toString(),
      );
    }).toList();
  }
}

String? deterministicTypstFix(String error, String source) {
  final match = RegExp(r'unknown variable:\s*([^\s]+)').firstMatch(error);
  if (match == null) return null;
  final word = match.group(1)!;
  if (source.contains('#$word')) {
    return 'Typst treats #$word as code. Use $word for plain text, '
        r'\#'
        '$word for a literal hashtag, or #pkm.tag("$word") for a PKMS tag.';
  }
  return null;
}
