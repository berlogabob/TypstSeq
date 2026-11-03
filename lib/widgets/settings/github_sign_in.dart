import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../github/github_auth.dart';
import '../../github/github_client.dart';

class GitHubSignIn extends StatefulWidget {
  const GitHubSignIn({
    super.key,
    this.auth,
    this.resolveToken,
    this.client,
    this.openUrl,
    this.onChanged,
  });
  final GitHubAuth? auth;
  final Future<String?> Function()? resolveToken;
  final GitHubClient Function(String)? client;
  final Future<bool> Function(Uri)? openUrl;
  final VoidCallback? onChanged;

  @override
  State<GitHubSignIn> createState() => _GitHubSignInState();
}

class _GitHubSignInState extends State<GitHubSignIn> {
  late final GitHubAuth auth = widget.auth ?? GitHubAuth();
  String? login;
  bool cli = false;
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final stored = await auth.token();
      final token = stored == null || stored.isEmpty
          ? await (widget.resolveToken?.call() ??
                githubToken(readToken: () async => null))
          : stored;
      final user = token == null
          ? null
          : await (widget.client?.call(token) ?? GitHubClient(token))
                .currentUser();
      if (mounted) {
        setState(() {
          login = user?['login'] as String?;
          cli = token != null && (stored == null || stored.isEmpty);
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = 'GitHub: $e');
    }
  }

  Future<void> _signIn() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final code = await auth.requestDeviceCode();
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Sign in with GitHub'),
          content: Text(
            'Enter code ${code.userCode} at ${code.verificationUri}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
      final uri = Uri.parse(code.verificationUri);
      if (!await (widget.openUrl?.call(uri) ??
          launchUrl(uri, mode: LaunchMode.externalApplication))) {
        throw StateError('Could not open verification URL');
      }
      await auth.pollForToken(code);
      await _load();
      widget.onChanged?.call();
    } catch (e) {
      if (mounted) setState(() => error = 'GitHub sign-in failed: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListTile(
    leading: const Icon(Icons.account_circle_outlined),
    title: Text(login == null ? 'Sign in with GitHub' : 'GitHub: $login'),
    subtitle: error != null
        ? Text(error!)
        : cli
        ? const Text('Using GitHub CLI login')
        : null,
    onTap: login == null && !busy ? _signIn : null,
    trailing: login != null && !cli
        ? TextButton(
            onPressed: busy
                ? null
                : () async {
                    await auth.clear();
                    await _load();
                    widget.onChanged?.call();
                  },
            child: const Text('Sign out'),
          )
        : null,
  );
}
