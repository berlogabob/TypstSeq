import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../audio/audio_peaks.dart';
import 'audio_note_screen.dart' show AudioTab, WaveformSeekBar;
import 'audio_sheets.dart';
import 'constants.dart';

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
    this.readPeaks,
    this.status,
  });

  final String label;
  final List<int> peaks;
  final Future<Uint8List> Function() readBytes;
  final String extension;
  final Future<List<int>> Function()? readPeaks;

  /// Opens the full screen on [AudioTab]; completes when it is closed.
  final Future<void> Function(AudioTab tab) onExpand;

  /// Whether a transcript / translations exist, for the chip's status icons.
  final Future<({bool transcribed, bool translated, String? alias})> Function()?
  status;

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
  bool _transcribed = false;
  bool _translated = false;
  String? _alias;

  @override
  void initState() {
    super.initState();
    if (_peaks.isEmpty) unawaited(_decodePeaks());
    unawaited(_loadStatus());
  }

  Future<void> _loadStatus() async {
    try {
      final s = await widget.status?.call();
      if (s != null && mounted) {
        setState(() {
          _transcribed = s.transcribed;
          _translated = s.translated;
          _alias = s.alias;
        });
      }
    } catch (_) {}
  }

  Future<void> _expand(AudioTab tab) async {
    await widget.onExpand(tab);
    if (mounted) await _loadStatus();
  }

  @override
  void didUpdateWidget(AudioInlineCard old) {
    super.didUpdateWidget(old);
    if (widget.peaks.isNotEmpty && widget.peaks != old.peaks) {
      _peaks = widget.peaks;
    }
  }

  /// A file without stored peaks (older recording, lesson mp3) gets its wave
  /// decoded once and handed back to be saved in a sidecar.
  Future<void> _decodePeaks() async {
    try {
      final sidecar = await widget.readPeaks?.call() ?? const <int>[];
      if (!mounted) return;
      if (sidecar.isNotEmpty) {
        setState(() => _peaks = sidecar);
        return;
      }
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

  Widget _statusIcon(IconData icon, String name, bool done, AudioTab tab) {
    final scheme = Theme.of(context).colorScheme;
    return InkResponse(
      onTap: () => unawaited(_expand(tab)),
      radius: 18,
      child: Padding(
        padding: const EdgeInsets.only(left: kSpace8),
        child: Tooltip(
          message: done ? '$name ready' : 'No ${name.toLowerCase()} yet',
          child: Icon(
            icon,
            size: 18,
            color: done
                ? scheme.primary
                : scheme.onSurfaceVariant.withValues(alpha: 0.4),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progress = _duration.inMilliseconds == 0
        ? 0.0
        : (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0);
    final textTheme = Theme.of(context).textTheme;
    // File name without its extension: the extension is in Properties.
    final name = widget.label.replaceFirst(RegExp(r'\.[^.]+$'), '');
    // Quick-use chip: header line (name, alias, status icons; the whole line opens the screen) and one
    // line of play + waveform. Time, speed and everything else live in the
    // expanded screen. 4 dp grid: 12 side padding, 8 top/bottom, 8 gaps.
    return Card(
      margin: const EdgeInsets.symmetric(vertical: kSpace4),
      color: scheme.surfaceContainerHighest,
      clipBehavior: Clip.antiAlias,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: () => unawaited(_expand(AudioTab.comments)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(kSpace12, kSpace8, kSpace12, kSpace8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: () => unawaited(_expand(AudioTab.comments)),
                // Icons are pinned to the right edge in their own slot; name
                // and alias share the rest, so nothing shifts when the alias
                // loads, is long, or is absent.
                child: Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            flex: _alias == null ? 1 : 0,
                            fit: _alias == null ? FlexFit.tight : FlexFit.loose,
                            child: Text(
                              _error ?? name,
                              style: textTheme.labelMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_alias != null)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(left: kSpace8),
                                child: Text(
                                  _alias!,
                                  style: textTheme.titleSmall,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.end,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    _statusIcon(
                      Icons.subtitles_outlined,
                      'Transcript',
                      _transcribed,
                      AudioTab.transcribe,
                    ),
                    _statusIcon(
                      Icons.translate,
                      'Translation',
                      _translated,
                      AudioTab.translate,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  IconButton.filled(
                    style: IconButton.styleFrom(
                      minimumSize: const Size(40, 40),
                      padding: EdgeInsets.zero,
                    ),
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
                  const SizedBox(width: 12),
                  Expanded(
                    child: WaveformSeekBar(
                      peaks: _peaks,
                      progress: progress,
                      markers: const [],
                      height: 40,
                      onSeek: (f) => unawaited(_seek(f)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
