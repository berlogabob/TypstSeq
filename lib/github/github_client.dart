import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class GitHubAuthError implements Exception {}

class GitHubConflict implements Exception {}

class GitHubRateLimit implements Exception {
  GitHubRateLimit(this.resetTime);
  final DateTime? resetTime;
}

class GitHubHttpError implements Exception {
  GitHubHttpError(this.statusCode, this.body);
  final int statusCode;
  final String body;
  @override
  String toString() => 'GitHub HTTP $statusCode: $body';
}

class GitHubClient {
  GitHubClient([this.token, HttpClient? client, Uri? baseUri])
    : _client = client ?? HttpClient(),
      _baseUri = baseUri ?? Uri.parse('https://api.github.com');
  final String? token;
  final HttpClient _client;
  final Uri _baseUri;
  static const maxZipBytes = 200 * 1024 * 1024;

  String _repo(String repo) =>
      repo.split('/').map(Uri.encodeComponent).join('/');
  String _path(String path) =>
      path.split('/').map(Uri.encodeComponent).join('/');
  Uri _uri(String path, [Map<String, String>? query]) => Uri.parse(
    _baseUri
        .resolve(path)
        .replace(queryParameters: query)
        .toString()
        .replaceAll('+', '%20'),
  );

  Future<Uint8List> _request(
    String method,
    Uri uri, {
    Object? body,
    String accept = 'application/vnd.github+json',
    int? limit,
    bool conflict = false,
  }) async {
    var current = uri;
    for (var redirects = 0; redirects <= 10; redirects++) {
      final request = await _client.openUrl(method, current);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.userAgentHeader, 'TyLog');
      request.headers.set(HttpHeaders.acceptHeader, accept);
      if (token != null && current.origin == _baseUri.origin) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close();
      if ([301, 302, 303, 307, 308].contains(response.statusCode) &&
          response.headers.value(HttpHeaders.locationHeader) != null) {
        final next = current.resolve(
          response.headers.value(HttpHeaders.locationHeader)!,
        );
        await response.drain<void>();
        if (current.scheme == 'https' && next.scheme != 'https') {
          throw StateError('Insecure GitHub redirect');
        }
        current = next;
        continue;
      }
      if (response.statusCode == 401) {
        await response.drain<void>();
        throw GitHubAuthError();
      }
      if (response.statusCode == 403 &&
          response.headers.value('x-ratelimit-remaining') == '0') {
        final seconds = int.tryParse(
          response.headers.value('x-ratelimit-reset') ?? '',
        );
        await response.drain<void>();
        throw GitHubRateLimit(
          seconds == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(
                  seconds * 1000,
                  isUtc: true,
                ),
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final error = await utf8.decoder.bind(response).join();
        if (conflict &&
            (response.statusCode == 409 ||
                (response.statusCode == 422 &&
                    RegExp(
                      r'\bsha\b',
                      caseSensitive: false,
                    ).hasMatch(error)))) {
          throw GitHubConflict();
        }
        throw GitHubHttpError(response.statusCode, error);
      }
      if (limit != null && response.contentLength > limit) {
        response.listen(null).cancel();
        throw StateError('Download exceeds size limit');
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response) {
        if (limit != null && bytes.length + chunk.length > limit) {
          throw StateError('Download exceeds size limit');
        }
        bytes.add(chunk);
      }
      return bytes.takeBytes();
    }
    throw StateError('Too many GitHub redirects');
  }

