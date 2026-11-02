import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:tylog_audio/tylog_audio.dart' show formatTimestamp;

import '../audio/audio_note_doc.dart';
import '../audio/processing_policy.dart' show kLanguageNames;
import 'constants.dart';
import 'snack.dart';

Future<void> copyNoteText(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) showSnack(context, 'Copied');
}

/// Language choices and translation retries for an audio transcript.
class AudioLanguageBar extends StatelessWidget {
  const AudioLanguageBar({
    super.key,
    required this.selected,
    required this.original,
    required this.translated,
    required this.translating,
    required this.view,
    required this.onView,
    required this.onRequest,
    required this.canRequest,
    this.requestMissing = false,
    this.sourceLanguage,
    this.parallel,
    this.onParallelChanged,
  });

  final List<String> selected;
  final String? original;
  final String? sourceLanguage;
  final Set<String> translated;
  final Map<String, String> translating;
  final String? view;
  final ValueChanged<String> onView;
  final ValueChanged<String> onRequest;
  final bool canRequest;
  final bool requestMissing;
  final bool? parallel;
  final ValueChanged<bool>? onParallelChanged;

  @override
  Widget build(BuildContext context) {
    final shown = {
      'ru',
      'en',
      'pt',
      ...selected,
      ...translated,
      ...translating.keys,
    };
    final requestable = {
      for (final language in shown)
        if (canRequest &&
            (translating[language] == 'failed' ||
                (requestMissing &&
                    translating[language] != 'queued' &&
                    translating[language] != 'processing')))
          language,
    };
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: kSpace12,
        vertical: kSpace4,
      ),
      child: Row(
        spacing: 8,
        children: [
          if (parallel != null) ...[
            FilterChip(
              tooltip: 'Side by side',
              selected: parallel!,
              label: Icon(
                parallel! ? Icons.view_column : Icons.view_column_outlined,
                size: kIconSmall,
              ),
              showCheckmark: false,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onSelected: onParallelChanged,
            ),
            if (sourceLanguage != null)
              Tooltip(
                message: 'Original',
                child: ChoiceChip(
                  label: Text(sourceLanguage!.toUpperCase()),
                  selected: view == sourceLanguage,
                  onSelected: (_) => onView(sourceLanguage!),
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
          ],
          for (final l in shown.where(
            (l) => parallel == null || l != sourceLanguage,
          ))
            if ((original == l) || translated.contains(l))
              ChoiceChip(
                label: Text(l.toUpperCase()),
                selected: view == l,
                onSelected: (_) => onView(l),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                showCheckmark: false,
              )
            else if (l != sourceLanguage)
              Chip(
                // A removed delete action must not linger in its exit animation.
                key: ValueKey((l, requestable.contains(l))),
                avatar:
                    translating[l] == 'queued' || translating[l] == 'processing'
                    ? const SizedBox(
                        width: kIconSmall,
                        height: kIconSmall,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
                label: Text(l.toUpperCase()),
                onDeleted: requestable.contains(l) ? () => onRequest(l) : null,
                deleteButtonTooltipMessage: !requestable.contains(l)
                    ? null
                    : translating[l] == 'failed'
                    ? 'Retry ${l.toUpperCase()}'
                    : 'Translate to ${l.toUpperCase()}',
                deleteIcon: Icon(
                  requestMissing && translating[l] != 'failed'
                      ? Icons.translate
                      : Icons.refresh,
                  size: kIconSmall,
                ),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
        ],
      ),
    );
  }
}

/// One seek target shared by the original line and its optional translation.
class AudioTranscriptRow extends StatelessWidget {
  const AudioTranscriptRow({
    super.key,
    required this.segment,
    required this.onTap,
    this.translation,
    this.active = false,
    this.showTimestamp = true,
  });

  final AudioComment segment;
  final String? translation;
  final bool active;
  final bool showTimestamp;
  final VoidCallback onTap;

  Widget _text(BuildContext context, String source, {bool muted = false}) {
    final parsed = parseTranscriptText(source);
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    final style = theme.textTheme.bodyMedium?.copyWith(
      color: muted || parsed.doubtful || parsed.nonSpeech || parsed.untranslated
          ? color
          : null,
      fontStyle: parsed.untranslated ? FontStyle.italic : null,
      decoration: parsed.doubtful ? TextDecoration.underline : null,
    );
    if (parsed.nonSpeech) {
      return Text(parsed.text, style: style);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (parsed.doubtful) ...[
          Tooltip(
            message: 'Doubtful text',
            child: Badge(
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              textColor: color,
              label: const Text('?'),
            ),
          ),
          const SizedBox(width: kSpace8),
        ],
        Expanded(child: Text(parsed.text, style: style)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final gap = parseTranscriptText(segment.text).nonSpeech;
    return ListTile(
      dense: true,
      selected: active,
      leading: !showTimestamp
          ? null
          : Text(
              formatTimestamp(segment.ms),
              style: gap
                  ? TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    )
                  : null,
            ),
      title: _text(context, segment.text),
      subtitle: translation == null || gap
          ? null
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onLongPress: () => unawaited(
                copyNoteText(context, parseTranscriptText(translation!).text),
              ),
              child: _text(context, translation!, muted: true),
            ),
      onTap: onTap,
      onLongPress: () => unawaited(
        copyNoteText(context, parseTranscriptText(segment.text).text),
      ),
    );
  }
}

/// Copy/page actions share the same original, translated and parallel choices.
Future<String?> chooseNoteText(
  BuildContext context, {
  required bool originalAvailable,
  required Iterable<String> languages,
  required String? target,
  bool allowParallel = true,
}) async {
  return showModalBottomSheet<String>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: const Text('Original'),
            enabled: originalAvailable,
            onTap: () => Navigator.pop(context, 'original'),
          ),
          for (final lang in languages)
            ListTile(
              title: Text(kLanguageNames[lang] ?? lang.toUpperCase()),
              onTap: () => Navigator.pop(context, lang),
            ),
          if (allowParallel)
            ListTile(
              title: const Text('Side by side'),
              subtitle: target == null
                  ? null
                  : Text(kLanguageNames[target] ?? target.toUpperCase()),
              enabled: target != null && originalAvailable,
              onTap: () => Navigator.pop(context, 'parallel'),
            ),
        ],
      ),
    ),
  );
}
