import 'dart:convert';

import 'package:tylog_core/storage.dart';

/// Languages offered for translation (ISO code -> native name).
const kLanguageNames = {
  'ru': 'Русский',
  'en': 'English',
  'pt': 'Português',
  'uk': 'Українська',
  'es': 'Español',
  'fr': 'Français',
  'de': 'Deutsch',
  'it': 'Italiano',
};

/// When the worker transcribes and translates audio on its own. Stored in the
/// synced vault (`_system/settings/processing.json`) because the worker runs
/// on another machine; contract: docs/audio-transcription.md.
class AudioPolicy {
  const AudioPolicy({
    this.transcribe = false,
    this.onTheFly = false,
    this.scheduled = false,
    this.time = '03:00',
    this.translateTo = const [],
  });

  final bool transcribe;

  /// Process right after the audio appears.
  final bool onTheFly;

  /// Process once a day at [time] (catches up if the machine was asleep).
  final bool scheduled;
  final String time;
  final List<String> translateTo;

  AudioPolicy copyWith({
    bool? transcribe,
    bool? onTheFly,
    bool? scheduled,
    String? time,
    List<String>? translateTo,
  }) => AudioPolicy(
    transcribe: transcribe ?? this.transcribe,
    onTheFly: onTheFly ?? this.onTheFly,
    scheduled: scheduled ?? this.scheduled,
    time: time ?? this.time,
    translateTo: translateTo ?? this.translateTo,
  );

  Map<String, Object?> toJson() => {
    'transcribe': transcribe,
    'on_the_fly': onTheFly,
    'scheduled': scheduled,
    'time': time,
    'translate_to': translateTo,
  };

  static final _time = RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$');

  factory AudioPolicy.fromJson(Object? json) {
    if (json is! Map) return const AudioPolicy();
    final time = json['time'];
    final to = json['translate_to'];
    return AudioPolicy(
      transcribe: json['transcribe'] == true,
      onTheFly: json['on_the_fly'] == true,
      scheduled: json['scheduled'] == true,
      time: time is String && _time.hasMatch(time) ? time : '03:00',
      translateTo: to is List
          ? [
              for (final l in to)
                if (l is String) l,
            ]
          : [],
    );
  }
}

const processingSettingsPath = '_system/settings/processing.json';
const processNowPath = '_system/jobs/process-now.json';

Future<AudioPolicy> readAudioPolicy(VaultStorage storage) async {
  try {
    if (!await storage.exists(processingSettingsPath)) {
      return const AudioPolicy();
    }
    final data = jsonDecode(await storage.readText(processingSettingsPath));
    return AudioPolicy.fromJson(data is Map ? data['audio'] : null);
  } catch (_) {
    return const AudioPolicy();
  }
}

/// Replaces only the `audio` key so other pipelines' settings survive.
Future<void> writeAudioPolicy(VaultStorage storage, AudioPolicy policy) async {
  Map<String, Object?> all = {};
  try {
    if (await storage.exists(processingSettingsPath)) {
      final data = jsonDecode(await storage.readText(processingSettingsPath));
      if (data is Map) all = data.cast<String, Object?>();
    }
  } catch (_) {}
  all['schema'] = 1;
  all['audio'] = policy.toJson();
  await storage.createDirectory('_system/settings');
  await storage.writeText(processingSettingsPath, jsonEncode(all));
}

/// "Process now": the worker sweeps once with the schedule gate forced open.
Future<void> requestProcessNow(VaultStorage storage, {DateTime? now}) async {
  await storage.createDirectory('_system/jobs');
  await storage.writeText(
    processNowPath,
    jsonEncode({
      'requested_at': (now ?? DateTime.now()).toUtc().toIso8601String(),
    }),
  );
}
