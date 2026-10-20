import 'dart:io';

import 'package:flutter/material.dart';

import '../ai/ai_settings.dart';
import '../ai/api_keys.dart';
import '../ai/connection_probe.dart' as connection_probe;
import '../ai/provider_presets.dart';
import 'ds/app_sheet.dart';
import 'dialogs.dart';
import 'constants.dart';

typedef ServerProbe =
    Future<connection_probe.ProbeResult> Function(
      String url, {
      String? key,
      String kind,
      HttpClient? client,
    });
typedef ModelTest =
    Future<connection_probe.ModelTestResult> Function(
      String url,
      String model, {
      String? key,
      String kind,
      HttpClient? client,
    });

class AiConnectionsSection extends StatefulWidget {
  const AiConnectionsSection({
    super.key,
    required this.settings,
    required this.onChanged,
    this.workerView = const {},
    this.probe = connection_probe.probeServer,
    this.testModel = connection_probe.testModel,
    this.onModelsChanged,
  });
  final AiSettings settings;
  final ValueChanged<AiSettings> onChanged;
  final Map<String, ({bool reachable, List<String> loaded})> workerView;
  final ServerProbe probe;
  final ModelTest testModel;
  final void Function(String id, List<connection_probe.ProbeModel> models)?
  onModelsChanged;

  @override
  State<AiConnectionsSection> createState() => _AiConnectionsSectionState();
}

class _AiConnectionsSectionState extends State<AiConnectionsSection> {
  final _probes = <String, connection_probe.ProbeResult>{};

  String _newId(String name) {
    final slug = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final base = slug.isEmpty ? 'server' : slug;
    var id = base;
    var suffix = 2;
    while (widget.settings.connections.any((c) => c.id == id)) {
      id = '$base-${suffix++}';
    }
    return id;
  }

  Future<void> _edit(AiConnection? connection, {ProviderPreset? preset}) async {
    connection_probe.ProbeResult? latest;
    String? latestUrl;
    final saved = await showModalBottomSheet<_ConnectionEdit>(
      context: context,
      showDragHandle: false,
      isScrollControlled: true,
      builder: (_) => _ConnectionEditor(
        connection: connection,
        preset: preset,
        initialProbe: connection == null ? null : _probes[connection.id],
        probe: widget.probe,
        testModel: widget.testModel,
        onProbe: (url, result) {
          latest = result;
          latestUrl = url;
          if (!mounted || connection == null || connection.url != url) return;
          setState(() => _probes[connection.id] = result);
          widget.onModelsChanged?.call(connection.id, result.models);
        },
        onDelete: connection == null
            ? null
            : () {
                _probes.remove(connection.id);
                widget.onModelsChanged?.call(connection.id, const []);
                widget.onChanged(
                  widget.settings.removeConnection(connection.id),
                );
              },
      ),
    );
    if (!mounted || saved == null) return;
    final next = saved.connection.id.isEmpty
        ? saved.connection.copyWith(id: _newId(saved.connection.label))
        : saved.connection;
    await writeApiKey(next.id, saved.apiKey);
    if (latest != null && latestUrl == next.url) {
      setState(() => _probes[next.id] = latest!);
      widget.onModelsChanged?.call(next.id, latest!.models);
    } else if (connection != null && connection.url != next.url) {
      setState(() => _probes.remove(next.id));
      widget.onModelsChanged?.call(next.id, const []);
    }
    widget.onChanged(widget.settings.upsertConnection(next));
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const ListTile(leading: Icon(Icons.dns_outlined), title: Text('Servers')),
      for (final cloud in [false, true])
        if (!cloud || widget.settings.connections.any((c) => c.cloud)) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(kSpace16, kSpace8, kSpace16, 0),
            child: Text(
              cloud ? 'Cloud (sends your text off-device)' : 'On this network',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          for (final connection in widget.settings.connections.where(
            (c) => c.cloud == cloud,
          ))
            ListTile(
              title: Text(
                connection.label.isEmpty ? connection.id : connection.label,
              ),
              subtitle: Text(connection.url),
              trailing: Icon(switch (_probes[connection.id]?.ok ??
                  widget.workerView[connection.id]?.reachable) {
                true => Icons.check_circle,
                false => Icons.error_outline,
                null => Icons.help_outline,
              }),
              onTap: () => _edit(connection),
            ),
        ],
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: kSpace16),
        child: PopupMenuButton<ProviderPreset>(
          tooltip: 'Add server',
          onSelected: (preset) =>
              _edit(null, preset: identical(preset, _other) ? null : preset),
          itemBuilder: (_) => [
            for (final preset in providerPresets)
              PopupMenuItem(
                value: preset,
                child: Text(
                  preset.cloud ? '${preset.label} (cloud)' : preset.label,
                ),
              ),
            const PopupMenuItem(value: _other, child: Text('Other server…')),
          ],
          child: const Chip(avatar: Icon(Icons.add), label: Text('Add server')),
        ),
      ),
    ],
  );
}

/// Menu entry for a server without a preset.
const _other = ProviderPreset('openai-compatible', '', '');

const _kinds = {
  'openai-compatible': 'OpenAI-compatible',
  'ollama': 'Ollama',
  'unsloth-studio': 'Unsloth Studio',
  'lm-studio': 'LM Studio',
  'anthropic': 'Anthropic',
};

