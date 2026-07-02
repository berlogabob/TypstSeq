import 'package:flutter/material.dart';

class TyLogApp extends StatelessWidget {
  const TyLogApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'TyLog',
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3F6F68)),
    ),
    home: const _WebHome(),
  );
}

class _WebHome extends StatelessWidget {
  const _WebHome();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('TyLog', style: Theme.of(context).textTheme.displaySmall),
              const SizedBox(height: 12),
              Text(
                'Local-first Typst journal and PKM app.',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 24),
              const Text(
                'Android/macOS app stores notes as plain .typ files, opens on the daily journal, and derives pages, graph, and backlinks from your vault.',
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: null,
                icon: Icon(Icons.android),
                label: Text('Install from GitHub Releases'),
              ),
              const SizedBox(height: 8),
              Text(
                'Web preview is a lightweight landing page until the native Typst preview dependency supports Flutter Web.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
