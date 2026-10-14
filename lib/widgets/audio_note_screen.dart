import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:tylog_audio/tylog_audio.dart';

import 'package:tylog_core/scanner.dart'
    show NoteMetadataDraft, replaceNoteHeader, scanNote;

import '../audio/audio_info.dart';
import '../audio/audio_note_doc.dart';
import '../audio/audio_peaks.dart';
import '../audio/processing_policy.dart';
import '../models.dart';
import 'audio_sheets.dart';
import 'snack.dart';

/// Sections of the expanded audio screen.
enum AudioTab { comments, transcribe, translate, properties }

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

/// Language choices and translation requests for an audio transcript.
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
  });

  final List<String> selected;
  final String? original;
  final Set<String> translated;
  final Map<String, String> translating;
  final String? view;
  final ValueChanged<String> onView;
  final ValueChanged<String> onRequest;
  final bool canRequest;

  String _name(String code) => kLanguageNames[code] ?? code;

  @override
  Widget build(BuildContext context) {
    final shown = {...selected, ...translated, ...translating.keys};
    final offered = kLanguageNames.keys.where((l) => !shown.contains(l));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: 8,
          children: [
            for (final l in shown)
              if ((original == l) || translated.contains(l))
                ChoiceChip(
                  label: Text(
                    original == l ? '${_name(l)} · original' : _name(l),
                  ),
                  selected: view == l,
                  onSelected: (_) => onView(l),
                )
              else if (translating.containsKey(l))
                Chip(
                  avatar: translating[l] == 'failed'
                      ? const Icon(Icons.error_outline, size: 18)
                      : const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                  label: Text(
                    translating[l] == 'failed'
                        ? '${_name(l)} failed'
                        : _name(l),
                  ),
                  onDeleted: canRequest && translating[l] == 'failed'
                      ? () => onRequest(l)
                      : null,
                  deleteIcon: const Icon(Icons.refresh, size: 18),
                )
              else
                ActionChip(
                  avatar: const Icon(Icons.add),
                  label: Text(_name(l)),
                  onPressed: canRequest ? () => onRequest(l) : null,
                ),
            if (canRequest && offered.isNotEmpty)
              PopupMenuButton<String>(
                tooltip: 'Translate',
                onSelected: onRequest,
                itemBuilder: (_) => [
                  for (final l in offered)
                    PopupMenuItem(value: l, child: Text(_name(l))),
                ],
                child: const Chip(
                  avatar: Icon(Icons.translate, size: 18),
                  label: Text('Translate'),
                ),
              ),
          ],
        ),
      ),
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
  });

  final AudioTab initialTab;
  final List<String> selectedLanguages;
  final Future<List<String>> Function(String audioPath)? transcriptLangs;

  /// Called after alias/tags are saved so the index and chips can refresh.
  final VoidCallback? onChanged;

  final NoteRef note;
  final Future<String> Function(String path) readSource;
  final Future<Uint8List> Function(String path) readBytes;
  final Future<bool> Function(String path, String Function(String) transform)
  mutate;

  /// Job status for this audio file (queued, processing, done, failed) or null.
  final Future<String?> Function(String audioPath) transcriptStatus;

  /// Queues a transcription job for a worker; see docs/audio-transcription.md.
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
  bool get _watching =>
      _tab == AudioTab.transcribe || _tab == AudioTab.translate;
  List<AudioComment> _transcript = const [];
  String? _audioPath;
  String? _transcriptState;
  late AudioTab _tab = widget.initialTab;
  String? _lang;
  List<String> _langs = const [];
  bool get _monolingual => _langs.length <= 1;
  String? _view; // selected translation's language
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

  bool get _jobsPending =>
      _transcriptState == 'queued' ||
      _transcriptState == 'processing' ||
      _translating.values.any((v) => v == 'queued' || v == 'processing');

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
      final bytes = await widget.readBytes(path);
      final file = await writeTempAudio(bytes, path.split('.').last);
      _info = audioInfo(
        bytes,
        path.split('.').last,
        _props['duration_ms'] as int?,
      );
      _temp = file;
      _audioPath = path;
      await _player.setFilePath(file.path);
      if (mounted) {
        setState(() {
          _applySource(source);
        });
      }
      unawaited(_refreshTranscriptState());
      if (_peaks.isEmpty) unawaited(_backfillPeaks(file));
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not load audio: $error');
    }
  }

  /// Imported mp3/m4a files arrive without peaks: decode once, then keep them
  /// in the note header so the next open (and other devices) skip the work.
  Future<void> _backfillPeaks(File file) async {
    final peaks = await peaksFromAudioFile(file);
    if (peaks.isEmpty || !mounted) return;
    setState(() => _peaks = peaks);
    final ms = _duration.inMilliseconds;
    _props['peaks'] = encodePeaks(peaks);
    if (ms > 0 && _props['duration_ms'] == null) _props['duration_ms'] = ms;
    await _writeHeader();
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
    _comments = parseComments(source);
    _transcript = parseTranscript(source);
    _translations = {
      for (final l in translationLangs(source)) l: parseTranslation(source, l),
    };
    if (_view != null &&
        !_translations.containsKey(_view) &&
        !(_monolingual &&
            _view == _lang &&
            widget.selectedLanguages.contains(_lang))) {
      _view = null;
    }
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
    for (final target in _translating.keys.toList()) {
      final status = await widget.translationStatus?.call(path, target);
      if (status != null && status != 'done') jobs[target] = status;
    }
    if (!mounted) return;
    final finished = _translating.keys.any((k) => !jobs.containsKey(k));
    setState(() {
      _transcriptState = state;
      _langs = langs;
      _lang = lang ?? _lang;
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
    if (mounted) showSnack(context, 'Translation requested');
  }

  Future<void> _requestTranscript() async {
    final path = _audioPath;
    if (path == null) return;
    await widget.requestTranscript(path, widget.note.path);
    await _refreshTranscriptState();
    if (mounted) showSnack(context, 'Transcription requested');
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
      ),
      body: SafeArea(
        child: _error != null
            ? Center(child: Text(_error!))
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: WaveformSeekBar(
                      peaks: _peaks,
                      progress: totalMs == 0
                          ? 0
                          : _position.inMilliseconds / totalMs,
                      markers: [
                        if (totalMs > 0)
                          for (final c in _comments) c.ms / totalMs,
                      ],
                      height: 72,
                      onSeek: (f) =>
                          _seek(Duration(milliseconds: (f * totalMs).round())),
                    ),
                  ),
                  _controls(),
                  const Divider(height: 1),
                  _tabBar(),
                  Expanded(
                    child: switch (_tab) {
                      AudioTab.comments => _commentList(active),
                      AudioTab.transcribe => _transcribeView(),
                      AudioTab.translate => _translateView(),
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
      AudioTab.transcribe: (Icons.subtitles_outlined, 'Transcribe'),
      AudioTab.translate: (Icons.translate, 'Translate'),
      AudioTab.properties: (Icons.info_outline, 'Properties'),
    };
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
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
                  padding: const EdgeInsets.symmetric(vertical: 8),
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
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
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
                  padding: const EdgeInsets.symmetric(horizontal: 12),
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
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => unawaited(_deleteComment(c)),
          ),
        );
      },
    );
  }

  Widget _transcribeView() {
    if (_transcript.isEmpty) {
      final waiting =
          _transcriptState == 'queued' ||
          _transcriptState == 'processing' ||
          _transcriptState == 'done';
      return Center(
        child: waiting
            ? Text(
                _transcriptState == 'done'
                    ? 'Transcript ready, waiting for it to sync…'
                    : 'Transcription $_transcriptState…',
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _transcriptState == 'failed'
                        ? 'Last transcription failed'
                        : 'No transcript yet',
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => unawaited(_requestTranscript()),
                    icon: const Icon(Icons.subtitles_outlined),
                    label: const Text('Request transcription'),
                  ),
                ],
              ),
      );
    }
    final active = activeIndex(_transcript, _position.inMilliseconds);
    return Column(
      children: [
        if (_lang != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Language: ${_name(_lang!)}',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          ),
        Expanded(child: _segments(_transcript, active)),
      ],
    );
  }

  Widget _segments(List<AudioComment> shown, int active) => ListView.builder(
    itemCount: shown.length,
    itemBuilder: (context, i) => ListTile(
      dense: true,
      selected: i == active,
      leading: Text(formatTimestamp(shown[i].ms)),
      title: Text(shown[i].text),
      onTap: () => _seek(Duration(milliseconds: shown[i].ms)),
    ),
  );

  Widget _translateView() {
    if (_transcript.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Transcribe the audio first'),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => setState(() => _tab = AudioTab.transcribe),
              child: const Text('Go to Transcribe'),
            ),
          ],
        ),
      );
    }
    final original =
        _monolingual &&
            _lang != null &&
            (widget.selectedLanguages.contains(_lang) ||
                _translations.containsKey(_lang))
        ? _lang
        : null;
    final view =
        _view != null && (_view == original || _translations.containsKey(_view))
        ? _view
        : original ?? (_translations.isEmpty ? null : _translations.keys.first);
    final shown = view == original && original != null
        ? _transcript
        : _translations[view];
    return Column(
      children: [
        AudioLanguageBar(
          selected: widget.selectedLanguages,
          original: original,
          translated: _translations.keys.toSet(),
          translating: _translating,
          view: view,
          onView: (l) => setState(() => _view = l),
          onRequest: (l) => unawaited(_requestTranslation(l)),
          canRequest: widget.requestTranslation != null && _lang != null,
        ),
        Expanded(
          child: shown == null
              ? const Center(child: Text('Pick a language to translate into'))
              : _segments(shown, activeIndex(shown, _position.inMilliseconds)),
        ),
      ],
    );
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
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
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
      16,
      4,
      8,
      8 + MediaQuery.viewInsetsOf(context).bottom,
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
