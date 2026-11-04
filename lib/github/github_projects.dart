import 'github_client.dart';

class GitHubProject {
  const GitHubProject(this.owner, this.number, this.title);
  final String owner, title;
  final int number;
}

class ProjectColumn {
  const ProjectColumn(this.id, this.name);
  final String? id;
  final String name;
}

class ProjectItem {
  ProjectItem(this.id, this.title, this.number, this.repo, this.status);
  final String id, title;
  final int? number;
  final String? repo;
  String? status;
}

class ProjectBoard {
  const ProjectBoard(this.id, this.fieldId, this.columns, this.items);
  final String id, fieldId;
  final List<ProjectColumn> columns;
  final List<ProjectItem> items;
}

class GitHubProjects {
  GitHubProjects(this.client);
  final GitHubClient client;

  String? _next(Map connection) {
    final page = connection['pageInfo'] as Map;
    if (page['hasNextPage'] != true) return null;
    final cursor = page['endCursor'] as String?;
    if (cursor == null || cursor.isEmpty) {
      throw StateError('Missing GitHub page cursor');
    }
    return cursor;
  }

  Future<List<GitHubProject>> fetchProjectsFromGitHub() async {
    final result = <GitHubProject>[];
    Future<void> projects(String? owner) async {
      String? cursor;
      do {
        final data = await client.graphQL(
          owner == null
              ? r'''query Projects($after: String) { viewer { login projectsV2(first: 100, after: $after) { nodes { number title } pageInfo { hasNextPage endCursor } } } }'''
              : r'''query OrganizationProjects($login: String!, $after: String) { organization(login: $login) { login projectsV2(first: 100, after: $after, minPermissionLevel: READ) { nodes { number title } pageInfo { hasNextPage endCursor } } } }''',
          {'after': cursor, 'login': ?owner},
        );
        final node = data[owner == null ? 'viewer' : 'organization'] as Map?;
        if (node == null) break;
        final connection = node['projectsV2'] as Map;
        for (final raw in connection['nodes'] as List) {
          if (raw == null) continue;
          result.add(
            GitHubProject(
              node['login'] as String,
              raw['number'] as int,
              raw['title'] as String,
            ),
          );
        }
        cursor = _next(connection);
      } while (cursor != null);
    }

    await projects(null);
    String? cursor;
    do {
      final data = await client.graphQL(
        r'''query Organizations($after: String) { viewer { organizations(first: 100, after: $after) { nodes { login } pageInfo { hasNextPage endCursor } } } }''',
        {'after': cursor},
      );
      final connection = (data['viewer'] as Map)['organizations'] as Map;
      for (final org in connection['nodes'] as List) {
        if (org != null) await projects(org['login'] as String);
      }
      cursor = _next(connection);
    } while (cursor != null);
    return result;
  }

  Future<ProjectBoard> fetchProjectBoardFromGitHub(
    String owner,
    int number,
  ) async {
    const query =
        r'''query ProjectBoard($owner: String!, $number: Int!, $after: String) {
      repositoryOwner(login: $owner) {
        ... on User { projectV2(number: $number) { ...Board } }
        ... on Organization { projectV2(number: $number) { ...Board } }
      }
    }
    fragment Board on ProjectV2 {
      id fields(first: 100) { nodes { __typename ... on ProjectV2SingleSelectField { id name options { id name } } } }
      items(first: 100, after: $after) { nodes { id fieldValues(first: 100) { nodes { ... on ProjectV2ItemFieldSingleSelectValue { optionId field { ... on ProjectV2FieldCommon { id } } } } } content { __typename ... on Issue { title number repository { nameWithOwner } } ... on PullRequest { title number repository { nameWithOwner } } ... on DraftIssue { title } } } pageInfo { hasNextPage endCursor } }
    }''';
    String? cursor, projectId, fieldId;
    final columns = <ProjectColumn>[];
    final items = <ProjectItem>[];
    do {
      final data = await client.graphQL(query, {
        'owner': owner,
        'number': number,
        'after': cursor,
      });
      final node = (data['repositoryOwner'] as Map?)?['projectV2'];
      if (node == null) throw StateError('Project not found');
      projectId = node['id'] as String;
      if (fieldId == null) {
        for (final field in (node['fields'] as Map)['nodes'] as List) {
          if (field != null &&
              field['__typename'] == 'ProjectV2SingleSelectField' &&
              (field['name'] as String).toLowerCase() == 'status') {
            fieldId = field['id'] as String;
            columns.add(const ProjectColumn(null, 'No status'));
            for (final option in field['options'] as List) {
              columns.add(
                ProjectColumn(option['id'] as String, option['name'] as String),
              );
            }
            break;
          }
        }
        if (fieldId == null) {
          throw StateError('Project has no single-select Status field');
        }
      }
      final connection = node['items'] as Map;
      for (final item in connection['nodes'] as List) {
        if (item == null) continue;
        final content = item['content'] as Map?;
        String? status;
        for (final value in (item['fieldValues'] as Map)['nodes'] as List) {
          if (value != null && (value['field'] as Map?)?['id'] == fieldId) {
            status = value['optionId'] as String?;
          }
        }
        items.add(
          ProjectItem(
            item['id'] as String,
            content?['title'] as String? ?? 'Unavailable item',
            content?['number'] as int?,
            (content?['repository'] as Map?)?['nameWithOwner'] as String?,
            status,
          ),
        );
      }
      cursor = _next(connection);
    } while (cursor != null);
    return ProjectBoard(projectId, fieldId, columns, items);
  }

  Future<void> setProjectItemStatus(
    String projectId,
    String itemId,
    String fieldId,
    String? optionId,
  ) async {
    await client.graphQL(
      optionId == null
          ? r'''mutation ClearStatus($projectId: ID!, $itemId: ID!, $fieldId: ID!) { clearProjectV2ItemFieldValue(input: {projectId: $projectId, itemId: $itemId, fieldId: $fieldId}) { projectV2Item { id } } }'''
          : r'''mutation SetStatus($projectId: ID!, $itemId: ID!, $fieldId: ID!, $optionId: String!) { updateProjectV2ItemFieldValue(input: {projectId: $projectId, itemId: $itemId, fieldId: $fieldId, value: {singleSelectOptionId: $optionId}}) { projectV2Item { id } } }''',
      {
        'projectId': projectId,
        'itemId': itemId,
        'fieldId': fieldId,
        'optionId': ?optionId,
      },
    );
  }
}
