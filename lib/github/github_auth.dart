import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class DeviceCodeResponse {
  const DeviceCodeResponse({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.expiresIn,
    required this.interval,
  });
  final String deviceCode, userCode, verificationUri;
  final int expiresIn, interval;
}

class GitHubDeviceFlowError implements Exception {
  const GitHubDeviceFlowError(this.code);
  final String code;
  @override
  String toString() => 'GitHub device flow: $code';
}

class GitHubAuth {
  GitHubAuth({
    HttpClient? client,
    String? clientId,
    Uri? baseUri,
    FlutterSecureStorage? storage,
    Future<void> Function(Duration)? delay,
  }) : _client = client ?? HttpClient(),
       _clientId =
           clientId ??
           const String.fromEnvironment(
             'GITHUB_CLIENT_ID',
             // Public OAuth App id (device flow, no secret).
             defaultValue: 'Ov23liaWEIBMqoe3CbA3',
           ),
       _baseUri = baseUri ?? Uri.parse('https://github.com'),
       _storage = storage ?? const FlutterSecureStorage(),
       _delay = delay ?? Future<void>.delayed;
  final HttpClient _client;
  final String _clientId;
  final Uri _baseUri;
  final FlutterSecureStorage _storage;
  final Future<void> Function(Duration) _delay;
  static const tokenKey = 'github_token';

  Future<String?> token() => _storage.read(key: tokenKey);
  Future<void> clear() => _storage.delete(key: tokenKey);

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, String> fields,
  ) async {
    final request = await _client.postUrl(_baseUri.resolve(path));
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.contentType = ContentType(
      'application',
      'x-www-form-urlencoded',
      charset: 'utf-8',
    );
    request.write(
      fields.entries
          .map(
            (e) =>
                '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
          )
          .join('&'),
    );
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode != 200) {
      throw GitHubDeviceFlowError('HTTP ${response.statusCode}');
    }
    return jsonDecode(body) as Map<String, dynamic>;
  }

  Future<DeviceCodeResponse> requestDeviceCode() async {
    if (_clientId.isEmpty) {
      throw const GitHubDeviceFlowError('GITHUB_CLIENT_ID is not configured');
    }
    final data = await _post('/login/device/code', {
      'client_id': _clientId,
      'scope': 'repo',
    });
    return DeviceCodeResponse(
      deviceCode: data['device_code'] as String,
      userCode: data['user_code'] as String,
      verificationUri: data['verification_uri'] as String,
      expiresIn: data['expires_in'] as int,
      interval: data['interval'] as int,
    );
  }

  Future<String> pollForToken(DeviceCodeResponse code) async {
    var interval = code.interval;
    final expires = DateTime.now().add(Duration(seconds: code.expiresIn));
    while (true) {
      if (!DateTime.now().isBefore(expires)) {
        throw const GitHubDeviceFlowError('expired_token');
      }
      await _delay(Duration(seconds: interval));
      if (!DateTime.now().isBefore(expires)) {
        throw const GitHubDeviceFlowError('expired_token');
      }
      final data = await _post('/login/oauth/access_token', {
        'client_id': _clientId,
        'device_code': code.deviceCode,
        'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
      });
      final token = data['access_token'] as String?;
      if (token != null) {
        await _storage.write(key: tokenKey, value: token);
        return token;
      }
      final error = data['error'] as String? ?? 'invalid_response';
      if (error == 'slow_down') {
        interval += 5;
        continue;
      }
      if (error != 'authorization_pending') throw GitHubDeviceFlowError(error);
    }
  }
}

Future<String?> githubToken({
  Future<String?> Function()? readToken,
  Future<ProcessResult> Function(String, List<String>)? runProcess,
  bool? desktop,
}) async {
  String? token;
  try {
    token = await (readToken ?? GitHubAuth().token)();
  } catch (_) {}
  if (token != null && token.isNotEmpty) return token;
  if (!(desktop ??
      (Platform.isLinux || Platform.isMacOS || Platform.isWindows))) {
    return null;
  }
  try {
    final result = await (runProcess ?? Process.run)('gh', [
      'auth',
      'token',
    ]).timeout(const Duration(seconds: 5));
    final value = result.stdout.toString().trim();
    return result.exitCode == 0 && value.isNotEmpty ? value : null;
  } catch (_) {
    return null;
  }
}
