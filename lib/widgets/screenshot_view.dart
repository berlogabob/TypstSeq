import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'constants.dart';
import '../audio/audio_note_doc.dart';
import 'text_note_widgets.dart';
import 'snack.dart';
import '../models.dart';
import 'screenshot_strip.dart';
import '../controlled_editor.dart' show localTime;

/// Section bodies of a screenshot note source: '== Description' and '== Text'
/// headings; Typst backslash escapes (\- \# \_ \* \\ etc.) are undone.
Map<String, String> screenshotSections(String source) {
  final lines = source.split('\n');
  final raw = <String, String>{};
  String? current;
  final buffer = <String>[];
  for (final line in lines) {
    if (line.startsWith('== ')) {
      if (current != null) {
        raw[current] = buffer.join('\n');
      }
      current = line.substring(3).trim();
      buffer.clear();
    } else if (current != null) {
      buffer.add(line);
    }
  }
  if (current != null) {
    raw[current] = buffer.join('\n');
  }
  final sections = <String, String>{};
  for (final entry in raw.entries) {
    final body = entry.value.trim();
    final unescaped = body.replaceAllMapped(
      RegExp(r'\\(.)'),
      (m) => m.group(1)!,
    );
    sections[entry.key] = unescaped;
  }
  return sections;
}

class ScreenshotView extends StatelessWidget {
  const ScreenshotView({
    super.key,
    required this.note,
    required this.source,
    required this.imageResolver,
    this.onEdit,
    this.onBack,
    this.readSource,
    this.translationJob,
    this.requestTranslation,
    this.onOpenAsPage,
  });
  final NoteRef note;
  final String source;
  final Future<Uint8List?> Function(String path) imageResolver;
  final VoidCallback? onEdit;
  final Future<String> Function()? readSource;
  final Future<Map<String, Object?>?> Function(String target)? translationJob;
  final Future<void> Function(String target, String sourceLanguage)?
  requestTranslation;
  final Future<void> Function(String language, List<String> lines)?
  onOpenAsPage;

