import 'package:flutter/material.dart';
import '../audio_processing_settings.dart';
import '../screenshots_settings.dart';
import '../settings_sheet.dart';
import 'settings_page.dart';

class AiPage extends StatelessWidget {
  const AiPage({super.key, required this.settings});
  final SettingsSheet settings;

  @override
  Widget build(BuildContext context) => SettingsPage(
    title: 'AI',
    children: [
      _row(
        context,
        'Servers',
        'Connections and worker status',
        AiSettingsSection.servers,
      ),
      _row(
        context,
        'Audio',
        'Transcription, translation, and languages',
        AiSettingsSection.audio,
      ),
      _row(
        context,
        'Articles',
        'Article extraction server and model',
        AiSettingsSection.articles,
      ),
      ListTile(
        title: const Text('Screenshots'),
        subtitle: const Text('OCR model, schedule, and folder'),
        trailing: const Icon(Icons.chevron_right),
        onTap: settings.readScreenshotsStatus == null
            ? null
            : () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  settings: const RouteSettings(name: '$kSettingsRoute/ai'),
                  builder: (_) => SettingsPage(
                    title: 'Screenshots',
                    children: [
                      if (settings.audioPolicyRead != null)
                        _audio(AiSettingsSection.screenshots),
                      _screenshots(),
                    ],
                  ),
                ),
              ),
      ),
    ],
  );

  ListTile _row(
    BuildContext context,
    String title,
    String subtitle,
    AiSettingsSection section,
  ) => ListTile(
    title: Text(title),
    subtitle: Text(subtitle),
    trailing: const Icon(Icons.chevron_right),
    onTap: settings.audioPolicyRead == null
        ? null
        : () => Navigator.push<void>(
            context,
            MaterialPageRoute(
              settings: const RouteSettings(name: '$kSettingsRoute/ai'),
              builder: (_) =>
                  SettingsPage(title: title, children: [_audio(section)]),
            ),
          ),
  );

  Widget _audio(AiSettingsSection section) => AudioProcessingSettings(
    section: section,
    read: settings.audioPolicyRead!,
    write: settings.audioPolicyWrite!,
    processNow: settings.onProcessAudio!,
    readAi: settings.readAi,
    writeAi: settings.writeAi,
    readWorkers: settings.readWorkers,
  );

  Widget _screenshots() => ScreenshotsSettings(
    mode: settings.screenshotsMode,
    time: settings.screenshotsTime,
    onConfigure: settings.onConfigureScreenshots!,
    onProcessNow: settings.onProcessScreenshots!,
    readStatus: settings.readScreenshotsStatus!,
    folder: settings.screenshotsFolder,
    onFolderChanged: settings.onScreenshotsFolderChanged,
    readWanted: settings.readScreenshotsWanted,
    editable: true,
  );
}
