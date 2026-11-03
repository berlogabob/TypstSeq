import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/github/github_client.dart';
import 'package:tylog/github/send_issue.dart';
import 'package:tylog/vault.dart';
import 'package:tylog_core/tylog_core.dart';

class FakeGithub extends GitHubClient {
  int creates = 0;
  int searches = 0;
  bool failSearch = false;
  List<Map<String, dynamic>> matches = [];
  String? marker;
  String? body;
  @override
  Future<List<Map<String, dynamic>>> searchIssues(
    String repo,
    String marker,
  ) async {
    searches++;
    this.marker = marker;
    if (failSearch) throw StateError('offline');
    return matches;
  }

  @override
  Future<Map<String, dynamic>> createIssue(
    String repo,
    String title,
    String body,
    List<String> labels,
  ) async {
    creates++;
    this.body = body;
    return {'number': 123};
  }
}

void main() {
  late Directory dir;
  late Vault vault;
  late FakeGithub client;
  const issue = IssueRef(
    notePath: 'log.typ',
    line: 1,
    text: '- bug',
    projectId: 'p',
    marker: 'fixit',
  );
  var source = '';
  var failWrite = false;
  Future<void> send() => sendIssueToGithub(
    issue: issue,
    repo: 'a/b',
    vault: vault,
    githubClient: () async => client,
    mutateNote: (_, edit) async {
      if (failWrite) return false;
      source = edit(source);
      return true;
    },
  );
  setUp(() async {
    dir = await Directory.systemTemp.createTemp();
    vault = Vault(dir);
    client = FakeGithub();
    source = issue.text;
    failWrite = false;
  });
  tearDown(() => dir.delete(recursive: true));
  test('retry after write failure recovers created issue', () async {
    failWrite = true;
    await expectLater(send(), throwsStateError);
    expect(client.body, contains(client.marker));
    failWrite = false;
    await send();
    expect(source, contains('"tylog-issue-gh": 123'));
    expect(client.creates, 1);
    expect(client.searches, 1);
  });
  test('search finds existing marker without recovery map', () async {
    client.matches = [
      {'number': 42},
    ];
    await send();
    expect(client.marker, startsWith('tylog-issue: log.typ#'));
    expect(source, contains('"tylog-issue-gh": 42'));
    expect(client.creates, 0);
  });
  test('search failure falls back to create', () async {
    client.failSearch = true;
    await send();
    expect(source, contains('"tylog-issue-gh": 123'));
    expect(client.creates, 1);
  });
}
