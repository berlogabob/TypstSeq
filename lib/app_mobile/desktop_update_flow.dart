part of '../app_mobile.dart';

extension _DesktopUpdateFlow on _HomeScreenState {
  /// macOS: check GitHub Releases for a newer build. When [silent], stays quiet
  /// unless an update exists (used for the once-per-launch check); otherwise it
  /// also reports "up to date"/errors (the Settings button).
  Future<void> _checkForUpdates({required bool silent}) async {
    final result = await updater.checkForUpdate();
    if (!mounted) return;
    final info = result.info;
    if (info == null) {
      // Distinguish a real failure from "already current" so the manual check
      // doesn't falsely claim you're up to date when the network call failed.
      if (!silent) {
        showSnack(
          context,
          result.failed
              ? "Couldn't check for updates"
              : "You're up to date",
        );
      }
      return;
    }
    final update = info;
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Update available · ${update.version}'),
        content: SingleChildScrollView(
          child: Text(
            update.notes.isEmpty ? 'A newer version is available.' : update.notes,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context, false);
              _openUrl(update.htmlUrl);
            },
            child: const Text('View release'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Update & restart'),
          ),
        ],
      ),
    );
    if (go == true) await _applyUpdate(update);
  }

  /// Downloads and applies [update] behind a progress dialog. On success the app
  /// quits and relaunches itself; on a non-writable location it falls back to
  /// opening the release page for a manual install.
  Future<void> _applyUpdate(updater.UpdateInfo update) async {
    final progress = ValueNotifier<double>(0);
    if (!mounted) return;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text('Updating…'),
          content: ValueListenableBuilder<double>(
            valueListenable: progress,
            builder: (_, value, _) => LinearProgressIndicator(
              value: value == 0 ? null : value,
            ),
          ),
        ),
      ),
    );
    try {
      // On success this never returns — the process exits and relaunches.
      await updater.downloadAndApply(update, onProgress: (p) => progress.value = p);
    } on updater.UpdateNotWritable {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        showSnack(
          context,
          "Can't replace the app here — opening the release page",
        );
        _openUrl(update.htmlUrl);
      }
    } on Exception {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        showSnack(context, 'Update failed — opening the release page');
        _openUrl(update.htmlUrl);
      }
    } finally {
      progress.dispose();
    }
  }
}
