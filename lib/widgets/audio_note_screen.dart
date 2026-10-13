import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:tylog_audio/tylog_audio.dart';

import '../audio/audio_note_doc.dart';
import '../models.dart';
import 'audio_sheets.dart';
import 'snack.dart';

/// Waveform with a played portion, comment dots and tap/drag seeking.
class WaveformSeekBar extends StatelessWidget {
  const WaveformSeekBar({
    super.key,
    required this.peaks,
    required this.progress,
    required this.markers,
    required this.onSeek,
  });

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
              size: Size(box.maxWidth, 96),
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
    final bars = peaks.isEmpty ? List.filled(80, 40) : peaks;
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

/// Player + timestamped comments for one `kind: audio` note.
class AudioNoteScreen extends StatefulWidget {
  const AudioNoteScreen({
    super.key,
    required this.note,
    required this.readSource,
    required this.readBytes,
    required this.mutate,
  });

  final NoteRef note;
  final Future<String> Function(String path) readSource;
  final Future<Uint8List> Function(String path) readBytes;
  final Future<bool> Function(String path, String Function(String) transform)
  mutate;

  @override
  State<AudioNoteScreen> createState() => _AudioNoteScreenState();
}

class _AudioNoteScreenState extends State<AudioNoteScreen> {
  static const _speeds = [0.75, 1.0, 1.25, 1.5];

  final _player = AudioPlayer();
  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  late final List<int> _peaks = decodePeaks(widget.note.properties['peaks']);
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
      ..add(_player.positionStream.listen((p) => setState(() => _position = p)))
      ..add(
        _player.durationStream.listen(
          (d) => setState(() => _duration = d ?? Duration.zero),
        ),
      );
    unawaited(_load());
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
      final path = audioPathOf(source);
      if (path == null) throw StateError('No audio file in this note');
      final bytes = await widget.readBytes(path);
      final file = await writeTempAudio(bytes, path.split('.').last);
      _temp = file;
      await _player.setFilePath(file.path);
      if (mounted) setState(() => _comments = parseComments(source));
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not load audio: $error');
    }
  }

  Future<void> _reloadComments() async {
    final source = await widget.readSource(widget.note.path);
    if (mounted) setState(() => _comments = parseComments(source));
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
      appBar: AppBar(title: Text(widget.note.title)),
      body: SafeArea(
        child: _error != null
            ? Center(child: Text(_error!))
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: WaveformSeekBar(
                      peaks: _peaks,
                      progress: totalMs == 0
                          ? 0
                          : _position.inMilliseconds / totalMs,
                      markers: [
                        if (totalMs > 0)
                          for (final c in _comments) c.ms / totalMs,
                      ],
                      onSeek: (f) =>
                          _seek(Duration(milliseconds: (f * totalMs).round())),
                    ),
                  ),
                  Text('${formatClock(_position)} / ${formatClock(_duration)}'),
                  _controls(),
                  const Divider(height: 1),
                  Expanded(child: _commentList(active)),
                  _commentInput(),
                ],
              ),
      ),
    );
  }

  Widget _controls() => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      IconButton(
        tooltip: 'Back 10 s',
        icon: const Icon(Icons.replay_10),
        onPressed: () => _seek(_position - const Duration(seconds: 10)),
      ),
      StreamBuilder<PlayerState>(
        stream: _player.playerStateStream,
        builder: (context, snap) {
          final done = snap.data?.processingState == ProcessingState.completed;
          final playing = (snap.data?.playing ?? false) && !done;
          return IconButton.filled(
            iconSize: 40,
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
      IconButton(
        tooltip: 'Forward 10 s',
        icon: const Icon(Icons.forward_10),
        onPressed: () => _seek(_position + const Duration(seconds: 10)),
      ),
      TextButton(
        onPressed: () {
          final next = _speeds[(_speeds.indexOf(_speed) + 1) % _speeds.length];
          setState(() => _speed = next);
          _player.setSpeed(next);
        },
        child: Text('${_speed}x'),
      ),
    ],
  );

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
