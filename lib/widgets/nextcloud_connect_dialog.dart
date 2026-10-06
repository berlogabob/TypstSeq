import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../nextcloud_sync.dart';
import '../nextcloud_sync/login_flow.dart';

class NextcloudConnectDialog extends StatefulWidget {
  const NextcloudConnectDialog({
    super.key,
    this.config,
    this.start = startLoginFlow,
    this.poll = pollLoginFlow,
    this.openBrowser,
  });

  final NextcloudConfig? config;
  final Future<LoginFlowStart> Function(Uri, {HttpClient? client}) start;
  final Future<LoginFlowResult> Function(
    LoginFlowStart, {
    HttpClient? client,
    Duration interval,
    Duration timeout,
  })
  poll;
  final Future<bool> Function(Uri)? openBrowser;

  @override
  State<NextcloudConnectDialog> createState() => _NextcloudConnectDialogState();
}

class _NextcloudConnectDialogState extends State<NextcloudConnectDialog> {
  late final url = TextEditingController(text: widget.config?.serverUrl ?? '');
  late final user = TextEditingController(text: widget.config?.username ?? '');
  late final pass = TextEditingController(text: widget.config?.password ?? '');
  late final folder = TextEditingController(
    text: widget.config?.remoteFolder ?? 'TyLogVault',
  );
  HttpClient? client;
  String? error;

  NextcloudConfig draft() => NextcloudConfig(
    serverUrl: url.text,
    username: user.text,
    password: pass.text,
    remoteFolder: folder.text,
  );

  void cancel() {
    client?.close(force: true);
    setState(() => client = null);
  }

  @override
  void dispose() {
    client?.close(force: true);
    for (final controller in [url, user, pass, folder]) {
      controller.dispose();
    }
    super.dispose();
  }

  void accept() {
    TextInput.finishAutofillContext();
    Navigator.pop(context, draft());
  }

  Future<void> signIn() async {
    final server = url.text.trim().replaceFirst(RegExp(r'/+$'), '');
    if (!NextcloudConfig(
      serverUrl: server,
      username: 'login',
      password: 'login',
    ).isReady) {
      setState(() => error = 'Enter a valid HTTPS server URL.');
      return;
    }
    final active = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    setState(() {
      client = active;
      error = null;
    });
    bool current() => mounted && client == active;
    try {
      final start = await widget.start(Uri.parse(server), client: active);
      if (!current()) return;
      final opened =
          await (widget.openBrowser?.call(start.loginUrl) ??
              launchUrl(start.loginUrl, mode: LaunchMode.externalApplication));
      if (!current()) return;
      if (!opened) throw StateError('Could not open the browser.');
      final result = await widget.poll(start, client: active);
      if (!current()) return;
      url.text = result.server;
      user.text = result.loginName;
      pass.text = result.appPassword;
      if (!draft().isReady) {
        throw const FormatException('Invalid login configuration.');
      }
      accept();
    } catch (failure) {
      if (current()) setState(() => error = failure.toString());
    } finally {
      active.close(force: true);
      if (current()) setState(() => client = null);
    }
  }

  Widget field(
    TextEditingController controller,
    String label, {
    bool password = false,
    List<String>? autofillHints,
    TextInputType? keyboardType,
    String? hint,
    String? helper,
    TextInputAction textInputAction = TextInputAction.next,
  }) => TextField(
    controller: controller,
    enabled: client == null,
    obscureText: password,
    autocorrect: false,
    enableSuggestions: false,
    autofillHints: autofillHints,
    keyboardType: keyboardType,
    textInputAction: textInputAction,
    onChanged: (_) => setState(() {}),
    decoration: InputDecoration(
      border: const OutlineInputBorder(),
      labelText: label,
      hintText: hint,
      helperText: helper,
    ),
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Connect Nextcloud'),
    content: SingleChildScrollView(
      child: AutofillGroup(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            field(
              url,
              'Server URL',
              keyboardType: TextInputType.url,
              hint: 'https://cloud.example.com',
              autofillHints: const [AutofillHints.url],
            ),
            if (client == null)
              TextButton(
                onPressed: signIn,
                child: const Text('Sign in with browser'),
              )
            else
              Row(
                children: [
                  const Expanded(child: Text('Waiting for approval…')),
                  TextButton(onPressed: cancel, child: const Text('Cancel')),
                ],
              ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            field(user, 'Login', autofillHints: const [AutofillHints.username]),
            field(
              pass,
              'Password or app password',
              password: true,
              autofillHints: const [AutofillHints.password],
            ),
            field(
              folder,
              'Remote folder',
              helper: 'Created inside your Nextcloud files.',
              textInputAction: TextInputAction.done,
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: client == null && draft().isReady ? accept : null,
        child: const Text('Check folder'),
      ),
    ],
  );
}
