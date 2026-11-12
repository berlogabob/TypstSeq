import 'dart:io';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/github/github_client.dart';
import 'package:tylog/github/send_issue.dart';
import 'package:tylog/rich_editor.dart';
import 'package:tylog/vault.dart';
import 'package:tylog/widgets/work_surface.dart';
import 'package:tylog_core/tylog_core.dart';
import 'support/temp_dir.dart';

class FakeGithub extends GitHubClient {
  int creates = 0;
  @override
  Future<List<Map<String, dynamic>>> searchIssues(
    String repo,
    String marker,
  ) async => [];
  @override
  Future<Map<String, dynamic>> createIssue(
    String repo,
    String title,
    String body,
    List<String> labels,
  ) async {
    creates++;
    return {'number': 77};
  }
}

void main() {
  testWidgets('Today issue line menu sends and links issue', (tester) async {
    final dir = await tester.runAsync(() => Directory.systemTemp.createTemp());
    if (dir == null) throw StateError('No temp directory');
    addTearDown(() => deleteTempDir(dir));
    final vault = Vault(dir);
    final client = FakeGithub();
    const issue = IssueRef(
      notePath: 'today.typ',
      line: 1,
      text: '- bug',
      projectId: 'p',
      marker: 'fixit',
    );
    var source = issue.text;
    Future<void>? sending;
    final controller = TyLogEditingController(
      source: source,
      onSourceChanged: (_) {},
      onError: (_) {},
      onProtectedTap: (_) {},
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TodayPage(
            tasks: const [],
            recent: const [],
            onOpenPath: (_) {},
            onSetStatus: (_, _) async {},
            editor: TyLogRichEditor(
              controller: controller,
              onInsert: () async {},
              issueAction: (line) => line != 1
                  ? null
                  : () => sending = (() async {
                      await sendIssueToGithub(
                        issue: issue,
                        repo: 'a/b',
                        vault: vault,
                        githubClient: () async => client,
                        mutateNote: (_, edit) async {
                          source = edit(source);
                          return true;
                        },
                      );
                    })(),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(EditableText));
    await tester.pump();
    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    editable.showToolbar();
    await tester.pump();
    expect(find.text('Send to GitHub'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.text('Send to GitHub'));
      // Await the send itself: a polling budget fails under load and lets the
      // send outlive the test's temp directory.
      await sending;
    });
    await tester.pump();
    expect(client.creates, 1);
    expect(source, contains('"tylog-issue-gh": 77'));
  });
}
