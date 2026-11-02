import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:tylog_audio/tylog_audio.dart';

import 'package:tylog_core/scanner.dart'
    show NoteMetadataDraft, replaceNoteHeader, scanNote;

import 'app_icons.dart';
import '../audio/audio_info.dart';
import '../audio/audio_note_actions.dart';
import '../audio/audio_note_doc.dart';
import '../audio/audio_peaks.dart';
import '../audio/processing_policy.dart';
import '../models.dart';
import 'audio_sheets.dart';
import 'snack.dart';
import 'processing_screen.dart';
import 'constants.dart';
import 'text_note_widgets.dart';
export 'text_note_widgets.dart' show AudioLanguageBar, AudioTranscriptRow;

/// Sections of the expanded audio screen.
enum AudioTab { comments, transcribe, properties }

bool get waveformSupported => !Platform.isWindows;

/// Waveform with a played portion, comment dots and tap/drag seeking.
class WaveformSeekBar extends StatelessWidget {
  const WaveformSeekBar({
    super.key,
    required this.peaks,
    required this.progress,
    required this.markers,
    required this.onSeek,
    this.height = 96,
  });

  final double height;

  /// 0-255 bars; empty draws a flat placeholder (e.g. an imported mp3).
  final List<int> peaks;
  final double progress;

