import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _url = 'https://ukelqvkanfimiafnomex.supabase.co';
const _anonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVrZWxxdmthbmZpbWlhZm5vbWV4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTI1ODU4NzEsImV4cCI6MjEwODE2MTg3MX0.uTR4Eu4tIujRoTKgfSCzHllOKa0pQSyxSNnz92DbUZs';

class OltSession {
  const OltSession({
    required this.email,
    required this.access,
    required this.refresh,
    required this.expiresAt,
  });

  final String email;
  final String access;
  final String refresh;
  final DateTime expiresAt;

  Map<String, dynamic> toJson() => {
    'email': email,
    'access': access,
    'refresh': refresh,
    'expiresAt': expiresAt.toIso8601String(),
  };

  factory OltSession.fromJson(Map<String, dynamic> json) => OltSession(
    email: json['email'] as String,
    access: json['access'] as String,
    refresh: json['refresh'] as String,
    expiresAt: DateTime.parse(json['expiresAt'] as String),
  );
}

typedef OltRequest =
    Future<OltResponse> Function(
      String method,
      Uri uri,
      Map<String, String> headers,
      String? body,
    );

class OltResponse {
  const OltResponse(this.statusCode, this.body);
  final int statusCode;
  final String body;
}

class OltClient {
  OltClient({OltRequest? request, OltSessionStore? store})
    : _request = request ?? _httpRequest,
      _store = store ?? SecureOltSessionStore();

  final OltRequest _request;
  final OltSessionStore _store;
  OltSession? _session;

  Future<OltSession?> get session async => _session ??= await _readSession();

  Future<void> requestCode(String email) async {
    await _send('POST', Uri.parse('$_url/auth/v1/otp'), {
      'email': email,
      'create_user': false,
    });
  }

  Future<void> verify(String email, String code) async {
    final result = await _send('POST', Uri.parse('$_url/auth/v1/verify'), {
      'type': 'email',
      'email': email,
      'token': code,
    });
    final user = result['user'] as Map<String, dynamic>;
    await _saveSession(_sessionFrom(result, user['email'] as String));
  }

  Future<void> refresh() async {
    final current = await session;
    if (current == null) throw StateError('Not signed in');
    final result = await _send(
      'POST',
      Uri.parse('$_url/auth/v1/token?grant_type=refresh_token'),
      {'refresh_token': current.refresh},
    );
    final user = result['user'] as Map<String, dynamic>?;
    await _saveSession(
      _sessionFrom(result, user?['email'] as String? ?? current.email),
    );
  }

  Future<dynamic> get(String table, String query) async {
    var current = await session;
    if (current == null) throw StateError('Not signed in');
    var response = await _get(current, table, query);
    if (response.statusCode == 401) {
      await refresh();
      current = await session;
      response = await _get(current!, table, query);
    }
    return _decode(response);
  }

  Future<OltResponse> _get(OltSession session, String table, String query) =>
      _request('GET', Uri.parse('$_url/rest/v1/$table?$query'), {
        'apikey': _anonKey,
        'Authorization': 'Bearer ${session.access}',
      }, null);

  Future<Map<String, dynamic>> _send(
    String method,
    Uri uri,
    Map<String, dynamic> body,
  ) async =>
      (await _decode(
                await _request(method, uri, {
                  'apikey': _anonKey,
                  'Content-Type': 'application/json',
                }, jsonEncode(body)),
              )
              as Map?)
          ?.cast<String, dynamic>() ??
      {};

  /// Rows come back as a JSON array, auth replies as an object.
  Future<dynamic> _decode(OltResponse response) async {
    final decoded = response.body.isEmpty ? null : jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = decoded is Map ? decoded : const {};
      throw Exception(
        error['msg'] ??
            error['error_description'] ??
            error['message'] ??
            error['error'] ??
            response.body,
      );
    }
    return decoded;
  }

  OltSession _sessionFrom(Map<String, dynamic> result, String email) =>
      OltSession(
        email: email,
        access: result['access_token'] as String,
        refresh: result['refresh_token'] as String,
        expiresAt: DateTime.now().add(
          Duration(seconds: result['expires_in'] as int),
        ),
      );

  Future<OltSession?> _readSession() async {
    final value = await _store.read();
    if (value == null) return null;
    try {
      return OltSession.fromJson(jsonDecode(value) as Map<String, dynamic>);
    } catch (_) {
      await _store.delete();
      return null;
    }
  }

  Future<void> _saveSession(OltSession value) async {
    _session = value;
    await _store.write(jsonEncode(value.toJson()));
  }

  Future<void> signOut() async {
    _session = null;
    await _store.delete();
  }
}

abstract interface class OltSessionStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> delete();
}

class SecureOltSessionStore implements OltSessionStore {
  SecureOltSessionStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;
  static const _key = 'olt-session';

  @override
  Future<String?> read() => _storage.read(key: _key);
  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);
  @override
  Future<void> delete() => _storage.delete(key: _key);
}

Future<OltResponse> _httpRequest(
  String method,
  Uri uri,
  Map<String, String> headers,
  String? body,
) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  try {
    final request = await client.openUrl(method, uri);
    headers.forEach(request.headers.set);
    if (body != null) request.write(body);
    final response = await request.close();
    return OltResponse(
      response.statusCode,
      await response.transform(utf8.decoder).join(),
    );
  } finally {
    client.close();
  }
}
