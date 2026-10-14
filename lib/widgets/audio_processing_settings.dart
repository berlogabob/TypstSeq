import 'dart:async';

import 'package:flutter/material.dart';

import '../ai/ai_settings.dart';
import '../audio/processing_policy.dart';
import 'ai_connections_settings.dart';
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
    this.readAi,
    this.writeAi,
    this.readWorkers,
  });

  final Future<AudioPolicy> Function() read;
  final Future<void> Function(AudioPolicy) write;
  final Future<void> Function() processNow;
  final Future<AiSettings> Function()? readAi;
  final Future<void> Function(AiSettings)? writeAi;
  final Future<List<WorkerStatus>> Function()? readWorkers;

  @override
  State<AudioProcessingSettings> createState() =>
      _AudioProcessingSettingsState();
}

class _AudioProcessingSettingsState extends State<AudioProcessingSettings> {
  AudioPolicy? _policy;
  bool _busy = false;
  AiSettings? _ai;
  List<WorkerStatus> _workers = const [];
  Timer? _workerTimer;
  bool _aiBusy = false;
  final _discoveredModels = <String, List<String>>{};

  bool get _aiEnabled => widget.readAi != null && widget.writeAi != null;

  @override
  void initState() {
    super.initState();
    if (_aiEnabled) {
      unawaited(_loadAi());
      unawaited(_refreshWorkers());
      _workerTimer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => unawaited(_refreshWorkers()),
      );
    }
    unawaited(
      widget.read().then((p) {
        if (mounted) setState(() => _policy = p);
      }),
    );
  }

  @override
  void dispose() {
    _workerTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadAi() async {
    try {
      final settings = await widget.readAi!();
      if (mounted) setState(() => _ai = settings);
    } catch (error) {
      if (mounted) showSnack(context, 'Could not load AI settings: $error');
    }
  }

  Future<void> _refreshWorkers() async {
    final read = widget.readWorkers;
    if (read == null) return;
    try {
      final workers = await read();
      if (mounted) setState(() => _workers = workers);
    } catch (_) {
      // Keep the last heartbeat if storage is temporarily unavailable.
    }
  }

  Future<void> _saveAi(AiSettings next) async {
    final previous = _ai;
    setState(() {
      _ai = next;
      _aiBusy = true;
    });
    try {
      await widget.writeAi!(next);
    } catch (error) {
      if (mounted) {
        setState(() => _ai = previous);
        showSnack(context, 'Could not save: $error');
      }
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  String _relativeTime(DateTime? seen, DateTime now) {
    if (seen == null) return 'an unknown time';
    final age = now.difference(seen);
    if (age.inMinutes < 1) return 'less than a minute';
    if (age.inHours < 1) {
      return '${age.inMinutes} minute${age.inMinutes == 1 ? '' : 's'}';
    }
    if (age.inDays < 1) {
      return '${age.inHours} hour${age.inHours == 1 ? '' : 's'}';
    }
    return '${age.inDays} day${age.inDays == 1 ? '' : 's'}';
  }

  Widget _workerStatus() {
    final now = DateTime.now();
    final online = _workers.where((worker) => worker.isOnline(now: now));
    final worker = online.firstOrNull ?? _workers.firstOrNull;
    final isOnline = worker?.isOnline(now: now) ?? false;
    return ListTile(
      leading: Icon(
        isOnline ? Icons.computer : Icons.computer_outlined,
        color: isOnline ? null : Theme.of(context).disabledColor,
      ),
      title: Text(
        worker == null
            ? 'No computer is processing yet. Start the TyLog worker on your computer.'
            : isOnline
            ? '${worker.host} online'
            : '${worker.host} last seen ${_relativeTime(worker.lastSeen, now)} ago (offline)',
      ),
    );
  }

  String? _serverStatus(AiSettings settings) {
    final connection = settings.translate.connection == null
        ? settings.connections.firstOrNull
        : settings.connections
              .where((c) => c.id == settings.translate.connection)
              .firstOrNull;
    if (connection == null) return null;
    final probes = _workers.where(
      (worker) => worker.connections.containsKey(connection.id),
    );
    final now = DateTime.now();
    final worker =
        probes.where((w) => w.isOnline(now: now)).firstOrNull ??
        probes.firstOrNull;
    if (worker == null) return null;
    final probe = worker.connections[connection.id]!;
    final label = connection.label.isEmpty ? connection.id : connection.label;
    return probe.reachable
        ? 'Server $label: reachable, loaded: ${probe.loaded.map((id) => id.split('/').last).join(', ')}'
        : 'Server $label: not reachable';
  }

  Map<String, ({bool reachable, List<String> loaded})> get _workerView {
    final now = DateTime.now();
    return {
      for (final worker in [
        ..._workers.where((w) => !w.isOnline(now: now)),
        ..._workers.where((w) => w.isOnline(now: now)),
      ])
        ...worker.connections,
    };
  }

  Widget _translationOverrides(AiSettings ai) {
    final task = ai.translate;
    final models = <String>{
      ...?_discoveredModels[task.connection],
      ...?_workerView[task.connection]?.loaded,
      if (task.model != null) task.model!,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          DropdownButtonFormField<String>(
            key: ValueKey(
              'server:${task.connection}:${ai.connections.map((c) => c.id).join('|')}',
            ),
            initialValue: ai.connections.any((c) => c.id == task.connection)
                ? task.connection
                : null,
            decoration: const InputDecoration(labelText: 'Server'),
            isExpanded: true,
            items: [
              const DropdownMenuItem(
                value: null,
                child: Text('Default (worker config)'),
              ),
              for (final connection in ai.connections)
                DropdownMenuItem(
                  value: connection.id,
                  child: Text(
                    connection.label.isEmpty ? connection.id : connection.label,
                  ),
                ),
            ],
            onChanged: _aiBusy
                ? null
                : (value) => unawaited(
                    _saveAi(
                      ai.copyWith(translate: task.copyWith(connection: value)),
                    ),
                  ),
          ),
          DropdownButtonFormField<String>(
            key: ValueKey(
              'model:${task.connection}:${task.model}:${task.quality}:${models.join('|')}',
            ),
            initialValue: task.model,
            decoration: const InputDecoration(labelText: 'Model'),
            isExpanded: true,
            items: [
              DropdownMenuItem(
                value: null,
                child: Text(
                  'Auto (${translateModelFor(task.copyWith(model: null))})',
                ),
              ),
              for (final model in models)
                DropdownMenuItem(value: model, child: Text(model)),
            ],
            onChanged: _aiBusy
                ? null
                : (value) => unawaited(
                    _saveAi(
                      ai.copyWith(translate: task.copyWith(model: value)),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _qualityRow({
    required String title,
    required AiTask task,
    required String model,
    required ValueChanged<String> onChanged,
    String? serverStatus,
  }) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title),
        const SizedBox(height: 4),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'fast', label: Text('Fast')),
            ButtonSegment(value: 'balanced', label: Text('Balanced')),
            ButtonSegment(value: 'best', label: Text('Best')),
          ],
          selected: {task.quality},
          onSelectionChanged: _aiBusy
              ? null
              : (values) => onChanged(values.single),
        ),
        Text(model, style: Theme.of(context).textTheme.bodySmall),
        if (serverStatus != null)
          Text(serverStatus, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );

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
        if (_aiEnabled) ...[
          _workerStatus(),
          if (_ai case final ai?) ...[
            AiConnectionsSection(
              settings: ai,
              workerView: _workerView,
              onChanged: (next) => unawaited(_saveAi(next)),
              onModelsChanged: (id, models) => setState(
                () => _discoveredModels[id] = models.map((m) => m.id).toList(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Preset'),
                  const SizedBox(height: 4),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'light',
                        label: Text('Light'),
                        tooltip: 'small + 9b models, fast',
                      ),
                      ButtonSegment(
                        value: 'best',
                        label: Text('Best'),
                        tooltip: 'large models',
                      ),
                      ButtonSegment(
                        value: 'custom',
                        label: Text('Custom'),
                        enabled: false,
                      ),
                    ],
                    selected: {ai.preset?.name ?? 'custom'},
                    onSelectionChanged: _aiBusy
                        ? null
                        : (values) => unawaited(
                            _saveAi(
                              ai.withPreset(AiPreset.values.byName(values.single)),
                            ),
                          ),
                  ),
                  Text(
                    'Light: fastest. Best: most accurate. '
                    'Servers stay as you set them; model overrides reset.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            _qualityRow(
              title: 'Transcription quality',
              task: ai.transcribe,
              model: whisperModelFor(ai.transcribe),
              onChanged: (quality) => unawaited(
                _saveAi(
                  ai.copyWith(
                    transcribe: ai.transcribe.copyWith(quality: quality),
                  ),
                ),
              ),
            ),
            _qualityRow(
              title: 'Translation quality',
              task: ai.translate,
              model: translateModelFor(ai.translate),
              serverStatus: _serverStatus(ai),
              onChanged: (quality) => unawaited(
                _saveAi(
                  ai.copyWith(
                    translate: ai.translate.copyWith(quality: quality),
                  ),
                ),
              ),
            ),
            _translationOverrides(ai),
          ],
        ],
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
