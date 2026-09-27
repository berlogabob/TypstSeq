import 'dart:io';

import 'package:crypto/crypto.dart';

const kSemanticModelId = 'multilingual-e5-small@ccc66d3/O4';

class SemanticModelFile {
  const SemanticModelFile(this.name, this.bytes, this.sha256);

  final String name;
  final int bytes;
  final String sha256;
}

const kSemanticModelManifest = [
  SemanticModelFile(
    'model_O4.onnx',
    235052531,
    '4654c156f3e4171abc9c716cdb771bf9116455d15ac1aab364aeeede0e3205b0',
  ),
  SemanticModelFile(
    'tokenizer.json',
    17082730,
    '0b44a9d7b51c3c62626640cda0e2c2f70fdacdc25bbbd68038369d14ebdf4c39',
  ),
];

class SemanticModelStore {
  SemanticModelStore(
    this.root, {
    List<SemanticModelFile>? manifest,
    String? baseUrl,
  }) : manifest = manifest ?? kSemanticModelManifest,
       baseUrl = baseUrl ?? _base;

  final Directory root;
  final List<SemanticModelFile> manifest;
  final String baseUrl;
  static const _revision = 'ccc66d3bcd826f577e26b9a4072cc5fe3a7ad6a3';
  static const _base =
      'https://huggingface.co/intfloat/multilingual-e5-small/resolve/$_revision/onnx';
  static const _marker = 'verified';

  Future<({String model, String tokenizer})?> installed() async {
    if (!await File('${root.path}/$_marker').exists()) {
      return null;
    }
    for (final item in manifest) {
      final file = File('${root.path}/${item.name}');
      if (!await file.exists() || await file.length() != item.bytes) {
        return null;
      }
    }
    final model = manifest.firstWhere((item) => item.name == 'model_O4.onnx');
    final tokenizer = manifest.firstWhere(
      (item) => item.name == 'tokenizer.json',
    );
    return (
      model: File('${root.path}/${model.name}').path,
      tokenizer: File('${root.path}/${tokenizer.name}').path,
    );
  }

  Future<void> download({
    void Function(int received, int total)? onProgress,
    bool Function()? cancelled,
    HttpClient Function()? client,
  }) async {
    await root.create(recursive: true);
    await _delete(File('${root.path}/$_marker'));
    final http = (client ?? HttpClient.new)();
    try {
      for (final item in manifest) {
        if (cancelled?.call() ?? false) throw _Cancelled();
        final part = File('${root.path}/${item.name}.part');
        final target = File('${root.path}/${item.name}');
        await _delete(part);
        final request = await http.getUrl(Uri.parse('$baseUrl/${item.name}'));
        final response = await request.close();
        if (response.statusCode != HttpStatus.ok) {
          throw HttpException('download failed: ${response.statusCode}');
        }
        final sink = part.openWrite();
        final digestSink = _DigestSink();
        final converter = sha256.startChunkedConversion(digestSink);
        var received = 0;
        try {
          await for (final bytes in response) {
            if (cancelled?.call() ?? false) throw _Cancelled();
            sink.add(bytes);
            converter.add(bytes);
            received += bytes.length;
            onProgress?.call(received, response.contentLength);
          }
          converter.close();
        } finally {
          await sink.close();
        }
        if (received != item.bytes || digestSink.value != item.sha256) {
          throw StateError('verification failed for ${item.name}');
        }
        await _delete(target);
        await part.rename(target.path);
      }
      await File('${root.path}/$_marker').writeAsString('verified\n');
    } catch (_) {
      for (final item in manifest) {
        await _delete(File('${root.path}/${item.name}'));
        await _delete(File('${root.path}/${item.name}.part'));
      }
      await _delete(File('${root.path}/$_marker'));
      rethrow;
    } finally {
      http.close(force: true);
    }
  }
}

Future<void> _delete(File file) async {
  if (await file.exists()) await file.delete();
}

class _DigestSink implements Sink<Digest> {
  String value = '';
  @override
  void add(Digest data) => value = data.toString();
  @override
  void close() {}
}

class _Cancelled implements Exception {}