  /// Comment positions as fractions of the duration.
  final List<double> markers;
  final ValueChanged<double> onSeek;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, box) {
        void seek(double dx) => onSeek((dx / box.maxWidth).clamp(0.0, 1.0));
        return Semantics(
          label: 'Waveform',
          slider: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => seek(d.localPosition.dx),
            onHorizontalDragUpdate: (d) => seek(d.localPosition.dx),
            child: CustomPaint(
              size: Size(box.maxWidth, height),
              painter: _WaveformPainter(
                peaks: peaks,
                progress: progress,
                markers: markers,
                played: scheme.primary,
                rest: scheme.onSurfaceVariant.withValues(alpha: 0.35),
                dot: scheme.tertiary,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Bars to draw: always [count] of them, whatever the source resolution
/// (a 3 s take has 30 samples, an 11 s one 110), stretched so the quietest
/// bar is low and the loudest tall. A quiet take then looks like a loud one,
/// and an empty/flat source still draws a placeholder wave.
List<int> displayBars(List<int> peaks, {int count = 64}) {
  if (peaks.isEmpty) return List.filled(count, 40);
  final resampled = [
    for (var i = 0; i < count; i++)
      () {
        final a = i * peaks.length ~/ count;
        final b = math.max(a + 1, (i + 1) * peaks.length ~/ count);
        return peaks.sublist(a, math.min(b, peaks.length)).reduce(math.max);
      }(),
  ];
  final lo = resampled.reduce(math.min);
  final hi = resampled.reduce(math.max);
  if (hi - lo < 8) return List.filled(count, 110);
  return [for (final p in resampled) 40 + (p - lo) * 215 ~/ (hi - lo)];
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.peaks,
    required this.progress,
    required this.markers,
    required this.played,
    required this.rest,
    required this.dot,
  });

  final List<int> peaks;
  final double progress;
  final List<double> markers;
  final Color played;
  final Color rest;
  final Color dot;

  @override
  void paint(Canvas canvas, Size size) {
    final bars = displayBars(peaks);
    final slot = size.width / bars.length;
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = (slot * 0.6).clamp(1.0, 6.0);
    final mid = size.height / 2 + 6;
    for (var i = 0; i < bars.length; i++) {
      final x = slot * (i + 0.5);
      final h = (bars[i] / 255 * (size.height - 20)).clamp(3.0, size.height);
      paint.color = x / size.width <= progress ? played : rest;
      canvas.drawLine(Offset(x, mid - h / 2), Offset(x, mid + h / 2), paint);
    }
    final head = Paint()
      ..color = played
      ..strokeWidth = 2;
    final hx = progress.clamp(0.0, 1.0) * size.width;
    canvas.drawLine(Offset(hx, 10), Offset(hx, size.height), head);
    final dotPaint = Paint()..color = dot;
    for (final m in markers) {
      canvas.drawCircle(
        Offset(m.clamp(0.0, 1.0) * size.width, 5),
        3.5,
        dotPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.progress != progress ||
      old.peaks != peaks ||
      old.markers != markers ||
      old.played != played;
}

/// Context written by the worker, with the same seek targets as transcript rows.
class AudioNoteSections extends StatefulWidget {
  const AudioNoteSections({
    super.key,
    required this.summary,
    required this.scenes,
    required this.references,
    required this.onSeek,
  });

  final List<AudioComment> summary;
  final List<AudioComment> scenes;
  final List<AudioComment> references;
  final ValueChanged<int> onSeek;

  @override
  State<AudioNoteSections> createState() => _AudioNoteSectionsState();
}

class _AudioNoteSectionsState extends State<AudioNoteSections> {
  bool _summaryExpanded = false;

  @override
  Widget build(BuildContext context) {
    final summary = widget.summary.map((c) => c.text).join('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.summary.isNotEmpty)
          ExpansionTile(
            title: const Text('Summary'),
            subtitle: _summaryExpanded
                ? null
                : Text(summary, maxLines: 1, overflow: TextOverflow.ellipsis),
            onExpansionChanged: (v) => setState(() => _summaryExpanded = v),
            childrenPadding: const EdgeInsets.fromLTRB(
              kSpace16,
              0,
              kSpace16,
              kSpace8,
            ),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [Text(summary)],
          ),
        for (final section in [
          ('Scenes', widget.scenes),
          ('References', widget.references),
        ])
          if (section.$2.isNotEmpty)
            ExpansionTile(
              dense: true,
              title: Text('${section.$1} · ${section.$2.length}'),
              children: [
                for (final entry in section.$2)
                  ListTile(
                    dense: true,
                    leading: Text(formatTimestamp(entry.ms)),
                    title: Text(entry.text),
                    onTap: () => widget.onSeek(entry.ms),
                  ),
              ],
            ),
      ],
    );
  }
}

/// Player + timestamped comments for one `kind: audio` note.
class AudioNoteScreen extends StatefulWidget {
  const AudioNoteScreen({
    super.key,
    required this.note,
    required this.readSource,
    required this.readBytes,
    required this.writeBytes,
    required this.mutate,
    required this.transcriptStatus,
    required this.requestTranscript,
    this.transcriptLang,
    this.transcriptLangs,
    this.selectedLanguages = const [],
    this.translationStatus,
    this.requestTranslation,
    this.initialTab = AudioTab.comments,
    this.onChanged,
    this.waveformAvailable,
    this.onOpenProcessing,
    this.onExport,
    this.onOpenAsPage,
  });

  final AudioTab initialTab;
  final List<String> selectedLanguages;
  final Future<List<String>> Function(String audioPath)? transcriptLangs;

  /// Called after alias/tags are saved so the index and chips can refresh.
  final VoidCallback? onChanged;
  final VoidCallback? onOpenProcessing;
  final Future<void> Function(
    String title,
    String content,
    AudioExportFormat format,
  )?
  onExport;
  final Future<void> Function(String language, List<String> lines)?
  onOpenAsPage;
  final bool? waveformAvailable;

  final NoteRef note;
  final Future<String> Function(String path) readSource;
  final Future<Uint8List> Function(String path) readBytes;
  final Future<void> Function(String path, List<int> bytes) writeBytes;
  final Future<bool> Function(String path, String Function(String) transform)
  mutate;

  /// Job status for this audio file (queued, processing, done, failed) or null.
  final Future<String?> Function(String audioPath) transcriptStatus;

  /// Queues a transcription job for a worker; see docs/audio-transcription.md.
  /// Also used by Re-process, so a completed job must be allowed to queue again.
  final Future<void> Function(String audioPath, String notePath)
  requestTranscript;

  /// Language the worker detected while transcribing (ISO code), if known.
  final Future<String?> Function(String audioPath)? transcriptLang;

  /// Status of the translation job into [target], or null.
  final Future<String?> Function(String audioPath, String target)?
  translationStatus;

  /// Queues a translation of the existing transcript into [target].
  final Future<void> Function(
    String audioPath,
    String notePath,
    String target,
    String sourceLang,
    List<String> sourceLangs,
  )?
  requestTranslation;

  @override
  State<AudioNoteScreen> createState() => _AudioNoteScreenState();
}

class _AudioNoteScreenState extends State<AudioNoteScreen> {
  static const _speeds = [0.75, 1.0, 1.25, 1.5];

  final _player = AudioPlayer();
  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  late List<int> _peaks = decodePeaks(widget.note.properties['peaks']);
  bool get _watching => _tab == AudioTab.transcribe;
  List<AudioComment> _transcript = const [];
  List<AudioComment> _summary = const [];
  List<AudioComment> _scenes = const [];
  List<AudioComment> _references = const [];
  String _source = '';
  bool _loadingSource = true;
  bool _parallel = true;
  bool _requestingTranscript = false;
  bool _sharing = false;
  String? _audioPath;
  String? _transcriptState;
  late AudioTab _tab = widget.initialTab;
  String? _lang;
  List<String> _langs = const [];
  String? _view; // selected language
  late List<String> _aliases = [...widget.note.aliases];
  late final List<String> _tags = [
    ...widget.note.tags.where((t) => t != widget.note.kind),
  ];
  late final Map<String, Object?> _props = {...widget.note.properties};
  final _aliasInput = TextEditingController();
  final _tagInput = TextEditingController();
  AudioInfo? _info;
  Map<String, List<AudioComment>> _translations = const {};
  final Map<String, String> _translating = {}; // target -> job status
  Timer? _poll;
  File? _temp;
  List<AudioComment> _comments = const [];
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  int? _pendingMs;
  double _speed = 1;
  String? _error;
  final _subs = <StreamSubscription<Object?>>[];

  @override
  void initState() {
    super.initState();
    _input.addListener(_capturePosition);
    _subs
      ..add(
        // The default stream ticks every 200 ms, which makes the playhead
        // visibly jump; ask for ~30 fps.
        _player
            .createPositionStream(
              steps: 1000,
              minPeriod: const Duration(milliseconds: 16),
              maxPeriod: const Duration(milliseconds: 33),
            )
            .listen((p) {
              if (mounted) setState(() => _position = p);
            }),
      )
      ..add(
        _player.durationStream.listen(
          (d) => setState(() => _duration = d ?? Duration.zero),
        ),
      );
    unawaited(_load());
    _poll = Timer.periodic(const Duration(seconds: 8), (_) => _tick());
  }

  bool get _waveformAvailable => widget.waveformAvailable ?? waveformSupported;

  bool get _jobsPending =>
      _transcriptState == 'queued' ||
      _transcriptState == 'processing' ||
      _translating.values.any((v) => v == 'queued' || v == 'processing') ||
      (widget.translationStatus != null &&
          _transcript.isNotEmpty &&
          {'ru', 'en', 'pt', ...widget.selectedLanguages}.any(
            (lang) =>
                lang != _lang &&
                !_translations.containsKey(lang) &&
                _translating[lang] != 'failed',
          ));

  void _tick() {
    if (mounted &&
        _watching &&
        (_jobsPending || (_transcriptState == 'done' && _transcript.isEmpty))) {
      unawaited(_reloadComments());
      unawaited(_refreshTranscriptState());
    }
  }

  /// SoundCloud-style: the comment lands where playback was when typing began.
  void _capturePosition() {
    if (_input.text.isEmpty) {
      if (_pendingMs != null) setState(() => _pendingMs = null);
    } else if (_pendingMs == null) {
      setState(() => _pendingMs = _position.inMilliseconds);
    }
  }

  Future<void> _load() async {
    try {
      final source = await widget.readSource(widget.note.path);
      if (!mounted) return;
      // The NoteRef we were opened with may be a stub (index still building);
      // the file is the truth, and later header rewrites must not drop it.
      final fresh = scanNote(widget.note.path, source);
      _aliases = [...fresh.aliases];
      _tags
        ..clear()
        ..addAll(
          fresh.tags.where((t) => t != fresh.kind),
        ); // kind is an implicit tag
      _props
        ..clear()
        ..addAll(fresh.properties);
      if (_peaks.isEmpty) _peaks = decodePeaks(_props['peaks']);
      final path = audioPathOf(source);
      if (path == null) throw StateError('No audio file in this note');
      setState(() {
        _audioPath = path;
        _applySource(source);
      });
      unawaited(_refreshTranscriptState());
      if (_waveformAvailable && _peaks.isEmpty) {
        _peaks = await readPeakSidecar(path, widget.readBytes);
      }
      final bytes = await widget.readBytes(path);
      final file = await writeTempAudio(bytes, path.split('.').last);
      _info = audioInfo(
        bytes,
        path.split('.').last,
        _props['duration_ms'] as int?,
      );
      _temp = file;
      await _player.setFilePath(file.path);
      if (mounted) setState(() {});
      if (_waveformAvailable && _peaks.isEmpty) unawaited(_backfillPeaks(file));
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not load audio: $error');
    }
  }

  /// Imported mp3/m4a files arrive without peaks: decode once, then keep them
  /// in a sidecar so the next open (and other devices) skip the work.
  Future<void> _backfillPeaks(File file) async {
    final peaks = await peaksFromAudioFile(file);
    if (peaks.isEmpty || !mounted) return;
    setState(() => _peaks = peaks);
    await writePeakSidecar(_audioPath!, peaks, widget.writeBytes);
  }

  /// Rewrites the note header from this screen's copy of the metadata.
  Future<void> _writeHeader() async {
    final n = widget.note;
    await widget.mutate(
      n.path,
      (cur) => replaceNoteHeader(
        cur,
        NoteMetadataDraft(
          id: n.id,
          title: n.title,
          kind: n.kind,
          project: n.project,
          date: n.date,
          tags: _tags,
          aliases: _aliases,
          properties: _props,
        ),
      ),
    );
  }

  Future<void> _saveMeta() async {
    await _writeHeader();
    widget.onChanged?.call();
    if (mounted) showSnack(context, 'Saved');
  }

  Future<void> _reloadComments() async {
    final source = await widget.readSource(widget.note.path);
    if (!mounted) return;
    setState(() => _applySource(source));
  }

  void _applySource(String source) {
    _source = source;
    _comments = parseComments(source);
    _transcript = parseTranscript(source);
    _translations = {
      for (final l in translationLangs(source)) l: parseTranslation(source, l),
    };
    _loadingSource = false;
    _selectView(_view);
  }

  void _selectView(String? lang) {
    _view = lang == _lang || _translations.containsKey(lang) ? lang : null;
    final selected = _view ?? _translations.keys.firstOrNull ?? _lang;
    _summary = parseSummary(_source, selected);
    _scenes = parseScenes(_source, selected);
    _references = parseReferences(_source, selected);
  }

  Future<void> _refreshTranscriptState() async {
    final path = _audioPath;
    if (path == null) return;
    final state = await widget.transcriptStatus(path);
    final langs = await widget.transcriptLangs?.call(path) ?? const <String>[];
    final lang = langs.isNotEmpty
        ? langs.first
        : await widget.transcriptLang?.call(path);
    final jobs = <String, String>{};
    final targets = {
      'ru',
      'en',
      'pt',
      ...widget.selectedLanguages,
      ..._translations.keys,
      ..._translating.keys,
    }..remove(lang);
    for (final target in targets) {
      final status = await widget.translationStatus?.call(path, target);
      final pending = status ?? _translating[target];
      if (pending != null && pending != 'done') jobs[target] = pending;
    }
    if (!mounted) return;
    final finished = _translating.keys.any((k) => !jobs.containsKey(k));
    setState(() {
      _transcriptState = state;
      _langs = langs;
      _lang = lang ?? _lang;
      _selectView(_view);
      _translating
        ..clear()
        ..addAll(jobs);
    });
    // The job finishing and the note arriving are separate sync events.
    if (finished || (state == 'done' && _transcript.isEmpty)) {
      unawaited(_reloadComments());
    }
  }

  Future<void> _requestTranslation(String target) async {
    final path = _audioPath;
    final lang = _lang;
    if (path == null || lang == null) return;
    await widget.requestTranslation?.call(
      path,
      widget.note.path,
      target,
      lang,
      _langs,
    );
    if (!mounted) return;
    setState(() => _translating[target] = 'queued');
    await _refreshTranscriptState();
    if (mounted) showProcessingQueued(context, widget.onOpenProcessing);
  }

  Future<void> _requestTranscript() async {
    final path = _audioPath;
    if (path == null || _requestingTranscript) return;
    setState(() => _requestingTranscript = true);
    try {
      await widget.requestTranscript(path, widget.note.path);
      await _refreshTranscriptState();
      if (mounted) {
        showProcessingQueued(context, widget.onOpenProcessing);
      }
    } catch (error) {
      if (mounted) {
        showSnack(context, 'Could not request transcription: $error');
      }
    } finally {
      if (mounted) setState(() => _requestingTranscript = false);
    }
  }

  Future<void> _addComment() async {
    final text = _input.text.trim();
    final ms = _pendingMs ?? _position.inMilliseconds;
    if (text.isEmpty) return;
    _input.clear();
    final ok = await widget.mutate(
      widget.note.path,
      (cur) => appendComment(cur, ms, text),
    );
    if (!mounted) return;
    if (!ok) showSnack(context, 'Could not save comment');
    await _reloadComments();
  }

  Future<void> _deleteComment(AudioComment c) async {
    await widget.mutate(
      widget.note.path,
      (cur) => removeComment(cur, c.ms, c.text),
    );
    if (mounted) await _reloadComments();
  }

  void _seek(Duration to) => _player.seek(
    Duration(
      milliseconds: to.inMilliseconds.clamp(0, _duration.inMilliseconds),
    ),
  );

  @override
  void dispose() {
    _poll?.cancel();
    _aliasInput.dispose();
    _tagInput.dispose();
    for (final s in _subs) {
      s.cancel();
    }
    _input.dispose();
    _inputFocus.dispose();
    unawaited(_player.dispose());
    unawaited(_temp?.delete().then((_) {}, onError: (_) {}) ?? Future.value());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalMs = _duration.inMilliseconds;
    final active = activeIndex(_comments, _position.inMilliseconds);
    return Scaffold(
      appBar: AppBar(
        title: Text(_aliases.isEmpty ? widget.note.title : _aliases.first),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Audio note menu',
            onSelected: (action) {
              if (action == 'copy') {
                unawaited(_showCopyAll());
              } else if (action == 'reprocess') {
                unawaited(_requestTranscript());
              } else if (action == 'export') {
                unawaited(_export());
              } else if (action == 'page') {
                unawaited(_openAsPage());
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'copy',
                enabled: _transcript.isNotEmpty || _translations.isNotEmpty,
                child: const Text('Copy all'),
              ),
              PopupMenuItem(
                value: 'export',
                enabled:
                    !_sharing &&
                    widget.onExport != null &&
                    (_transcript.isNotEmpty || _translations.isNotEmpty),
                child: const Text('Export…'),
              ),
              PopupMenuItem(
                value: 'page',
                enabled:
                    !_sharing &&
                    widget.onOpenAsPage != null &&
                    (_transcript.isNotEmpty || _translations.isNotEmpty),
                child: const Text('Open as page'),
              ),
              PopupMenuItem(
                value: 'reprocess',
                enabled:
                    _audioPath != null &&
                    !_requestingTranscript &&
                    _transcriptState != 'queued' &&
                    _transcriptState != 'processing',
                child: const Text('Re-process'),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: _error != null
            ? Center(child: Text(_error!))
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      kSpace16,
                      kSpace4,
                      kSpace16,
                      0,
                    ),
                    child: _waveformAvailable
                        ? WaveformSeekBar(
                            peaks: _peaks,
                            progress: totalMs == 0
                                ? 0
                                : _position.inMilliseconds / totalMs,
                            markers: [
                              if (totalMs > 0)
                                for (final c in _comments) c.ms / totalMs,
                            ],
                            height: 72,
                            onSeek: (f) => _seek(
                              Duration(milliseconds: (f * totalMs).round()),
                            ),
                          )
                        : LinearProgressIndicator(
                            value: totalMs == 0
                                ? 0
                                : _position.inMilliseconds / totalMs,
                            minHeight: 8,
                          ),
                  ),
                  _controls(),
                  const Divider(height: 1),
                  _tabBar(),
                  Expanded(
                    child: _loadingSource && _watching
                        ? const Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : switch (_tab) {
                            AudioTab.comments => _commentList(active),
                            AudioTab.transcribe => _transcribeView(),
                            AudioTab.properties => _propertiesView(),
                          },
                  ),
                  if (_tab == AudioTab.comments) _commentInput(),
                ],
              ),
      ),
    );
  }

  Widget _tabBar() {
    const tabs = {
      AudioTab.comments: (Icons.chat_bubble_outline, 'Comments'),
      AudioTab.transcribe: (Icons.subtitles_outlined, 'Text'),
      AudioTab.properties: (Icons.info_outline, 'Properties'),
    };
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kSpace8),
      child: Row(
        children: [
          for (final e in tabs.entries)
            Expanded(
              child: InkWell(
                onTap: () {
                  setState(() => _tab = e.key);
                  if (e.key != AudioTab.comments) {
                    unawaited(_reloadComments());
                    unawaited(_refreshTranscriptState());
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: kSpace8),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        width: 3,
                        color: _tab == e.key
                            ? scheme.primary
                            : Colors.transparent,
                      ),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Badge(
                        isLabelVisible:
                            e.key == AudioTab.comments && _comments.isNotEmpty,
                        label: Text('${_comments.length}'),
                        child: Icon(
                          e.value.$1,
                          color: _tab == e.key
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        e.value.$2,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: _tab == e.key
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// One row, three cells on a 16 px margin: time at the left edge (position
  /// over duration), back / play / forward on the centre axis, speed at the
  /// right edge. The side cells are equal, so play stays centred.
  Widget _controls() {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    const tabular = [FontFeature.tabularFigures()];
    return Padding(
      padding: const EdgeInsets.fromLTRB(kSpace16, 0, kSpace16, kSpace4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  formatClock(_position),
                  style: textTheme.labelLarge?.copyWith(fontFeatures: tabular),
                ),
                Text(
                  formatClock(_duration),
                  style: textTheme.labelMedium?.copyWith(
                    fontFeatures: tabular,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            iconSize: 28,
            tooltip: 'Back 10 s',
            icon: const Icon(Icons.replay_10),
            onPressed: () => _seek(_position - const Duration(seconds: 10)),
          ),
          const SizedBox(width: 4),
          StreamBuilder<PlayerState>(
            stream: _player.playerStateStream,
            builder: (context, snap) {
              final done =
                  snap.data?.processingState == ProcessingState.completed;
              final playing = (snap.data?.playing ?? false) && !done;
              return IconButton.filled(
                iconSize: 32,
                padding: const EdgeInsets.all(10),
                tooltip: playing ? 'Pause' : 'Play',
                icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                onPressed: () {
                  if (playing) {
                    _player.pause();
                  } else {
                    if (done) _player.seek(Duration.zero);
                    _player.play();
                  }
                },
              );
            },
          ),
          const SizedBox(width: 4),
          IconButton(
            iconSize: 28,
            tooltip: 'Forward 10 s',
            icon: const Icon(Icons.forward_10),
            onPressed: () => _seek(_position + const Duration(seconds: 10)),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonal(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(52, 32),
                  padding: const EdgeInsets.symmetric(horizontal: kSpace12),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () {
                  final next =
                      _speeds[(_speeds.indexOf(_speed) + 1) % _speeds.length];
                  setState(() => _speed = next);
                  _player.setSpeed(next);
                },
                child: Text('${_speed}x'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _commentList(int active) {
    if (_comments.isEmpty) {
      return const Center(child: Text('No comments yet'));
    }
    return ListView.builder(
      itemCount: _comments.length,
      itemBuilder: (context, i) {
        final c = _comments[i];
        return ListTile(
          dense: true,
          selected: i == active,
          leading: Text(formatTimestamp(c.ms)),
          title: Text(c.text),
          onTap: () => _seek(Duration(milliseconds: c.ms)),
          trailing: IconButton(
            tooltip: 'Delete comment',
            icon: const Icon(AppIcons.close, size: 18),
            onPressed: () => unawaited(_deleteComment(c)),
          ),
        );
      },
    );
  }

  Widget _transcribeView() {
    if (_transcript.isEmpty) {
      final waiting =
          _transcriptState == 'queued' || _transcriptState == 'processing';
      final done = _transcriptState == 'done';
      return Center(
        child: waiting
            ? Text('Transcription $_transcriptState…')
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    done
                        ? 'No speech found, or the transcript is still syncing'
                        : _transcriptState == 'failed'
                        ? 'Last transcription failed'
                        : 'No transcript yet',
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => unawaited(_requestTranscript()),
                    icon: const Icon(Icons.subtitles_outlined),
                    label: Text(
                      done ? 'Transcribe again' : 'Request transcription',
                    ),
                  ),
                ],
              ),
      );
    }
    final view = _view ?? _translations.keys.firstOrNull ?? _lang;
    final translation = view == _lang ? null : _translations[view];
    final shown = _parallel ? _transcript : translation ?? _transcript;
    final active = activeIndex(shown, _position.inMilliseconds);
    return Column(
      children: [
        AudioLanguageBar(
          selected: widget.selectedLanguages,
          original: null,
          sourceLanguage: _lang,
          translated: _translations.keys.toSet(),
          translating: _translating,
          view: view,
          onView: (l) => setState(() => _selectView(l)),
          onRequest: (l) => unawaited(_requestTranslation(l)),
          canRequest: widget.requestTranslation != null && _lang != null,
          parallel: _parallel,
          onParallelChanged: (v) => setState(() => _parallel = v),
        ),
        Expanded(
          child: _segments(
            shown,
            active,
            parallel: _parallel ? translation : null,
            showSections: true,
          ),
        ),
      ],
    );
  }

  Widget _segments(
    List<AudioComment> shown,
    int active, {
    List<AudioComment>? parallel,
    bool showSections = false,
  }) {
    final rows = [
      for (var i = 0; i < shown.length; i++)
        if (i == 0 ||
            !parseTranscriptText(shown[i].text).nonSpeech ||
            !parseTranscriptText(shown[i - 1].text).nonSpeech)
          i,
    ];
    return CustomScrollView(
      slivers: [
        if (showSections)
          SliverToBoxAdapter(
            child: AudioNoteSections(
              summary: _summary,
              scenes: _scenes,
              references: _references,
              onSeek: (ms) => _seek(Duration(milliseconds: ms)),
            ),
          ),
        SliverList.builder(
          itemCount: rows.length,
          itemBuilder: (context, row) {
            final i = rows[row];
            final end = row + 1 < rows.length ? rows[row + 1] : shown.length;
            return AudioTranscriptRow(
              segment: shown[i],
              translation:
                  parallel != null &&
                      i < parallel.length &&
                      parallel[i].ms == shown[i].ms
                  ? parallel[i].text
                  : null,
              active: i <= active && active < end,
              onTap: () => _seek(Duration(milliseconds: shown[i].ms)),
            );
          },
        ),
      ],
    );
  }

  Future<String?> _chooseText({bool allowParallel = true}) async {
    final transcript = _transcript;
    final translations = _translations;
    final target = _view != _lang && translations.containsKey(_view)
        ? _view
        : translations.keys.firstOrNull;
    return chooseNoteText(
      context,
      originalAvailable: transcript.isNotEmpty,
      languages: translations.keys,
      target: target,
      allowParallel: allowParallel,
    );
  }

  String? _textLanguage(String choice) => switch (choice) {
    'original' => _lang,
    'parallel' =>
      _view != _lang && _translations.containsKey(_view)
          ? _view
          : _translations.keys.firstOrNull,
    _ => choice,
  };

  List<String> _textLines(String choice) => audioTextLines(
    choice == 'original' || choice == 'parallel'
        ? _transcript
        : _translations[choice] ?? const [],
    parallel: choice == 'parallel'
        ? _translations[_textLanguage(choice)] ?? const []
        : const [],
  );

  Future<void> _showCopyAll() async {
    final choice = await _chooseText();
    if (choice == null || !mounted) return;
    await copyNoteText(context, _textLines(choice).join('\n'));
  }

  Future<void> _export() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final format = await showModalBottomSheet<AudioExportFormat>(
        context: context,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final format in AudioExportFormat.values)
                ListTile(
                  title: Text(
                    format == AudioExportFormat.markdown ? 'Markdown' : 'PDF',
                  ),
                  onTap: () => Navigator.pop(context, format),
                ),
            ],
          ),
        ),
      );
      if (format == null || !mounted) return;
      final choice = await _chooseText();
      if (choice == null || !mounted) return;
      await widget.onExport?.call(
        widget.note.title,
        audioExportContent(
          title: widget.note.title,
          source: _source,
          language: _textLanguage(choice),
          lines: _textLines(choice),
          format: format,
        ),
        format,
      );
    } catch (error) {
      if (mounted) showSnack(context, 'Could not export audio note: $error');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _openAsPage() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final choice = await _chooseText(allowParallel: false);
      if (choice == null || !mounted) return;
      await widget.onOpenAsPage?.call(
        _textLanguage(choice) ?? 'original',
        _textLines(choice),
      );
    } catch (error) {
      if (mounted) showSnack(context, 'Could not open text page: $error');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Widget _propertiesView() {
    final info = _info;
    Widget row(String k, String? v) => v == null
        ? const SizedBox.shrink()
        : ListTile(
            dense: true,
            title: Text(k),
            trailing: Text(v, style: Theme.of(context).textTheme.bodyMedium),
          );
    String mb(int b) => b < 1024 * 1024
        ? '${(b / 1024).toStringAsFixed(0)} KB'
        : '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
    return ListView(
      padding: const EdgeInsets.fromLTRB(kSpace16, kSpace8, kSpace16, kSpace24),
      children: [
        TextField(
          controller: _aliasInput,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: 'Alias',
            helperText: 'A name of your own; shown instead of the file name',
            suffixIcon: IconButton(
              tooltip: 'Save alias',
              icon: const Icon(Icons.check),
              onPressed: () {
                final v = _aliasInput.text.trim();
                setState(() => _aliases = v.isEmpty ? [] : [v]);
                unawaited(_saveMeta());
              },
            ),
          ),
          onSubmitted: (v) {
            final t = v.trim();
            setState(() => _aliases = t.isEmpty ? [] : [t]);
            unawaited(_saveMeta());
          },
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          children: [
            for (final t in _tags)
              InputChip(
                label: Text('#$t'),
                onDeleted: () {
                  setState(() => _tags.remove(t));
                  unawaited(_saveMeta());
                },
              ),
          ],
        ),
        TextField(
          controller: _tagInput,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(labelText: 'Add tag'),
          onSubmitted: (v) {
            final t = v.trim().replaceFirst(RegExp(r'^#'), '');
            _tagInput.clear();
            if (t.isEmpty || _tags.contains(t)) return;
            setState(() => _tags.add(t));
            unawaited(_saveMeta());
          },
        ),
        const SizedBox(height: 16),
        Text('File', style: Theme.of(context).textTheme.titleSmall),
        row('Format', info?.format),
        row('Duration', formatClock(_duration)),
        row('Size', info == null ? null : mb(info.bytes)),
        row(
          'Sample rate',
          info?.sampleRate == null
              ? null
              : '${(info!.sampleRate! / 1000).toStringAsFixed(info.sampleRate! % 1000 == 0 ? 0 : 1)} kHz',
        ),
        row(
          'Average bitrate',
          info?.bitrateKbps == null ? null : '${info!.bitrateKbps} kbps',
        ),
        row('Waveform', _peaks.isEmpty ? null : '${_peaks.length} samples'),
        row('Language', _lang == null ? null : _name(_lang!)),
        row('Audio file', _audioPath),
        row('Note', widget.note.path),
      ],
    );
  }

  String _name(String code) => kLanguageNames[code] ?? code;

  Widget _commentInput() => Padding(
    padding: EdgeInsets.fromLTRB(
      kSpace16,
      kSpace4,
      kSpace8,
      kSpace8 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: Row(
      children: [
        Expanded(
          child: TextField(
            controller: _input,
            focusNode: _inputFocus,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => unawaited(_addComment()),
            decoration: InputDecoration(
              hintText: _pendingMs == null
                  ? 'Comment at ${formatTimestamp(_position.inMilliseconds)}'
                  : 'Comment at ${formatTimestamp(_pendingMs!)}',
            ),
          ),
        ),
        IconButton(
          tooltip: 'Add comment',
          icon: const Icon(Icons.send),
          onPressed: () => unawaited(_addComment()),
        ),
      ],
    ),
  );
}

/// Index of the last comment at or before [positionMs], or -1.
int activeIndex(List<AudioComment> comments, int positionMs) {
  var active = -1;
  for (var i = 0; i < comments.length; i++) {
    if (comments[i].ms <= positionMs) active = i;
  }
  return active;
}
