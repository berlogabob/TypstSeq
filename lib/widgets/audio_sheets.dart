import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:tylog_audio/tylog_audio.dart';
import 'ds/app_sheet.dart';

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
  const AudioTake(
    this.bytes,
    this.extension, [
    this.peaks = const [],
    this.durationMs,
  ]);
  final Uint8List bytes;
  final String extension;

  /// Waveform bars (0-255) measured while recording; empty when unknown.
  final List<int> peaks;

  /// Measured before muxing to m4a, which `audioDurationMs` can't read.
  final int? durationMs;
}

AudioTake finishTake(Uint8List raw, [List<int> peaks = const []]) {
  final ms = audioDurationMs(raw);
  if (AudioNoteRecorder.extension == 'aac') {
    final m4a = m4aFromAdts(raw);
    if (m4a != null) return AudioTake(m4a, 'm4a', peaks, ms);
  }
  return AudioTake(raw, AudioNoteRecorder.extension, peaks, ms);
}

/// Writes [bytes] to a cache-dir temp file for `just_audio`: the vault may be
/// an Android SAF tree with no real path to open.
Future<File> writeTempAudio(Uint8List bytes, String extension) async {
  final dir = await getTemporaryDirectory();
  final file = File(
    '${dir.path}/tylog-audio-${DateTime.now().microsecondsSinceEpoch}.$extension',
  );
  return file.writeAsBytes(bytes, flush: true);
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
    showDragHandle: false,
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
  final List<double> _recent = []; // 0..1, newest last
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
        if (!mounted) return;
        setState(() {
          _recent.add(((db + 60) / 60).clamp(0.0, 1.0));
          if (_recent.length > 60) _recent.removeAt(0);
        });
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
      audioDurationMs(raw) == null
          ? null
          : finishTake(raw, peaksFromLevels(_recorder.levels)),
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
    return AppSheet(
      title: 'Record audio',
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
            '${formatClock(Duration(seconds: _seconds))} / '
            '${formatClock(const Duration(seconds: kMaxRecordingSeconds))}',
            style: Theme.of(context).textTheme.displaySmall,
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 56,
            child: CustomPaint(
              size: const Size(double.infinity, 56),
              painter: _LiveWavePainter(_recent, scheme.primary),
            ),
          ),
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
    );
  }
}

/// Scrolling level history: the last ~6 s of the mic, newest on the right.
class _LiveWavePainter extends CustomPainter {
  _LiveWavePainter(this.levels, this.color);

  final List<double> levels;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final slot = size.width / 60;
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = (slot * 0.6).clamp(1.0, 6.0);
    final offset = 60 - levels.length;
    for (var i = 0; i < levels.length; i++) {
      final x = slot * (offset + i + 0.5);
      final h = (levels[i] * size.height).clamp(3.0, size.height);
      canvas.drawLine(
        Offset(x, size.height / 2 - h / 2),
        Offset(x, size.height / 2 + h / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_LiveWavePainter old) => true;
}
