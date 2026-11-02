import 'dart:convert';

import 'package:tylog_audio/tylog_audio.dart' show formatTimestamp;
import 'package:tylog_core/values.dart' show escapeMarkup;

import '../models.dart';
import '../workspace_controller.dart';
import 'audio_note_doc.dart';

enum AudioExportFormat { markdown, pdf }

/// Copy and export use the same ordering, including same-second segments.
List<String> audioTextLines(
  List<AudioComment> rows, {
  List<AudioComment> parallel = const [],
}) {
  final lines =
      [
        for (var i = 0; i < rows.length; i++) (segment: rows[i], order: i * 2),
        for (var i = 0; i < parallel.length; i++)
          (segment: parallel[i], order: i * 2 + 1),
      ]..sort((a, b) {
        final time = a.segment.ms.compareTo(b.segment.ms);
        return time != 0 ? time : a.order.compareTo(b.order);
      });
  return [
    for (final line in lines)
      '${formatTimestamp(line.segment.ms)} ${parseTranscriptText(line.segment.text).text}',
  ];
}

String _flat(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

String _typstText(String text) => escapeMarkup(
  _flat(text),
).replaceAllMapped(RegExp(r'[`<>/]'), (match) => '\\${match[0]}');

String _markdownText(String text) => _flat(text).replaceAllMapped(
  RegExp(r'[\\`*_{}\[\]<>()#+.!|>~-]'),
  (match) => '\\${match[0]}',
);

/// PDF uses standalone Typst with the same sections and text as Markdown.
String audioExportContent({
  required String title,
  required String source,
  required String? language,
  required List<String> lines,
  required AudioExportFormat format,
}) {
  final markdown = format == AudioExportFormat.markdown;
  final literal = markdown ? _markdownText : _typstText;
  final heading = markdown ? '#' : '=';
  final out = StringBuffer('$heading ${literal(title)}\n');
  for (final section in [
    ('Summary', audioTextLines(parseSummary(source, language))),
    ('Scenes', audioTextLines(parseScenes(source, language))),
    ('References', audioTextLines(parseReferences(source, language))),
    ('Text', lines),
  ]) {
    out.writeln('\n$heading$heading ${section.$1}\n');
    for (final line in section.$2) {
      out.writeln('- ${literal(line)}');
    }
  }
  return out.toString();
}

/// Resolve from disk as well as the index: a just-created page may not be
/// indexed yet. Existing text is never regenerated over the user's edits.
Future<String> createAudioTextPage(
  WorkspaceController workspace,
  NoteRef audio,
  String language,
  List<String> lines,
) async {
  final vault = workspace.vault;
  if (vault == null) throw StateError('No vault is open');
  final id = '${audio.id}-text-$language';
  final existing = workspace.index?.notes
      .where((note) => note.id == id)
      .firstOrNull;
  final knownPath = existing?.path ?? workspace.recentNotePaths[id];
  if (knownPath != null && await vault.storage.exists(knownPath)) {
    return knownPath;
  }
  final title = '${audio.title} (${language.toUpperCase()})';
  final safe = title.trim().replaceAll(RegExp(r'[\\/]'), '-');
  final path = 'notes/$safe.typ';
  if (await vault.storage.exists(path)) return path;
  if (workspace.vault != vault) throw StateError('Vault changed');
  final created = await workspace.createPage(title, kind: 'text', id: id);
  final saved = await workspace.mutateNote(
    created,
    (current) =>
        '$current\nFrom: #tylog.ref-note(${jsonEncode(audio.id)})[${_typstText(audio.title)}]\n\n'
        '${lines.map((line) => '- ${_typstText(line)}').join('\n')}\n',
  );
  if (!saved) throw StateError('Could not save text page');
  return created;
}