  /// Shown as an arrow over the picture when this view fills the screen
  /// (read mode has no app bar of its own).
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final details = _detailsChildren(context);
    final body = LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 720) {
          return Row(
            // Full height: the picture is the main item.
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 2,
                child: _ScreenshotPicture(
                  key: const ValueKey('screenshot-picture'),
                  note: note,
                  imageResolver: imageResolver,
                ),
              ),
              VerticalDivider(width: 1),
              Expanded(
                flex: 3,
                child: ListView(
                  padding: EdgeInsets.all(kSpace16),
                  children: details,
                ),
              ),
            ],
          );
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            _ScreenshotPicture(
              key: const ValueKey('screenshot-picture'),
              note: note,
              imageResolver: imageResolver,
            ),
            DraggableScrollableSheet(
              key: const ValueKey('screenshot-details-sheet'),
              initialChildSize: 0.2,
              minChildSize: 0.12,
              maxChildSize: 0.9,
              snap: true,
              builder: (context, controller) {
                return Material(
                  color: scheme.surface,
                  elevation: 3,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(kRadiusSmall * 2),
                  ),
                  child: ListView(
                    controller: controller,
                    padding: EdgeInsets.all(kSpace16),
                    children: [
                      Center(
                        child: Container(
                          width: 32,
                          height: 4,
                          decoration: BoxDecoration(
                            color: scheme.outlineVariant,
                            borderRadius: BorderRadius.all(
                              Radius.circular(kRadiusSmall),
                            ),
                          ),
                        ),
                      ),
                      ...details,
                    ],
                  ),
                );
              },
            ),
          ],
        );
      },
    );
    if (onBack == null) return body;
    return Stack(
      fit: StackFit.expand,
      children: [
        body,
        SafeArea(
          child: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: EdgeInsets.all(kSpace8),
              child: IconButton.filledTonal(
                key: const ValueKey('screenshot-back'),
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back),
                onPressed: onBack,
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _detailsChildren(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final children = <Widget>[];

    final titleRow = Row(
      children: [
        Expanded(child: Text(note.title, style: textTheme.titleLarge)),
        if (onEdit != null)
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: onEdit,
          ),
      ],
    );
    children.add(titleRow);

    final captured = screenshotCapturedAt(note);
    final sourceApp = note.properties['source_app'];
    final metaParts = <String>[];
    if (captured != null) {
      metaParts.add(localTime(captured));
    }
    if (sourceApp != null) {
      metaParts.add(sourceApp.toString());
    }
    if (metaParts.isNotEmpty) {
      children.add(
        Padding(
          padding: EdgeInsets.only(top: kSpace4),
          child: Text(
            metaParts.join(' · '),
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    final keywords = note.properties['keywords'];
    final chips = keywords is List
        ? keywords.whereType<String>().toList()
        : const <String>[];
    if (chips.isNotEmpty) {
      children.add(
        Wrap(
          spacing: kSpace4,
          runSpacing: kSpace4,
          children: [for (final k in chips) Chip(label: Text(k))],
        ),
      );
    }

    final sections = screenshotSections(source);
    for (final name in ['Description']) {
      final body = sections[name];
      if (body == null || body.isEmpty) continue;
      children.add(
        Padding(
          padding: EdgeInsets.only(top: kSpace16),
          child: Text(name, style: textTheme.titleMedium),
        ),
      );
      children.add(SizedBox(height: kSpace8));
      children.add(SelectableText(body));
    }

    if (sections['Text']?.isNotEmpty ?? false) {
      children.add(
        ScreenshotTextView(
          key: ValueKey(note.path),
          source: source,
          readSource: readSource,
          translationJob: translationJob,
          requestTranslation: requestTranslation,
          onOpenAsPage: onOpenAsPage,
        ),
      );
    }
    return children;
  }
}

/// OCR and translations share the audio text controls, with line-order alignment.
class ScreenshotTextView extends StatefulWidget {
  const ScreenshotTextView({
    super.key,
    required this.source,
    this.readSource,
    this.translationJob,
    this.requestTranslation,
    this.onOpenAsPage,
  });

  final String source;
  final Future<String> Function()? readSource;
  final Future<Map<String, Object?>?> Function(String target)? translationJob;
  final Future<void> Function(String target, String sourceLanguage)?
  requestTranslation;
  final Future<void> Function(String language, List<String> lines)?
  onOpenAsPage;

  @override
  State<ScreenshotTextView> createState() => _ScreenshotTextViewState();
}

class _ScreenshotTextViewState extends State<ScreenshotTextView> {
  late String _source = widget.source;
  String? _language;
  String? _view;
  bool _parallel = true;
  bool _opening = false;
  bool _refreshing = false;
  int _generation = 0;
  final _statuses = <String, String>{};
  Timer? _poll;

  Map<String, List<AudioComment>> get _translations => {
    for (final lang in translationLangs(_source))
      lang: parseTranslation(_source, lang),
  };

  List<String> get _original => [
    for (final line in (screenshotSections(_source)['Text'] ?? '').split('\n'))
      if (line.trim().isNotEmpty) line.trim(),
  ];

  String get _sourceLanguage => _language ?? 'source';

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    _poll = Timer.periodic(const Duration(seconds: 8), (_) => _refresh());
  }

  @override
  void didUpdateWidget(ScreenshotTextView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.source != oldWidget.source) {
      _generation++;
      _source = widget.source;
    }
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    final generation = _generation;
    try {
      final jobs = <String, String>{};
      String? language;
      for (final target in {'ru', 'en', 'pt', ...translationLangs(_source)}) {
        final job = await widget.translationJob?.call(target);
        if (!mounted || generation != _generation) return;
        if (job?['status'] case final String status) jobs[target] = status;
        if (job?['lang'] case final String lang when lang != 'auto') {
          language = lang;
        }
      }
      final source = await widget.readSource?.call();
      if (!mounted || generation != _generation) return;
      setState(() {
        if (source != null) _source = source;
        final viewingSource = _view == _sourceLanguage;
        _language = language ?? _language;
        if (viewingSource) _view = _sourceLanguage;
        _statuses.addAll(jobs);
      });
    } catch (_) {
      // A sync replacement can be incomplete; keep the last visible snapshot.
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _request(String target) async {
    _generation++;
    setState(() => _statuses[target] = 'queued');
    try {
      await widget.requestTranslation?.call(target, _language ?? 'auto');
      if (mounted) unawaited(_refresh());
    } catch (error) {
      if (!mounted) return;
      setState(() => _statuses[target] = 'failed');
      showSnack(context, 'Could not request translation: $error');
    }
  }

  Future<void> _textAction(bool openPage) async {
    final translations = _translations;
    final original = _original;
    final target = translations.containsKey(_view)
        ? _view
        : translations.keys.firstOrNull;
    final choice = await chooseNoteText(
      context,
      originalAvailable: original.isNotEmpty,
      languages: translations.keys,
      target: target,
    );
    if (choice == null || !mounted) return;
    final language = choice == 'parallel' ? target! : choice;
    final translated = translations[language] ?? const <AudioComment>[];
    final lines = choice == 'original'
        ? original
        : choice == 'parallel'
        ? [
            for (
              var i = 0;
              i < original.length || i < translated.length;
              i++
            ) ...[
              if (i < original.length) original[i],
              if (i < translated.length)
                parseTranscriptText(translated[i].text).text,
            ],
          ]
        : translated
              .map((line) => parseTranscriptText(line.text).text)
              .toList();
    if (!openPage) {
      await copyNoteText(context, lines.join('\n'));
      return;
    }
    setState(() => _opening = true);
    try {
      await widget.onOpenAsPage?.call(
        choice == 'original' ? _sourceLanguage : language,
        lines,
      );
    } catch (error) {
      if (mounted) showSnack(context, 'Could not open text page: $error');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final translations = _translations;
    final view = _view ?? translations.keys.firstOrNull ?? _sourceLanguage;
    final translation = view == _sourceLanguage ? null : translations[view];
    final original = _original;
    final shown = _parallel || translation == null
        ? original
        : translation.map((line) => line.text).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Text',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Text menu',
              onSelected: (action) => unawaited(_textAction(action == 'page')),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'copy', child: Text('Copy all')),
                PopupMenuItem(
                  value: 'page',
                  enabled: !_opening && widget.onOpenAsPage != null,
                  child: const Text('Open as page'),
                ),
              ],
            ),
          ],
        ),
        AudioLanguageBar(
          selected: const [],
          original: null,
          sourceLanguage: _sourceLanguage,
          translated: translations.keys.toSet(),
          translating: _statuses,
          view: view,
          onView: (lang) => setState(() => _view = lang),
          onRequest: (lang) => unawaited(_request(lang)),
          canRequest: widget.requestTranslation != null,
          requestMissing: true,
          parallel: _parallel,
          onParallelChanged: (value) => setState(() => _parallel = value),
        ),
        for (var i = 0; i < shown.length; i++)
          AudioTranscriptRow(
            segment: (ms: 0, text: shown[i]),
            translation:
                _parallel && translation != null && i < translation.length
                ? translation[i].text
                : null,
            showTimestamp: false,
            onTap: () {},
          ),
      ],
    );
  }
}

