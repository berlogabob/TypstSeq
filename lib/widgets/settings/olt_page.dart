import 'package:flutter/material.dart';

import '../../olt/olt_client.dart';
import '../constants.dart';
import 'settings_page.dart';

class OltPage extends StatefulWidget {
  const OltPage({super.key});
  @override
  State<OltPage> createState() => _OltPageState();
}

class _OltPageState extends State<OltPage> {
  final _client = OltClient();
  final _email = TextEditingController(
    text: 'andrey.dyakov@universidadeeuropeia.pt',
  );
  final _code = TextEditingController();
  String? _message;
  int? _places;
  bool _busy = false;

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
  Widget build(BuildContext context) => SettingsPage(
    title: 'OpenLabTwin',
    children: [
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
                            final rows =
                                await _client.get(
                                      'places',
                                      'select=*&limit=200',
                                    )
                                    as List;
                            setState(() => _places = rows.length);
                          }),
                    child: const Text('Read places'),
                  ),
                  if (_places != null) Text('$_places places'),
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
                  decoration: const InputDecoration(labelText: '6-digit code'),
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
      if (_message != null)
        Padding(
          padding: const EdgeInsets.all(kSpace16),
          child: Text(_message!),
        ),
    ],
  );
}
