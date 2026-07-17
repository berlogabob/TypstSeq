import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../rich_editor.dart';

class ReadingMode extends StatefulWidget {
  const ReadingMode({
    super.key,
    required this.source,
    required this.path,
    required this.fontScale,
    required this.nightMode,
    required this.onExit,
    required this.onPreferencesChanged,
    required this.onProgress,
  });

  final String source;
  final String? path;
  final double fontScale;
  final bool nightMode;
  final VoidCallback onExit;
  final Future<void> Function(double fontScale, bool nightMode)
  onPreferencesChanged;
  final Future<void> Function(String path, double progress) onProgress;

  @override
  State<ReadingMode> createState() => _ReadingModeState();
}

class _ReadingModeState extends State<ReadingMode> {
  final scrollController = ScrollController();
  final progress = ValueNotifier<double>(0);
  late double fontScale = widget.fontScale.clamp(0.8, 2).toDouble();
  late bool nightMode = widget.nightMode;
  bool fullscreen = false;

  @override
  void initState() {
    super.initState();
    scrollController.addListener(_updateProgress);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateProgress());
  }

  @override
  void dispose() {
    final path = widget.path;
    if (path != null) {
      unawaited(widget.onProgress(path, progress.value).catchError((_) {}));
    }
    scrollController
      ..removeListener(_updateProgress)
      ..dispose();
    progress.dispose();
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }

  void _updateProgress() {
    if (!scrollController.hasClients) return;
    final position = scrollController.position;
    final value = position.maxScrollExtent == 0
        ? 1.0
        : (position.pixels / position.maxScrollExtent).clamp(0, 1).toDouble();
    if ((progress.value - value).abs() > 0.001) progress.value = value;
  }

  void _setFontScale(double value) {
    final next = (value.clamp(0.8, 2) * 10).round() / 10;
    if (next == fontScale) return;
    final position = scrollController.hasClients
        ? scrollController.position
        : null;
    final fraction = position != null && position.maxScrollExtent > 0
        ? position.pixels / position.maxScrollExtent
        : 0.0;
    setState(() => fontScale = next);
    _persistPreferences();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scrollController.hasClients) return;
      final max = scrollController.position.maxScrollExtent;
      scrollController.jumpTo((fraction * max).clamp(0, max).toDouble());
      _updateProgress();
    });
  }

  void _setNightMode(bool value) {
    setState(() => nightMode = value);
    _persistPreferences();
  }

  void _persistPreferences() => unawaited(
    widget.onPreferencesChanged(fontScale, nightMode).catchError((_) {}),
  );

  Future<void> _setFullscreen(bool value) async {
    setState(() => fullscreen = value);
    try {
      await SystemChrome.setEnabledSystemUIMode(
        value ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      );
    } catch (_) {
      if (mounted) setState(() => fullscreen = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final readingTheme = nightMode
        ? ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF0F172A),
              brightness: Brightness.dark,
            ),
          )
        : Theme.of(context);
    final iconBrightness = nightMode ? Brightness.light : Brightness.dark;

    return Theme(
      data: readingTheme,
      child: Builder(
        builder: (context) => AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarBrightness: nightMode ? Brightness.dark : Brightness.light,
            statusBarIconBrightness: iconBrightness,
            systemNavigationBarColor: Theme.of(context).colorScheme.surface,
            systemNavigationBarIconBrightness: iconBrightness,
          ),
          child: PopScope<void>(
            canPop: false,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) widget.onExit();
            },
            child: Scaffold(
              backgroundColor: Theme.of(context).colorScheme.surface,
              body: SafeArea(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    NotificationListener<ScrollMetricsNotification>(
                      onNotification: (_) {
                        _updateProgress();
                        return false;
                      },
                      child: SingleChildScrollView(
                        key: const Key('reading-scroll'),
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(18, 64, 18, 22),
                        child: MediaQuery(
                          data: MediaQuery.of(context).copyWith(
                            textScaler: _ReadingTextScaler(
                              MediaQuery.textScalerOf(context),
                              fontScale,
                            ),
                          ),
                          child: TyLogReadView(
                            key: const Key('reading-document'),
                            source: widget.source,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 8,
                      top: 4,
                      child: IconButton.filledTonal(
                        tooltip: 'Back to edit',
                        onPressed: widget.onExit,
                        icon: const Icon(Icons.arrow_back),
                      ),
                    ),
                    Positioned(
                      right: 8,
                      top: 4,
                      child: MenuAnchor(
                        menuChildren: [
                          SizedBox(
                            width: 260,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    8,
                                    12,
                                    4,
                                  ),
                                  child: Row(
                                    children: [
                                      IconButton(
                                        key: const Key('reading-font-smaller'),
                                        tooltip: 'Decrease font size',
                                        onPressed: fontScale > 0.8
                                            ? () =>
                                                  _setFontScale(fontScale - 0.1)
                                            : null,
                                        icon: const Icon(Icons.remove),
                                      ),
                                      Expanded(
                                        child: Text(
                                          '${(fontScale * 100).round()}%',
                                          key: const Key('reading-font-scale'),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                      IconButton(
                                        key: const Key('reading-font-larger'),
                                        tooltip: 'Increase font size',
                                        onPressed: fontScale < 2
                                            ? () =>
                                                  _setFontScale(fontScale + 0.1)
                                            : null,
                                        icon: const Icon(Icons.add),
                                      ),
                                    ],
                                  ),
                                ),
                                SwitchListTile(
                                  key: const Key('reading-night-mode'),
                                  dense: true,
                                  secondary: const Icon(
                                    Icons.dark_mode_outlined,
                                  ),
                                  title: const Text('Night mode'),
                                  value: nightMode,
                                  onChanged: _setNightMode,
                                ),
                                SwitchListTile(
                                  key: const Key('reading-fullscreen'),
                                  dense: true,
                                  secondary: const Icon(Icons.fullscreen),
                                  title: const Text('Fullscreen'),
                                  value: fullscreen,
                                  onChanged: (value) =>
                                      unawaited(_setFullscreen(value)),
                                ),
                              ],
                            ),
                          ),
                        ],
                        builder: (context, controller, _) =>
                            IconButton.filledTonal(
                              tooltip: 'Reading settings',
                              onPressed: () => controller.isOpen
                                  ? controller.close()
                                  : controller.open(),
                              icon: const Icon(Icons.text_fields),
                            ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: ValueListenableBuilder<double>(
                        valueListenable: progress,
                        builder: (_, value, _) => LinearProgressIndicator(
                          key: const Key('reading-progress'),
                          value: value,
                          minHeight: 3,
                          semanticsLabel: 'Reading progress',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReadingTextScaler extends TextScaler {
  const _ReadingTextScaler(this.base, this.factor);

  final TextScaler base;
  final double factor;

  @override
  double scale(double fontSize) => base.scale(fontSize * factor);

  @override
  double get textScaleFactor => scale(1);

  @override
  bool operator ==(Object other) =>
      other is _ReadingTextScaler &&
      other.base == base &&
      other.factor == factor;

  @override
  int get hashCode => Object.hash(base, factor);
}
