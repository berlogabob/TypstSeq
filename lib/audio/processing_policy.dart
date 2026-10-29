import 'dart:convert';

import 'package:tylog_core/storage.dart';

import '../settings_path.dart';

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
    this.translate = false,
    this.onTheFly = false,
    this.scheduled = false,
    this.time = '03:00',
    this.translateTo = const ['ru', 'en', 'pt'],
  });

  final bool transcribe;
  final bool translate;

  /// Process right after the audio appears.
  final bool onTheFly;

  /// Process once a day at [time] (catches up if the machine was asleep).
  final bool scheduled;
  final String time;
  final List<String> translateTo;

  AudioPolicy copyWith({
    bool? transcribe,
    bool? translate,
    bool? onTheFly,
    bool? scheduled,
    String? time,
    List<String>? translateTo,
  }) => AudioPolicy(
    transcribe: transcribe ?? this.transcribe,
    translate: translate ?? this.translate,
    onTheFly: onTheFly ?? this.onTheFly,
    scheduled: scheduled ?? this.scheduled,
    time: time ?? this.time,
    translateTo: translateTo ?? this.translateTo,
  );

  Map<String, Object?> toJson() => {
    'transcribe': transcribe,
    'translate': translate,
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
    final translateTo = to is List
        ? [
            for (final l in to)
              if (l is String) l,
          ]
        : const ['ru', 'en', 'pt'];
    return AudioPolicy(
      transcribe: json['transcribe'] == true,
      translate: json.containsKey('translate')
          ? json['translate'] == true
          : translateTo.isNotEmpty,
      onTheFly: json['on_the_fly'] == true,
      scheduled: json['scheduled'] == true,
      time: time is String && _time.hasMatch(time) ? time : '03:00',
      translateTo: translateTo,
    );
  }
}

const processingSettingsPath = '_system/settings/processing.json';
const processNowPath = '_system/jobs/process-now.json';

Future<AudioPolicy> readAudioPolicy(VaultStorage storage) async {
  try {
    final path = await settingsPathFor(storage, processingSettingsPath);
    if (!await storage.existsNow(path)) {
      return const AudioPolicy();
    }
    final data = jsonDecode(utf8.decode(await storage.readBytesNow(path)));
    return AudioPolicy.fromJson(data is Map ? data['audio'] : null);
  } catch (_) {
    return const AudioPolicy();
  }
}

/// Replaces only the `audio` key so other pipelines' settings survive.
Future<void> writeAudioPolicy(VaultStorage storage, AudioPolicy policy) async {
  final path = await settingsPathFor(storage, processingSettingsPath);
  Map<String, Object?> all = {};
  try {
    if (await storage.exists(path)) {
      final data = jsonDecode(await storage.readText(path));
      if (data is Map) all = data.cast<String, Object?>();
    }
  } catch (_) {}
  all['schema'] = 1;
  all['audio'] = policy.toJson();
  await storage.createDirectory('_system/settings');
  await storage.writeText(path, jsonEncode(all));
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
