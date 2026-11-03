import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:tylog_core/tylog_core.dart';
import '../vault.dart';
import '../controlled_editor.dart';
import '../kind_registry.dart';
import 'github_client.dart';

String? issueGithubRepo(IssueRef issue, VaultIndex index) {
  final queue = <String>[issue.projectId];
  final seen = <String>{};
  while (queue.isNotEmpty) {
    final id = queue.removeAt(0);
    if (!seen.add(id)) continue;
    final note = index.notesByPath.values
        .where((n) => n.id == id || n.title == id || n.aliases.contains(id))
        .firstOrNull;
    if (note == null) continue;
    final repo = note.properties['github'];
    if (repo is String && RegExp(r'^[^/\s]+/[^/\s]+$').hasMatch(repo)) {
      return repo;
    }
    queue.addAll(note.partOf);
  }
  return null;
}

Future<void> sendIssueToGithub({
  required IssueRef issue,
  required String repo,
  required Vault vault,
  required Future<GitHubClient> Function() githubClient,
  required Future<bool> Function(String, String Function(String)) mutateNote,
}) async {
  final registry = await readKindRegistry(vault.storage);
  final entry = registry[issue.marker];
  final label = entry is Map && entry['github_label'] is String
      ? entry['github_label'] as String
      : issue.marker;
  final date = DateTime.now().toIso8601String().substring(0, 10);
  final lineHash = sha256.convert(utf8.encode(issue.text)).toString();
  final lines = await vault.storage.exists(issue.notePath)
      ? (await vault.storage.readText(issue.notePath)).split('\n')
      : <String>[issue.text];
  final occurrence = lines
      .take(issue.line)
      .where((line) => line == issue.text)
      .length;
  final legacyMarker = 'tylog-issue: ${issue.notePath}#$lineHash';
  final marker = '$legacyMarker:${issue.line}:$occurrence';
  final client = await githubClient();
  final recoveryPath = '.tylog/github-issues.json';
  final recovery = await vault.storage.exists(recoveryPath)
      ? (jsonDecode(await vault.storage.readText(recoveryPath)) as Map)
            .cast<String, dynamic>()
      : <String, dynamic>{};
  final recoveryKey = '$repo|$marker';
  int? number = (recovery[recoveryKey] as num?)?.toInt();
  final legacyKey = '$repo|$legacyMarker';
  final comparableLines = lines.where(
    (line) =>
        line == issue.text ||
        line.replaceAll(
              RegExp(
                r'\s*#metadata\(\(\s*"tylog-issue-gh"\s*:\s*\d+\s*,?\s*\)\)',
              ),
              '',
            ) ==
            issue.text,
  );
  if (number == null && comparableLines.length == 1) {
    number = (recovery.remove(legacyKey) as num?)?.toInt();
  }
  if (number == null) {
    try {
      final matches = await client.searchIssues(repo, marker);
      if (matches.isNotEmpty) {
        number = (matches.first['number'] as num).toInt();
      }
    } catch (_) {
      // Search is best-effort; creation can still succeed.
    }
  }
  if (number == null) {
    final result = await client.createIssue(
      repo,
      issuePreview(issue.text),
      'From TyLog ${issue.notePath}, $date\n\n$marker',
      [label],
    );
    number = (result['number'] as num).toInt();
  }
  recovery[recoveryKey] = number;
  await vault.storage.createDirectory('.tylog');
  await vault.storage.writeText(recoveryPath, jsonEncode(recovery));
  if (!await mutateNote(
    issue.notePath,
    (s) => setIssueGithubNumber(s, issue, number!),
  )) {
    throw StateError('Issue could not be saved');
  }
  await vault.storage.createDirectory(decisionsDir);
  const path = '$decisionsDir/github.jsonl';
  final old = await vault.storage.exists(path)
      ? await vault.storage.readText(path)
      : '';
  await vault.storage.writeText(
    path,
    old +
        encodeDecisions([
          Decision(
            at: DateTime.now().toIso8601String(),
            device: 'github',
            item: issue.notePath,
            source: 'issue',
            action: 'sent',
            target: '$repo#$number',
          ),
        ]),
  );
}
