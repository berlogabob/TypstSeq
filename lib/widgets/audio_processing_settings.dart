import 'dart:async';

import 'package:flutter/material.dart';

import '../audio/processing_policy.dart';
import 'processing_policy_editor.dart';
import 'snack.dart';

/// Settings section: when audio is transcribed and which languages it is
/// translated into. Works on any platform because the policy file syncs; the
/// worker that obeys it runs on the computer.
class AudioProcessingSettings extends StatefulWidget {
  const AudioProcessingSettings({
    super.key,
    required this.read,
    required this.write,
    required this.processNow,
  });

  final Future<AudioPolicy> Function() read;
  final Future<void> Function(AudioPolicy) write;
  final Future<void> Function() processNow;

  @override
  State<AudioProcessingSettings> createState() =>
      _AudioProcessingSettingsState();
}

class _AudioProcessingSettingsState extends State<AudioProcessingSettings> {
  AudioPolicy? _policy;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(
      widget.read().then((p) {
        if (mounted) setState(() => _policy = p);
      }),
    );
  }

  Future<void> _save(AudioPolicy next) async {
    setState(() {
      _policy = next;
      _busy = true;
    });
    try {
      await widget.write(next);
    } catch (error) {
      if (mounted) showSnack(context, 'Could not save: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _processNow() async {
    try {
      await widget.processNow();
      if (mounted) showSnack(context, 'Requested');
    } catch (error) {
      if (mounted) showSnack(context, '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _policy;
    if (p == null) {
      return const ListTile(
        leading: Icon(Icons.graphic_eq),
        title: Text('Audio transcription'),
        subtitle: Text('Loading…'),
      );
    }
    return ProcessingPolicyEditor(
      icon: Icons.graphic_eq,
      title: 'Audio: transcribe and translate',
      onTheFly: p.onTheFly,
      scheduled: p.scheduled,
      time: p.time,
      busy: _busy,
      status:
          'Done by the worker on your computer. Anything you request '
          'by hand in the audio screen runs at once.',
      onChanged: (fly, sched, time) =>
          _save(p.copyWith(onTheFly: fly, scheduled: sched, time: time)),
      onProcessNow: () => unawaited(_processNow()),
      extras: [
        CheckboxListTile(
          value: p.transcribe,
          title: const Text('Transcribe automatically'),
          onChanged: _busy ? null : (v) => _save(p.copyWith(transcribe: v)),
        ),
        CheckboxListTile(
          value: p.translate,
          title: const Text('Translate automatically'),
          onChanged: _busy ? null : (v) => _save(p.copyWith(translate: v)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Full text in each of these languages',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Wrap(
                spacing: 8,
                children: [
                  for (final l in p.translateTo)
                    InputChip(
                      label: Text(kLanguageNames[l] ?? l),
                      onDeleted: () => _save(
                        p.copyWith(
                          translateTo: p.translateTo
                              .where((v) => v != l)
                              .toList(),
                        ),
                      ),
                    ),
                  MenuAnchor(
                    menuChildren: [
                      for (final e in kLanguageNames.entries)
                        if (!p.translateTo.contains(e.key))
                          MenuItemButton(
                            onPressed: () => _save(
                              p.copyWith(
                                translateTo: [...p.translateTo, e.key],
                              ),
                            ),
                            child: Text(e.value),
                          ),
                    ],
                    builder: (context, controller, child) => ActionChip(
                      avatar: const Icon(Icons.add),
                      label: const Text('Add language'),
                      onPressed: () => controller.isOpen
                          ? controller.close()
                          : controller.open(),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}
