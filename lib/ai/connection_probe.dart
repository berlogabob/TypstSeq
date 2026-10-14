import 'dart:async';
import 'dart:convert';
import 'dart:io';

class ProbeModel {
  const ProbeModel({required this.id, this.loaded, this.contextLength});
  final String id;
  final bool? loaded;
  final int? contextLength;
}

class ProbeResult {
  const ProbeResult({
    required this.ok,
    this.error,
    this.latencyMs = 0,
    this.models = const [],
  });
  final bool ok;
  final String? error;
  final int latencyMs;
  final List<ProbeModel> models;
}

class ModelTestResult {
  const ModelTestResult({
    required this.ok,
    this.reply,
    this.latencyMs = 0,
    this.error,
  });
  final bool ok;
  final String? reply;
  final int latencyMs;
  final String? error;
}

/// The factory is injectable; a supplied client remains owned by the caller.
class ConnectionProbe {
  ConnectionProbe({HttpClient Function()? clientFactory})
    : clientFactory = clientFactory ?? HttpClient.new;
  final HttpClient Function() clientFactory;
  static const _timeout = Duration(seconds: 6);

  Future<Object?> _request(
    String url,
    String endpoint,
    String? key,
    HttpClient? client, {
    Map<String, Object?>? body,
  }) async {
    HttpClient? active;
    HttpClientRequest? request;
    var finished = false;
    try {
      active = client ?? clientFactory();
      return await (() async {
        final uri = Uri.parse(
          '${url.trim().replaceFirst(RegExp(r'/+$'), '')}/$endpoint',
        );
        request = await active!.openUrl(body == null ? 'GET' : 'POST', uri);
        if (finished) {
          request!.abort();
          throw TimeoutException('Timed out');
        }
        if (key != null && key.trim().isNotEmpty) {
          request!.headers.set(
            HttpHeaders.authorizationHeader,
            'Bearer ${key.trim()}',
          );
        }
        if (body != null) {
          request!.headers.contentType = ContentType.json;
          request!.write(jsonEncode(body));
        }
        final response = await request!.close();
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw _ProbeError(
            response.statusCode == 401
                ? 'HTTP 401: key rejected'
                : 'HTTP ${response.statusCode}: server error',
          );
        }
        return jsonDecode(await utf8.decoder.bind(response).join());
      })().timeout(_timeout);
    } finally {
      finished = true;
      request?.abort();
      if (client == null) active?.close(force: true);
    }
  }

  Future<ProbeResult> probeServer(
    String url, {
    String? key,
    HttpClient? client,
  }) async {
    final watch = Stopwatch()..start();
    try {
      final json = await _request(url, 'models', key, client);
      if (json is! Map || json['data'] is! List) {
        throw const _ProbeError('Not an OpenAI-compatible server');
      }
      final models = <ProbeModel>[];
      for (final item in json['data'] as List) {
        if (item is! Map ||
            item['id'] is! String ||
            (item['id'] as String).trim().isEmpty) {
          continue;
        }
        final length = item['context_length'] ?? item['max_model_len'];
        models.add(
          ProbeModel(
            id: item['id'] as String,
            loaded: item['loaded'] is bool ? item['loaded'] as bool : null,
            contextLength: length is int ? length : int.tryParse('$length'),
          ),
        );
      }
      return ProbeResult(
        ok: true,
        latencyMs: watch.elapsedMilliseconds,
        models: models,
      );
    } catch (error) {
      return ProbeResult(
        ok: false,
        error: _errorText(error),
        latencyMs: watch.elapsedMilliseconds,
      );
    }
  }

  Future<ModelTestResult> testModel(
    String url,
    String model, {
    String? key,
    HttpClient? client,
  }) async {
    final watch = Stopwatch()..start();
    try {
      final json = await _request(
        url,
        'chat/completions',
        key,
        client,
        body: {
          'model': model,
          'temperature': 0,
          'max_tokens': 48,
          'messages': [
            {
              'role': 'user',
              'content': 'Translate to Portuguese: Good morning',
            },
          ],
        },
      );
      if (json is! Map || json['choices'] is! List) {
        throw const _ProbeError('Not an OpenAI-compatible server');
      }
      final choices = json['choices'] as List;
      final first = choices.firstOrNull;
      final message = first is Map ? first['message'] : null;
      final content = message is Map ? message['content'] : null;
      final reply = content is String ? content.trim() : '';
      if (reply.isEmpty) {
        throw const _ProbeError(
          "Empty reply: the model's context window may be too small or the model is not loaded",
        );
      }
      return ModelTestResult(
        ok: true,
        reply: String.fromCharCodes(reply.runes.take(120)),
        latencyMs: watch.elapsedMilliseconds,
      );
    } catch (error) {
      return ModelTestResult(
        ok: false,
        error: _errorText(error),
        latencyMs: watch.elapsedMilliseconds,
      );
    }
  }
}

class _ProbeError implements Exception {
  const _ProbeError(this.message);
  final String message;
}

String _errorText(Object error) => switch (error) {
  _ProbeError() => error.message,
  TimeoutException() => 'Timed out',
  FormatException() => 'Not an OpenAI-compatible server',
  _ => 'Cannot connect',
};

Future<ProbeResult> probeServer(
  String url, {
  String? key,
  HttpClient? client,
}) => ConnectionProbe().probeServer(url, key: key, client: client);
Future<ModelTestResult> testModel(
  String url,
  String model, {
  String? key,
  HttpClient? client,
}) => ConnectionProbe().testModel(url, model, key: key, client: client);