class _ConnectionEditor extends StatefulWidget {
  const _ConnectionEditor({
    required this.connection,
    this.preset,
    required this.initialProbe,
    required this.probe,
    required this.testModel,
    required this.onProbe,
    this.onDelete,
  });
  final AiConnection? connection;
  final ProviderPreset? preset;
  final connection_probe.ProbeResult? initialProbe;
  final ServerProbe probe;
  final ModelTest testModel;
  final void Function(String url, connection_probe.ProbeResult result) onProbe;
  final VoidCallback? onDelete;
  @override
  State<_ConnectionEditor> createState() => _ConnectionEditorState();
}

class _ConnectionEdit {
  const _ConnectionEdit(this.connection, this.apiKey);
  final AiConnection connection;
  final String? apiKey;
}

class _ConnectionEditorState extends State<_ConnectionEditor> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(
    text: widget.connection?.label ?? widget.preset?.label,
  );
  late final _url = TextEditingController(
    text: widget.connection?.url ?? widget.preset?.url,
  );
  final _key = TextEditingController();
  late String _kind =
      widget.preset?.kind ??
      (_kinds.containsKey(widget.connection?.kind)
          ? widget.connection!.kind
          : 'openai-compatible');
  late final bool _cloud =
      widget.connection?.cloud ?? widget.preset?.cloud ?? false;
  late connection_probe.ProbeResult? _result = widget.initialProbe;
  connection_probe.ModelTestResult? _test;
  String? _model;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final id = widget.connection?.id;
    if (id != null) {
      readApiKey(id).then((key) {
        if (mounted && key != null) _key.text = key;
      });
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _probe() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final url = normalizeConnectionUrl(_url.text);
    final result = await widget.probe(url, key: _key.text, kind: _kind);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = result;
      _model = result.models.map((m) => m.id).contains(_model)
          ? _model
          : result.models.firstOrNull?.id;
      _test = null;
    });
    widget.onProbe(url, result);
  }

  Future<void> _testModel() async {
    if (!_form.currentState!.validate() || _model == null) return;
    setState(() => _busy = true);
    final result = await widget.testModel(
      normalizeConnectionUrl(_url.text),
      _model!,
      key: _key.text,
      kind: _kind,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _test = result;
    });
  }

  Future<void> _delete() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete server?',
      message: 'Tasks using this server will return to their defaults.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!mounted || confirmed != true) return;
    widget.onDelete!();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final models = {
      for (final model in _result?.models ?? <connection_probe.ProbeModel>[])
        model.id: model,
    }.values.toList();
    return AppSheet.body(
      title: widget.connection == null ? 'Add server' : 'Edit server',
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          kSpace16,
          0,
          kSpace16,
          kSpace16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _name,
                enabled: !_busy,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter a name'
                    : null,
              ),
              TextFormField(
                controller: _url,
                enabled: !_busy,
                decoration: const InputDecoration(labelText: 'Server URL'),
                validator: (value) => validateConnectionUrl(value ?? ''),
                onChanged: (_) => setState(() {
                  _result = null;
                  _model = null;
                  _test = null;
                }),
              ),
              DropdownButtonFormField<String>(
                initialValue: _kind,
                decoration: const InputDecoration(labelText: 'Kind'),
                items: [
                  for (final kind in _kinds.entries)
                    DropdownMenuItem(value: kind.key, child: Text(kind.value)),
                ],
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _kind = value!),
              ),
              TextFormField(
                controller: _key,
                enabled: !_busy,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'API key'),
              ),
              TextButton(
                onPressed: _busy ? null : _probe,
                child: const Text('Test connection'),
              ),
              if (_busy) const LinearProgressIndicator(),
              if (_result case final result?) ...[
                Text(
                  result.ok
                      ? 'Reachable · ${result.latencyMs} ms'
                      : result.error ?? 'Cannot connect',
                ),
                for (final model in models)
                  Text(
                    '${model.id}${model.loaded == null
                        ? ''
                        : model.loaded!
                        ? ' · loaded'
                        : ' · not loaded'}${model.contextLength == null ? '' : ' · context ${model.contextLength}'}',
                  ),
              ],
              if (models.isNotEmpty) ...[
                DropdownButtonFormField<String>(
                  key: ValueKey(models.map((m) => m.id).join('|')),
                  initialValue: _model ?? models.first.id,
                  decoration: const InputDecoration(labelText: 'Test model'),
                  isExpanded: true,
                  items: [
                    for (final model in models)
                      DropdownMenuItem(value: model.id, child: Text(model.id)),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _model = value),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () {
                          _model ??= models.first.id;
                          _testModel();
                        },
                  child: const Text('Test model'),
                ),
              ],
              if (_test case final result?)
                Text(
                  result.ok
                      ? '${result.reply} · ${result.latencyMs} ms'
                      : result.error ?? 'Cannot connect',
                ),
              Wrap(
                spacing: 8,
                children: [
                  if (widget.onDelete != null)
                    TextButton(
                      onPressed: _busy ? null : _delete,
                      child: const Text('Delete'),
                    ),
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () {
                            if (!_form.currentState!.validate()) return;
                            Navigator.pop(
                              context,
                              _ConnectionEdit(
                                AiConnection(
                                  id: widget.connection?.id ?? '',
                                  label: _name.text.trim(),
                                  url: normalizeConnectionUrl(_url.text),
                                  kind: _kind,
                                  cloud: _cloud,
                                ),
                                _key.text,
                              ),
                            );
                          },
                    child: const Text('Save'),
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