/// Owns the image future so it is created exactly once and survives the many
/// page rebuilds that sync/index updates trigger.
class _ScreenshotPicture extends StatefulWidget {
  const _ScreenshotPicture({
    super.key,
    required this.note,
    required this.imageResolver,
  });
  final NoteRef note;
  final Future<Uint8List?> Function(String path) imageResolver;

  @override
  State<_ScreenshotPicture> createState() => _ScreenshotPictureState();
}

class _ScreenshotPictureState extends State<_ScreenshotPicture> {
  Future<Uint8List?>? _bytes;

  String? _path;

  void _load() {
    _path = screenshotAssetPath(widget.note);
    _bytes = _path == null ? null : widget.imageResolver(_path!);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_ScreenshotPicture old) {
    super.didUpdateWidget(old);
    // Same view reused for another screenshot: load its picture.
    if (screenshotAssetPath(widget.note) != _path) _load();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surfaceContainerHighest,
      child: InteractiveViewer(
        maxScale: 5,
        child: FutureBuilder<Uint8List?>(
          future: _bytes,
          builder: (context, snapshot) {
            final bytes = snapshot.data;
            if (bytes == null) {
              return const Center(
                child: Icon(Icons.image_not_supported_outlined),
              );
            }
            return Image.memory(
              bytes,
              fit: BoxFit.contain,
              gaplessPlayback: true,
            );
          },
        ),
      ),
    );
  }
}
