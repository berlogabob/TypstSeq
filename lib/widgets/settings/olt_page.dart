import 'package:flutter/material.dart';

import '../../olt/olt_client.dart';
import '../../olt/olt_cache.dart';
import '../constants.dart';

class OltSection extends StatefulWidget {
  const OltSection({super.key});
  @override
  State<OltSection> createState() => _OltSectionState();
}

class _OltSectionState extends State<OltSection> {
  final _client = OltClient();
  final _email = TextEditingController();
  final _code = TextEditingController();
  String? _message;
  bool _busy = false;
  bool _expanded = false;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, {String? done}) async {
    setState(() => _busy = true);
    try {
      await action();
      _message = done;
    } catch (error) {
      _message = error.toString().replaceFirst('Exception: ', '');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ExpansionTile(
    title: const Text('OpenLabTwin'),
    onExpansionChanged: (expanded) => setState(() => _expanded = expanded),
    children: [
      if (_expanded) ...[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: kSpace16),
          child: FutureBuilder<OltSession?>(
            future: _client.session,
            builder: (context, snapshot) {
              final session = snapshot.data;
              if (session != null) {
                return Column(
                  children: [
                    ListTile(title: Text('Signed in as ${session.email}')),
                    FilledButton(
                      onPressed: _busy
                          ? null
                          : () => _run(() async {
                              final result = await refreshOltCache(
                                _client,
                                await oltCacheDirectory(),
                              );
                              if (result.signedOut) throw OltSignInNeeded();
                            }),
                      child: const Text('Refresh OpenLabTwin'),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _run(() async {
                              await _client.signOut();
                              setState(() {});
                            }),
                      child: const Text('Sign out'),
                    ),
                  ],
                );
              }
              return Column(
                children: [
                  const ListTile(title: Text('Signed out')),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () => _run(
                            () => _client.requestCode(_email.text.trim()),
                            done: 'Code sent to ${_email.text.trim()}',
                          ),
                    child: const Text('Send code'),
                  ),
                  TextField(
                    controller: _code,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: const InputDecoration(
                      labelText: '6-digit code',
                    ),
                  ),
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                            await _client.verify(
                              _email.text.trim(),
                              _code.text.trim(),
                            );
                            setState(() {});
                          }),
                    child: const Text('Sign in'),
                  ),
                ],
              );
            },
          ),
        ),
        FutureBuilder<OltCacheMeta>(
          future: oltCacheDirectory().then(loadOltCacheMeta),
          builder: (context, snapshot) {
            final meta = snapshot.data;
            if (meta == null) return const SizedBox.shrink();
            return ListTile(
              title: Text(
                meta.lastSuccess == null
                    ? 'Never refreshed'
                    : 'Last refreshed: ${formatOltTime(meta.lastSuccess!)}',
              ),
              subtitle: meta.error == null
                  ? null
                  : Text(
                      'Refresh failed ${formatOltTime(meta.failedAt!)}: ${meta.error}',
                    ),
            );
          },
        ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.all(kSpace16),
            child: Text(_message!),
          ),
      ],
    ],
  );
}
