import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/github/github_client.dart';
import 'package:tylog/github/github_projects.dart';
import 'package:tylog/vault.dart';
import 'package:tylog/widgets/github_project_board.dart';
import 'package:tylog_core/tylog_core.dart';

class FakeGraphQL extends GitHubClient {
  final calls = <Map<String, dynamic>>[];
  bool fail = false;
  @override
  Future<Map<String, dynamic>> graphQL(
    String query,
    Map<String, dynamic> variables,
  ) async {
    calls.add({'query': query, ...variables});
    if (query.contains('mutation')) {
      if (fail) throw StateError('offline');
      return {};
    }
    final second = variables['after'] != null;
    return {
      'repositoryOwner': {
        'projectV2': {
          'id': 'project',
          'fields': {
            'nodes': [
              {
                '__typename': 'ProjectV2SingleSelectField',
                'id': 'field',
                'name': 'Status',
                'options': [
                  {'id': 'todo', 'name': 'Todo'},
                  {'id': 'done', 'name': 'Done'},
                ],
              },
            ],
          },
          'items': {
            'nodes': [
              {
                'id': second ? 'two' : 'one',
                'fieldValues': {
                  'nodes': [
                    {
                      'optionId': 'todo',
                      'field': {'id': 'field'},
                    },
                  ],
                },
                'content': {
                  'title': second ? 'Second' : 'First',
                  'number': 1,
                  'repository': {'nameWithOwner': 'a/b'},
                },
              },
            ],
            'pageInfo': {
              'hasNextPage': !second,
              'endCursor': second ? null : 'cursor',
            },
          },
        },
      },
    };
  }
}

void main() {
  test('status options, paginated items and mutation', () async {
    final client = FakeGraphQL();
    final projects = GitHubProjects(client);
    final board = await projects.fetchProjectBoardFromGitHub('a', 1);
    expect(board.columns.map((c) => c.name), ['No status', 'Todo', 'Done']);
    expect(board.items.map((i) => i.title), ['First', 'Second']);
    expect(client.calls[1]['after'], 'cursor');
    await projects.setProjectItemStatus(board.id, 'one', board.fieldId, 'done');
    expect(client.calls.last['optionId'], 'done');
    expect(
      client.calls.last['query'],
      contains('updateProjectV2ItemFieldValue'),
    );
  });
  testWidgets('failed move reverts and reports error', (tester) async {
    final dir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('github-board'),
    );
    addTearDown(() => dir!.delete(recursive: true));
    final client = FakeGraphQL()..fail = true;
    await tester.pumpWidget(
      MaterialApp(
        home: GitHubProjectBoard(
          board: const Board(
            id: 'b',
            title: 'Board',
            scopeExtra: {
              'github_project': {'owner': 'a', 'number': 1},
            },
          ),
          storage: Vault(dir!).storage,
          client: () async => client,
          deviceId: 'test',
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('First')),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(
      tester.getCenter(find.byKey(const ValueKey('project-column-done'))),
    );
    await tester.pump();
    await gesture.up();
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(find.textContaining('Could not move card'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('project-column-todo')),
        matching: find.text('First'),
      ),
      findsOneWidget,
    );
    expect(client.calls.last['optionId'], 'done');
  });
}
