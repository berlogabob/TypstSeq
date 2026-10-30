import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/olt/olt_client.dart';

void main() {
  test('OTP request disables account creation', () async {
    late String body;
    final client = OltClient(
      store: _Store(),
      request: (method, uri, headers, value) async {
        body = value!;
        return const OltResponse(200, '{}');
      },
    );
    await client.requestCode('a@example.com');
    expect(jsonDecode(body), {'email': 'a@example.com', 'create_user': false});
  });

  test('verify saves session', () async {
    final store = _Store();
    final client = OltClient(
      store: store,
      request: (_, _, _, _) async => const OltResponse(
        200,
        '{"access_token":"a","refresh_token":"r","expires_in":3600,"user":{"email":"a@example.com"}}',
      ),
    );
    await client.verify('a@example.com', '123456');
    expect(jsonDecode(store.value!), containsPair('refresh', 'r'));
    expect((await client.session)?.email, 'a@example.com');
  });

  test('get sends bearer token', () async {
    final client = _signedIn((_, _, headers, _) async {
      expect(headers['Authorization'], 'Bearer access');
      return const OltResponse(200, '[]');
    });
    expect(await client.get('places', 'select=*'), isEmpty);
  });

  test('401 refreshes once then retries', () async {
    var gets = 0;
    final store = _Store()..value = _sessionJson;
    final client = OltClient(
      store: store,
      request: (method, uri, headers, body) async {
        if (uri.path.endsWith('/token')) {
          return const OltResponse(
            200,
            '{"access_token":"new","refresh_token":"new-r","expires_in":3600,"user":{"email":"a@example.com"}}',
          );
        }
        gets++;
        return gets == 1
            ? const OltResponse(401, '{"message":"expired"}')
            : const OltResponse(200, '[]');
      },
    );
    await client.get('places', 'select=*');
    expect(gets, 2);
    expect((await client.session)?.access, 'new');
  });

  test('surfaces server error message', () async {
    final client = OltClient(
      store: _Store(),
      request: (_, _, _, _) async =>
          const OltResponse(400, '{"msg":"Invalid code"}'),
    );
    await expectLater(
      client.requestCode('a@example.com'),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('Invalid code'),
        ),
      ),
    );
  });
}

const _sessionJson =
    '{"email":"a@example.com","access":"access","refresh":"refresh","expiresAt":"2030-01-01T00:00:00.000"}';

OltClient _signedIn(OltRequest request) =>
    OltClient(store: _Store()..value = _sessionJson, request: request);

class _Store implements OltSessionStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async => this.value = value;
  @override
  Future<void> delete() async => value = null;
}
