import 'package:tylog_core/values.dart' show escapeMarkup;

/// An audio recording is a normal TyLog note (`kind: audio`): header, one
/// `#tylog.attachment(..., kind: "audio")` call, and timestamped comments as
/// list lines in the body (`- 00:42 good chorus entry`). Comments therefore
/// sync, search and link like any note text, and a later transcript can be
/// another body section.
typedef AudioComment = ({int ms, String text});

String _two(int v) => v.toString().padLeft(2, '0');

/// `20261014-153042`; pass [withMillis] to disambiguate a same-second take.
String audioStamp(DateTime t, {bool withMillis = false}) =>
    '${t.year.toString().padLeft(4, '0')}${_two(t.month)}${_two(t.day)}-'
    '${_two(t.hour)}${_two(t.minute)}${_two(t.second)}'
    '${withMillis ? '-${t.millisecond.toString().padLeft(3, '0')}' : ''}';

/// Same readable id as the file name: `Audio 20261014-153042`.
String audioTitle(String stamp) => 'Audio $stamp';

({String id, String title}) audioAssetNote(String assetPath) {
  final slug = assetPath
      .replaceFirst(RegExp(r'^assets/'), '')
      .replaceFirst(RegExp(r'\.[^./]+$'), '')
      .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-');
  final base = assetPath.split('/').last.replaceFirst(RegExp(r'\.[^.]+$'), '');
  return (id: 'audio-$slug', title: audioTitle(base));
}

/// Waveform peaks (0-255) as hex, two chars each, to fit a header property.
String encodePeaks(List<int> peaks) =>
    peaks.map((p) => p.clamp(0, 255).toRadixString(16).padLeft(2, '0')).join();

List<int> decodePeaks(Object? value) {
  if (value is! String || value.length < 2) return const [];
  return [
    for (var i = 0; i + 1 < value.length; i += 2)
      int.tryParse(value.substring(i, i + 2), radix: 16) ?? 0,
  ];
}

final _commentLine = RegExp(r'^\s*-\s+(\d{1,3}):([0-5]\d)\s+(.+?)\s*$');

String _unescape(String s) =>
    s.replaceAllMapped(RegExp(r'\\(.)'), (m) => m.group(1)!);

String _commentSource(int ms, String text) {
  final total = ms ~/ 1000;
  final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return '- ${_two(total ~/ 60)}:${_two(total % 60)} ${escapeMarkup(flat)}';
}

/// Line range `[start, end)` of the body under `== [heading]`, or null.
/// Comments and transcript segments share one line format, so they are told
/// apart by section only.
(int, int)? _section(List<String> lines, String heading) {
  final start = lines.indexWhere((l) => l.trim() == '== $heading');
  if (start < 0) return null;
  var end = start + 1;
  while (end < lines.length && !lines[end].startsWith('== ')) {
    end++;
  }
  return (start + 1, end);
}

List<AudioComment> _parseSection(String source, String heading) {
  final lines = source.split('\n');
  final range = _section(lines, heading);
  if (range == null) return const [];
  final out = <AudioComment>[];
  for (final line in lines.sublist(range.$1, range.$2)) {
    final m = _commentLine.firstMatch(line);
    if (m == null) continue;
    out.add((
      ms: (int.parse(m[1]!) * 60 + int.parse(m[2]!)) * 1000,
      text: _unescape(m[3]!),
    ));
  }
  out.sort((a, b) => a.ms.compareTo(b.ms));
  return out;
}

List<AudioComment> parseComments(String source) =>
    _parseSection(source, 'Comments');

/// Timestamped segments a transcription worker wrote under `== Transcript`.
List<AudioComment> parseTranscript(String source) =>
    _parseSection(source, 'Transcript');

/// A translation of the transcript, `== Translation <lang>`.
List<AudioComment> parseTranslation(String source, String lang) =>
    _parseSection(source, 'Translation $lang');

/// Languages that already have a `== Translation <lang>` section.
List<String> translationLangs(String source) => [
  for (final m in RegExp(
    r'^== Translation (\S+)\s*$',
    multiLine: true,
  ).allMatches(source))
    m[1]!,
];

/// Appends at the end of `== Comments` (section added if missing). Empty text
/// is a no-op.
String appendComment(String source, int ms, String text) {
  if (text.trim().isEmpty) return source;
  final line = _commentSource(ms, text);
  final lines = source.split('\n');
  final range = _section(lines, 'Comments');
  if (range == null) {
    final base = source.endsWith('\n') ? source : '$source\n';
    return '$base\n== Comments\n\n$line\n';
  }
  var at = range.$2;
  while (at > range.$1 && lines[at - 1].trim().isEmpty) {
    at--;
  }
  lines.insert(at, line);
  return lines.join('\n');
}

/// Removes the first comment line equal to this one; other lines are untouched.
String removeComment(String source, int ms, String text) {
  final target = _commentSource(ms, text);
  final lines = source.split('\n');
  final range = _section(lines, 'Comments');
  if (range == null) return source;
  final i = lines.indexWhere((l) => l.trim() == target, range.$1);
  if (i < 0 || i >= range.$2) return source;
  return (lines..removeAt(i)).join('\n');
}

/// Vault path of the first audio attachment in [source], or null.
String? audioPathOf(String source) {
  final m = RegExp(
    r'#tylog\.attachment\(\s*"((?:\\.|[^"])*)"\s*,\s*kind:\s*"audio"',
  ).firstMatch(source);
  if (m == null) return null;
  final path = m[1]!.replaceAll(r'\"', '"').replaceAll(r'\\', r'\');
  return path.replaceFirst(RegExp(r'^/+'), '');
}

/// Body appended to a freshly created `= Title` page. [from] links back to
/// the note whose audio chip first opened this recording (a lesson, say).
String audioNoteBody(
  String assetPath,
  String label, {
  String? fromId,
  String? fromTitle,
}) =>
    '\n#tylog.attachment("/$assetPath", kind: "audio")[${escapeMarkup(label)}]\n'
    '${fromId == null ? '' : '\nFrom: #tylog.ref-note("${fromId.replaceAll('"', '')}")[${escapeMarkup(fromTitle ?? fromId)}]\n'}'
    '\n== Comments\n';
