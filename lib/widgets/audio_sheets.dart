import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:tylog_audio/tylog_audio.dart';

const _audioExtensions = ['.mp3', '.m4a', '.aac', '.wav', '.ogg', '.opus'];

bool isAudioPath(String path) {
  final lower = path.toLowerCase();
  return _audioExtensions.any(lower.endsWith);
}

/// ~16 kB/s AAC: 25 minutes stays under the 25 MB range where sync switches
/// to many chunks and a phone upload gets slow.
const kMaxRecordingSeconds = 25 * 60;

/// A finished take: an `.m4a` when the ADTS stream could be muxed, else the
/// raw `.aac`/`.wav` the recorder produced.
class AudioTake {
  const AudioTake(this.bytes, this.extension);
  final Uint8List bytes;
  final String extension;
}

AudioTake finishTake(Uint8List raw) {
  if (AudioNoteRecorder.extension == 'aac') {
    final m4a = m4aFromAdts(raw);
    if (m4a != null) return AudioTake(m4a, 'm4a');
  }
  return AudioTake(raw, AudioNoteRecorder.extension);
}

String formatClock(Duration d) {
  final m = d.inMinutes.toString().padLeft(2, '0');
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

/// Records until Stop; null when cancelled or the mic is denied.
Future<AudioTake?> showAudioRecorder(BuildContext context) {
  return showModalBottomSheet<AudioTake>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    builder: (_) => const _RecorderSheet(),
  );
}

class _RecorderSheet extends StatefulWidget {
  const _RecorderSheet();

  @override
  State<_RecorderSheet> createState() => _RecorderSheetState();
}

class _RecorderSheetState extends State<_RecorderSheet> {
  final _audio = AudioRecorder();
  late final AudioNoteRecorder _recorder = AudioNoteRecorder(_audio);
  Timer? _ticker;
  int _seconds = 0;
  double _level = 0; // 0..1
  String? _error;
  bool _stopping = false;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      // `record` asks the OS itself; no permission_handler Podfile macro to
      // forget (repsync's macOS build silently reports "denied" without it).
      if (!await _audio.hasPermission()) {
        if (mounted) setState(() => _error = 'Microphone access denied');
        return;
      }
      _recorder.onLevel = (db) {
        if (mounted) setState(() => _level = ((db + 60) / 60).clamp(0.0, 1.0));
      };
      await _recorder.start();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _seconds++);
        if (_seconds >= kMaxRecordingSeconds) unawaited(_stop());
      });
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not record: $error');
    }
  }

  Future<void> _stop() async {
    if (_stopping) return; // double-tap / cap timer racing a tap
    _stopping = true;
    _ticker?.cancel();
    final raw = await _recorder.stop();
    if (!mounted) return;
    // A take that doesn't parse as audio is discarded rather than saved.
    Navigator.pop(
      context,
      audioDurationMs(raw) == null ? null : finishTake(raw),
    );
  }

  Future<void> _cancel() async {
    _stopping = true;
    _ticker?.cancel();
    await _recorder.cancel();
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    unawaited(_audio.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null) ...[
              Text(_error!),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ] else ...[
              Text(
                formatClock(Duration(seconds: _seconds)),
                style: Theme.of(context).textTheme.displaySmall,
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(value: _level, color: scheme.primary),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton(onPressed: _cancel, child: const Text('Cancel')),
                  FilledButton.icon(
                    onPressed: _stop,
                    icon: const Icon(Icons.stop),
                    label: const Text('Save'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Plays [bytes] (read from the vault) via a cache-dir temp file: the vault
/// may be an Android SAF tree with no real path for just_audio to open.
Future<void> showAudioPlayer(
  BuildContext context, {
  required Uint8List bytes,
  required String title,
  required String extension,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) =>
        _PlayerSheet(bytes: bytes, title: title, extension: extension),
  );
}

class _PlayerSheet extends StatefulWidget {
  const _PlayerSheet({
    required this.bytes,
    required this.title,
    required this.extension,
  });
  final Uint8List bytes;
  final String title;
  final String extension;

  @override
  State<_PlayerSheet> createState() => _PlayerSheetState();
}

class _PlayerSheetState extends State<_PlayerSheet> {
  final _player = AudioPlayer();
  File? _temp;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/tylog-audio-${DateTime.now().microsecondsSinceEpoch}.${widget.extension}',
      );
      await file.writeAsBytes(widget.bytes, flush: true);
      _temp = file;
      await _player.setFilePath(file.path);
      unawaited(_player.play());
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not play: $error');
    }
  }

  @override
  void dispose() {
    unawaited(_player.dispose());
    unawaited(_temp?.delete().then((_) {}, onError: (_) {}) ?? Future.value());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.title, overflow: TextOverflow.ellipsis),
            if (_error != null)
              Text(_error!)
            else
              StreamBuilder<Duration?>(
                stream: _player.durationStream,
                builder: (context, durationSnap) {
                  final total = durationSnap.data ?? Duration.zero;
                  return StreamBuilder<Duration>(
                    stream: _player.positionStream,
                    builder: (context, positionSnap) {
                      final pos = positionSnap.data ?? Duration.zero;
                      final max = total.inMilliseconds.toDouble();
                      return Column(
                        children: [
                          Slider(
                            value: max <= 0
                                ? 0
                                : pos.inMilliseconds
                                      .clamp(0, total.inMilliseconds)
                                      .toDouble(),
                            max: max <= 0 ? 1 : max,
                            onChanged: (v) =>
                                _player.seek(Duration(milliseconds: v.round())),
                          ),
                          Text('${formatClock(pos)} / ${formatClock(total)}'),
                        ],
                      );
                    },
                  );
                },
              ),
            StreamBuilder<PlayerState>(
              stream: _player.playerStateStream,
              builder: (context, snap) {
                final state = snap.data;
                final playing = state?.playing ?? false;
                final done =
                    state?.processingState == ProcessingState.completed;
                return IconButton(
                  iconSize: 48,
                  icon: Icon(playing && !done ? Icons.pause : Icons.play_arrow),
                  onPressed: () {
                    if (done) {
                      _player.seek(Duration.zero);
                      _player.play();
                    } else if (playing) {
                      _player.pause();
                    } else {
                      _player.play();
                    }
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