  Future<Map<String, dynamic>> _json(
    String method,
    Uri uri, {
    Object? body,
    bool conflict = false,
  }) async =>
      jsonDecode(
            utf8.decode(
              await _request(method, uri, body: body, conflict: conflict),
            ),
          )
          as Map<String, dynamic>;
  Future<Map<String, dynamic>> graphQL(
    String query,
    Map<String, dynamic> variables,
  ) async {
    final result = await _json(
      'POST',
      _uri('/graphql'),
      body: {'query': query, 'variables': variables},
    );
    if (result['errors'] != null) {
      throw StateError('GitHub GraphQL: ${result['errors']}');
    }
    return result['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> currentUser() => _json('GET', _uri('/user'));

  Future<String> defaultBranch(String repo) async =>
      (await _json('GET', _uri('/repos/${_repo(repo)}')))['default_branch']
          as String;

  Future<Map<String, dynamic>> repoPermissions(String repo) async {
    final data = await _json('GET', _uri('/repos/${_repo(repo)}'));
    return (data['permissions'] as Map<String, dynamic>?) ?? {};
  }

  Future<bool> canPush(String repo) async =>
      (await repoPermissions(repo))['push'] == true;

  Future<String> commitSha(String repo, String ref) async =>
      (await _json(
            'GET',
            _uri('/repos/${_repo(repo)}/commits/${Uri.encodeComponent(ref)}'),
          ))['sha']
          as String;
  Future<Uint8List> downloadZipball(String repo, String ref) => _request(
    'GET',
    _uri('/repos/${_repo(repo)}/zipball/${Uri.encodeComponent(ref)}'),
    limit: maxZipBytes,
  );
  Future<({String tag, List<({String name, String url})> assets})>
  latestRelease(String repo) async {
    final data = await _json(
      'GET',
      _uri('/repos/${_repo(repo)}/releases/latest'),
    );
    return (
      tag: data['tag_name'] as String,
      assets: (data['assets'] as List)
          .map((a) => (name: a['name'] as String, url: a['url'] as String))
          .toList(),
    );
  }

  Future<Uint8List> downloadAsset(String url) =>
      _request('GET', Uri.parse(url), accept: 'application/octet-stream');
  Future<({String sha, Uint8List bytes})> getContent(
    String repo,
    String path,
    String ref,
  ) async {
    final data = await _json(
      'GET',
      _uri('/repos/${_repo(repo)}/contents/${_path(path)}', {'ref': ref}),
    );
    return (
      sha: data['sha'] as String,
      bytes: base64Decode(
        (data['content'] as String).replaceAll(RegExp(r'\s'), ''),
      ),
    );
  }

  Future<String> putContent(
    String repo,
    String path,
    List<int> bytes,
    String message, {
    String? sha,
    required String branch,
  }) async {
    final data = await _json(
      'PUT',
      _uri('/repos/${_repo(repo)}/contents/${_path(path)}'),
      body: {
        'message': message,
        'content': base64Encode(bytes),
        'branch': branch,
        'sha': ?sha,
      },
      conflict: true,
    );
    return (data['content'] as Map<String, dynamic>)['sha'] as String;
  }

  Future<Map<String, dynamic>> createIssue(
    String repo,
    String title,
    String body,
    List<String> labels,
  ) => _json(
    'POST',
    _uri('/repos/${_repo(repo)}/issues'),
    body: {'title': title, 'body': body, 'labels': labels},
  );
  Future<List<Map<String, dynamic>>> searchIssues(
    String repo,
    String marker,
  ) async {
    final data = await _json(
      'GET',
      _uri('/search/issues', {'q': 'repo:$repo "$marker" in:body'}),
    );
    return (data['items'] as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> repositoryIssues(String repo) async {
    final issues = <Map<String, dynamic>>[];
    for (var page = 1; ; page++) {
      final rows =
          jsonDecode(
                utf8.decode(
                  await _request(
                    'GET',
                    _uri('/repos/${_repo(repo)}/issues', {
                      'state': 'all',
                      'per_page': '100',
                      'page': '$page',
                    }),
                  ),
                ),
              )
              as List;
      issues.addAll(
        rows.cast<Map<String, dynamic>>().where(
          (row) => !row.containsKey('pull_request'),
        ),
      );
      if (rows.length < 100) return issues;
    }
  }

  Future<Map<String, dynamic>> issue(String repo, int number) =>
      _json('GET', _uri('/repos/${_repo(repo)}/issues/$number'));
  Future<Map<String, dynamic>> updateIssueColumn(
    String repo,
    int number,
    String column,
    List<String> labels, {
    String? currentColumn,
  }) async {
    final path = '/repos/${_repo(repo)}/issues/$number';
    final result =
        currentColumn != null && (currentColumn == 'done') == (column == 'done')
        ? <String, dynamic>{}
        : await _json(
            'PATCH',
            _uri(path),
            body: {'state': column == 'done' ? 'closed' : 'open'},
          );
    if (column == 'doing' && !labels.contains('doing')) {
      await _request(
        'POST',
        _uri('$path/labels'),
        body: {
          'labels': ['doing'],
        },
      );
    } else if (column == 'todo' && labels.contains('doing')) {
      try {
        await _request('DELETE', _uri('$path/labels/doing'));
      } on GitHubHttpError catch (error) {
        if (error.statusCode != 404) rethrow;
      }
    }
    return result;
  }

  Future<Map<String, dynamic>> closeIssue(String repo, int number) => _json(
    'PATCH',
    _uri('/repos/${_repo(repo)}/issues/$number'),
    body: {'state': 'closed'},
  );
}
