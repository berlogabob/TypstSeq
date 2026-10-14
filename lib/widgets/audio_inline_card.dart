import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../audio/audio_peaks.dart';
import 'audio_note_screen.dart' show WaveformSeekBar;
import 'audio_sheets.dart';

/// A note-body audio attachment as a player: waveform, play/pause and an
/// expand button that opens the full comment screen. The player is created on
/// the first play, so a journal full of recordings loads nothing up front.
class AudioInlineCard extends StatefulWidget {
  const AudioInlineCard({
    super.key,
    required this.label,
    required this.peaks,
    required this.readBytes,
    required this.extension,
    required this.onExpand,
    this.onPeaks,
  });

  final String label;
  final List<int> peaks;
  final Future<Uint8List> Function() readBytes;
  final String extension;
  final VoidCallback onExpand;

  /// Called with peaks decoded from the file when [peaks] was empty.
  final void Function(List<int> peaks, int durationMs)? onPeaks;

  @override
  State<AudioInlineCard> createState() => _AudioInlineCardState();
}

class _AudioInlineCardState extends State<AudioInlineCard> {
  AudioPlayer? _player;
  File? _temp;
  Future<void>? _loading;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  bool _busy = false;
  String? _error;
  final _subs = <StreamSubscription<Object?>>[];
  late List<int> _peaks = widget.peaks;

  @override
  void initState() {
    super.initState();
    if (_peaks.isEmpty) unawaited(_decodePeaks());
  }

  @override
  void didUpdateWidget(AudioInlineCard old) {
    super.didUpdateWidget(old);
    if (widget.peaks.isNotEmpty && widget.peaks != old.peaks) {
      _peaks = widget.peaks;
    }
  }

  /// A file without stored peaks (older recording, lesson mp3) gets its wave
  /// decoded once and handed back to be saved in its audio note.
  Future<void> _decodePeaks() async {
    try {
      await _ensure();
      final file = _temp;
      if (file == null || !mounted) return;
      final peaks = await peaksFromAudioFile(file);
      if (peaks.isEmpty || !mounted) return;
      setState(() => _peaks = peaks);
      widget.onPeaks?.call(peaks, _duration.inMilliseconds);
    } catch (_) {}
  }

  Future<void> _ensure() => _loading ??= () async {
    try {
      final file = await writeTempAudio(
        await widget.readBytes(),
        widget.extension,
      );
      _temp = file;
      final player = AudioPlayer();
      _player = player;
      _subs
        ..add(
          player
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
          player.durationStream.listen((d) {
            if (mounted) setState(() => _duration = d ?? Duration.zero);
          }),
        )
        ..add(
          player.playerStateStream.listen((s) {
            if (!mounted) return;
            setState(
              () => _playing =
                  s.playing && s.processingState != ProcessingState.completed,
            );
          }),
        );
      await player.setFilePath(file.path);
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not load audio');
      _loading = null;
    }
  }();

  Future<void> _toggle() async {
    setState(() => _busy = true);
    await _ensure();
    if (mounted) setState(() => _busy = false);
    final player = _player;
    if (player == null) return;
    if (_playing) {
      await player.pause();
    } else {
      if (player.processingState == ProcessingState.completed) {
        await player.seek(Duration.zero);
      }
      unawaited(player.play());
    }
  }

  Future<void> _seek(double fraction) async {
    await _ensure();
    final ms = (_duration.inMilliseconds * fraction).round();
    await _player?.seek(Duration(milliseconds: ms));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    unawaited(_player?.dispose());
    unawaited(_temp?.delete().then((_) {}, onError: (_) {}) ?? Future.value());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progress = _duration.inMilliseconds == 0
        ? 0.0
        : (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
        child: Row(
          children: [
            IconButton.filled(
              tooltip: _playing ? 'Pause' : 'Play',
              onPressed: _toggle,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(_playing ? Icons.pause : Icons.play_arrow),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  WaveformSeekBar(
                    peaks: _peaks,
                    progress: progress,
                    markers: const [],
                    height: 48,
                    onSeek: (f) => unawaited(_seek(f)),
                  ),
                  Text(
                    _error ??
                        (_duration == Duration.zero
                            ? widget.label
                            : '${formatClock(_position)} / ${formatClock(_duration)}'),
                    style: Theme.of(context).textTheme.labelSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Comments and transcript',
              onPressed: widget.onExpand,
              icon: const Icon(Icons.open_in_full),
            ),
          ],
        ),
      ),
    );
  }
}
