import 'dart:convert';

import 'package:tylog_core/storage.dart';

class AiConnection {
  const AiConnection({
    this.id = '',
    this.kind = 'openai-compatible',
    this.label = '',
    this.url = '',
  });

  final String id;
  final String kind;
  final String label;
  final String url;

  AiConnection copyWith({
    String? id,
    String? kind,
    String? label,
    String? url,
  }) => AiConnection(
    id: id ?? this.id,
    kind: kind ?? this.kind,
    label: label ?? this.label,
    url: url ?? this.url,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind,
    'label': label,
    'url': url,
  };

  factory AiConnection.fromJson(Object? json) {
    if (json is! Map) return const AiConnection();
    return AiConnection(
      id: json['id'] is String ? json['id'] as String : '',
      kind: json['kind'] is String
          ? json['kind'] as String
          : 'openai-compatible',
      label: json['label'] is String ? json['label'] as String : '',
      url: json['url'] is String ? json['url'] as String : '',
    );
  }
}

const _unset = Object();

class AiTask {
  const AiTask({this.quality = 'best', this.model, this.connection});

  final String quality;
  final String? model;
  final String? connection;

  AiTask copyWith({
    String? quality,
    Object? model = _unset,
    Object? connection = _unset,
  }) => AiTask(
    quality: quality ?? this.quality,
    model: identical(model, _unset) ? this.model : model as String?,
    connection: identical(connection, _unset)
        ? this.connection
        : connection as String?,
  );

  Map<String, Object?> toJson() => {
    'quality': quality,
    if (model != null) 'model': model,
    if (connection != null) 'connection': connection,
  };

  factory AiTask.fromJson(Object? json) {
    if (json is! Map) return const AiTask();
    final quality = json['quality'];
    return AiTask(
      quality: quality == 'fast' || quality == 'balanced' || quality == 'best'
          ? quality as String
          : 'best',
      model: json['model'] is String ? json['model'] as String : null,
      connection: json['connection'] is String
          ? json['connection'] as String
          : null,
    );
  }
}

String whisperModelFor(AiTask t) =>
    t.model ??
    switch (t.quality) {
      'fast' => 'small',
      'balanced' => 'large-v3-turbo',
      _ => 'large-v3',
    };

String translateModelFor(AiTask t) =>
    t.model ??
    (t.quality == 'fast' ? 'ollama/ornith-1.5:9b' : 'ollama/ornith-1.5:35b');

class AiSettings {
  const AiSettings({
    this.connections = const [],
    this.transcribe = const AiTask(),
    this.translate = const AiTask(),
  });

  final List<AiConnection> connections;
  final AiTask transcribe;
  final AiTask translate;

  AiSettings copyWith({
    List<AiConnection>? connections,
    AiTask? transcribe,
    AiTask? translate,
  }) => AiSettings(
    connections: connections ?? this.connections,
    transcribe: transcribe ?? this.transcribe,
    translate: translate ?? this.translate,
  );

  Map<String, Object?> toJson() => {
    'schema': 1,
    'connections': [for (final connection in connections) connection.toJson()],
    'tasks': {
      'transcribe': transcribe.toJson(),
      'translate': translate.toJson(),
    },
  };

  factory AiSettings.fromJson(Object? json) {
    if (json is! Map) return const AiSettings();
    final connections = json['connections'];
    final tasks = json['tasks'];
    return AiSettings(
      connections: connections is List
          ? [
              for (final item in connections)
                if (AiConnection.fromJson(item) case final connection
                    when connection.id.trim().isNotEmpty &&
                        connection.url.trim().isNotEmpty)
                  connection,
            ]
          : const [],
      transcribe: AiTask.fromJson(tasks is Map ? tasks['transcribe'] : null),
      translate: AiTask.fromJson(tasks is Map ? tasks['translate'] : null),
    );
  }
}

const aiSettingsPath = '_system/settings/ai.json';

Future<AiSettings> readAiSettings(VaultStorage storage) async {
  try {
    if (!await storage.exists(aiSettingsPath)) return const AiSettings();
    return AiSettings.fromJson(
      jsonDecode(await storage.readText(aiSettingsPath)),
    );
  } catch (_) {
    return const AiSettings();
  }
}

/// Replaces known settings so other top-level keys survive.
Future<void> writeAiSettings(VaultStorage storage, AiSettings settings) async {
  Map<String, Object?> all = {};
  try {
    if (await storage.exists(aiSettingsPath)) {
      final data = jsonDecode(await storage.readText(aiSettingsPath));
      if (data is Map) all = data.cast<String, Object?>();
    }
  } catch (_) {}
  all.addAll(settings.toJson());
  await storage.createDirectory('_system/settings');
  await storage.writeText(aiSettingsPath, jsonEncode(all));
}

class WorkerStatus {
  const WorkerStatus({
    this.host = '',
    this.lastSeen,
    this.whisperModels = const [],
    this.connections = const {},
  });

  final String host;
  final DateTime? lastSeen;
  final List<String> whisperModels;
  final Map<String, ({bool reachable, List<String> loaded})> connections;

  bool isOnline({
    Duration within = const Duration(minutes: 5),
    required DateTime now,
  }) {
    final seen = lastSeen;
    if (seen == null) return false;
    final age = now.difference(seen);
    return !age.isNegative && age <= within;
  }

  factory WorkerStatus.fromJson(Object? json) {
    if (json is! Map) return const WorkerStatus();
    final lastSeen = json['last_seen'];
    final whisperModels = json['whisper_models'];
    final connections = json['connections'];
    return WorkerStatus(
      host: json['host'] is String ? json['host'] as String : '',
      lastSeen: lastSeen is String ? DateTime.tryParse(lastSeen) : null,
      whisperModels: whisperModels is List
          ? [
              for (final model in whisperModels)
                if (model is String) model,
            ]
          : const [],
      connections: connections is Map
          ? {
              for (final entry in connections.entries)
                if (entry.key is String && entry.value is Map)
                  entry.key as String: (
                    reachable: entry.value['reachable'] == true,
                    loaded: entry.value['loaded'] is List
                        ? [
                            for (final model in entry.value['loaded'])
                              if (model is String) model,
                          ]
                        : <String>[],
                  ),
            }
          : const {},
    );
  }
}

Future<List<WorkerStatus>> readWorkers(VaultStorage storage) async {
  const directory = '_system/workers';
  if (!await storage.exists(directory)) return const [];
  final workers = <WorkerStatus>[];
  for (final entry in await storage.list(path: directory)) {
    if (entry.isDirectory || !entry.path.endsWith('.json')) continue;
    try {
      final data = jsonDecode(await storage.readText(entry.path));
      if (data is! Map) continue;
      workers.add(WorkerStatus.fromJson(data));
    } catch (_) {}
  }
  return workers;
}
