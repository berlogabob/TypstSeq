import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../nextcloud_sync.dart';

class NextcloudPushClient {
  NextcloudPushClient(this.config, {required this.onFilesChanged});

  final NextcloudConfig config;
  final void Function() onFilesChanged;
  final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15);
  WebSocket? _socket;
  Timer? _retry;
  bool _closed = false;
  bool _started = false;
  int _delaySeconds = 1;

  void start() {
    if (_started || _closed || !config.isReady) return;
    _started = true;
    unawaited(_connect());
  }

  Future<void> _connect() async {
    try {
      final base = Uri.parse(config.serverUrl.trim());
      final path = base.path
          .split('/remote.php/dav/files/')
          .first
          .replaceFirst(RegExp(r'/+$'), '');
      final request = await _http.getUrl(
        base.replace(
          path: '$path/ocs/v2.php/cloud/capabilities',
          query: 'format=json',
        ),
      );
      request.followRedirects = false;
      request.headers.set('OCS-APIRequest', 'true');
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Basic ${base64Encode(utf8.encode('${config.username}:${config.password}'))}',
      );
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      if (response.statusCode != 200) {
        await response.drain<void>();
        if (response.statusCode == 401 || response.statusCode == 403) return;
        throw const HttpException('capabilities');
      }
      final body = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 15));
      final endpoint = jsonDecode(
        body,
      )['ocs']?['data']?['capabilities']?['notify_push']?['endpoints']?['websocket'];
      if (endpoint is! String || endpoint.isEmpty || _closed) return;
      final uri = Uri.parse(endpoint);
      // The password goes to this socket: only to the configured server, and
      // in the clear only if that server is itself plain http.
      if (uri.host != base.host ||
          !(uri.scheme == 'wss' ||
              (uri.scheme == 'ws' && base.scheme == 'http'))) {
        return;
      }
      final socket = await WebSocket.connect(endpoint, customClient: _http);
      if (_closed) {
        await socket.close();
        return;
      }
      _socket = socket;
      socket.add(config.username);
      socket.add(config.password);
      var authenticated = false;
      await for (final message in socket.timeout(
        const Duration(seconds: 15),
        onTimeout: (sink) {
          if (!authenticated) sink.addError(TimeoutException('authentication'));
        },
      )) {
        if (_closed) return;
        if (message is! String) continue;
        if (message.startsWith('err:')) return;
        if (message == 'authenticated') {
          authenticated = true;
          _delaySeconds = 1;
        } else if (authenticated && message.startsWith('notify_file')) {
          onFilesChanged();
        }
      }
    } catch (_) {
      // Push is optional; the root probe remains the fallback.
    } finally {
      await _socket?.close();
      _socket = null;
    }
    if (_closed) return;
    _retry = Timer(
      Duration(seconds: _delaySeconds),
      () => unawaited(_connect()),
    );
    _delaySeconds = (_delaySeconds * 2).clamp(1, 300);
  }

  void close() {
    _closed = true;
    _retry?.cancel();
    unawaited(_socket?.close());
    _http.close(force: true);
  }

  void dispose() => close();
}
