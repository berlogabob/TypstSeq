import 'dart:io';
import 'dart:convert';
import 'dart:async';

class LoginFlowResult {
  final String server;
  final String loginName;
  final String appPassword;
  const LoginFlowResult(this.server, this.loginName, this.appPassword);
}

class LoginFlowStart {
  final Uri loginUrl;
  final Uri pollEndpoint;
  final String token;
  const LoginFlowStart(this.loginUrl, this.pollEndpoint, this.token);
}

Future<LoginFlowStart> startLoginFlow(Uri server, {HttpClient? client}) async {
  final HttpClient httpClient = client ?? HttpClient();
  try {
    final Uri uri = Uri.parse('${server.toString()}/index.php/login/v2');
    final HttpClientRequest request = await httpClient.postUrl(uri);
    request.headers.set('User-Agent', 'TyLog');
    request.headers.set('Content-Type', 'application/json');

    final HttpClientResponse response = await request.close();

    if (response.statusCode != 200) {
      await response.drain<void>();
      throw FormatException('HTTP ${response.statusCode}');
    }

    final String responseString = await response
        .transform(utf8.decoder)
        .join('');
    final Map<String, dynamic> jsonResponse = json.decode(responseString);

    if (!jsonResponse.containsKey('poll') ||
        !jsonResponse.containsKey('login')) {
      throw FormatException('Malformed JSON response');
    }

    final Map<String, dynamic> pollData = jsonResponse['poll'];
    final String token = pollData['token'];
    final String endpoint = pollData['endpoint'];
    // Nextcloud returns an absolute endpoint; resolve also accepts a relative one.
    final Uri pollEndpoint = server.resolve(endpoint);

    final String loginUrlString = jsonResponse['login'];
    final Uri loginUrl = Uri.parse(loginUrlString);

    return LoginFlowStart(loginUrl, pollEndpoint, token);
  } finally {
    if (client == null) httpClient.close();
  }
}

Future<LoginFlowResult> pollLoginFlow(
  LoginFlowStart start, {
  HttpClient? client,
  Duration interval = const Duration(seconds: 2),
  Duration timeout = const Duration(minutes: 5),
}) async {
  final HttpClient httpClient = client ?? HttpClient();
  final Stopwatch stopwatch = Stopwatch()..start();

  try {
    while (stopwatch.elapsed < timeout) {
      final HttpClientRequest request = await httpClient.postUrl(
        start.pollEndpoint,
      );
      request.headers.set('Content-Type', 'application/x-www-form-urlencoded');
      request.write('token=${Uri.encodeComponent(start.token)}');

      final HttpClientResponse response = await request.close();

      if (response.statusCode == 404) {
        // Not yet approved, wait and retry
        await response.drain<void>();
        await Future.delayed(interval);
        continue;
      } else if (response.statusCode == 200) {
        // Success
        final String responseString = await response
            .transform(utf8.decoder)
            .join('');
        final Map<String, dynamic> jsonResponse = json.decode(responseString);

        if (!jsonResponse.containsKey('server') ||
            !jsonResponse.containsKey('loginName') ||
            !jsonResponse.containsKey('appPassword')) {
          throw FormatException('Malformed JSON response');
        }

        return LoginFlowResult(
          jsonResponse['server'],
          jsonResponse['loginName'],
          jsonResponse['appPassword'],
        );
      } else {
        // Other error
        await response.drain<void>();
        throw HttpException('HTTP ${response.statusCode}');
      }
    }

    throw TimeoutException('Login flow timed out', timeout);
  } finally {
    if (client == null) httpClient.close();
  }
}
