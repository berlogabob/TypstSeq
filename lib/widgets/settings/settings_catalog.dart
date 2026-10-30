import 'package:flutter/material.dart';

import '../audio_processing_settings.dart';
import '../settings_sheet.dart';
import 'about_page.dart';
import 'ai_page.dart';
import 'calendars_page.dart';
import 'general_page.dart';
import 'maintenance_page.dart';
import 'olt_page.dart';
import 'sync_storage_page.dart';

typedef SettingsPageBuilder =
    Widget Function(
      SettingsSheet settings, {
      ValueChanged<String>? onPaperChanged,
      ValueChanged<ThemeMode>? onThemeChanged,
    });

class SettingsSearchEntry {
  const SettingsSearchEntry({
    required this.title,
    required this.keywords,
    required this.path,
    required this.routeName,
    required this.builder,
  });

  final String title;
  final String keywords;
  final String path;
  final String routeName;
  final SettingsPageBuilder builder;

  bool matches(String query) =>
      '$title $keywords'.toLowerCase().contains(query.toLowerCase());
}

Widget _general(
  SettingsSheet settings, {
  ValueChanged<String>? onPaperChanged,
  ValueChanged<ThemeMode>? onThemeChanged,
}) => GeneralPage(
  settings: settings,
  onPaperChanged: onPaperChanged,
  onThemeChanged: onThemeChanged,
);

/// The single index used by Settings search and desktop's split view.
const settingsSearchEntries = <SettingsSearchEntry>[
  SettingsSearchEntry(
    title: 'General',
    keywords: 'appearance theme paper size reminders pdf',
    path: 'General',
    routeName: '$kSettingsRoute/page',
    builder: _general,
  ),
  SettingsSearchEntry(
    title: 'Calendars',
    keywords: 'calendar feeds ics timetable',
    path: 'Calendars',
    routeName: '$kSettingsRoute/page',
    builder: _calendars,
  ),
  SettingsSearchEntry(
    title: 'AI',
    keywords: 'servers audio articles screenshots ocr',
    path: 'AI',
    routeName: '$kSettingsRoute/page',
    builder: _ai,
  ),
  SettingsSearchEntry(
    title: 'Sync and storage',
    keywords: 'sync nextcloud vault folder storage',
    path: 'Sync and storage',
    routeName: '$kSettingsRoute/page',
    builder: _sync,
  ),
  SettingsSearchEntry(
    title: 'Maintenance',
    keywords: 'problems index import relink modules semantic search',
    path: 'Maintenance',
    routeName: '$kSettingsRoute/page',
    builder: _maintenance,
  ),
  SettingsSearchEntry(
    title: 'About',
    keywords: 'version updates help typst github',
    path: 'About',
    routeName: '$kSettingsRoute/page',
    builder: _about,
  ),
  SettingsSearchEntry(
    title: 'OpenLabTwin',
    keywords: 'olt lab booking places staff account login',
    path: 'OpenLabTwin',
    routeName: '$kSettingsRoute/page',
    builder: _olt,
  ),
  SettingsSearchEntry(
    title: 'Servers',
    keywords: 'connections worker status ai',
    path: 'AI › Servers',
    routeName: '$kSettingsRoute/ai',
    builder: _servers,
  ),
  SettingsSearchEntry(
    title: 'Audio',
    keywords: 'transcription translation languages processing ai',
    path: 'AI › Audio',
    routeName: '$kSettingsRoute/ai',
    builder: _audio,
  ),
  SettingsSearchEntry(
    title: 'Articles',
    keywords: 'article extraction server model ai',
    path: 'AI › Articles',
    routeName: '$kSettingsRoute/ai',
    builder: _articles,
  ),
  SettingsSearchEntry(
    title: 'Screenshots',
    keywords: 'ocr model schedule folder ai',
    path: 'AI › Screenshots',
    routeName: '$kSettingsRoute/ai',
    builder: _screenshots,
  ),
];

Widget _calendars(
  SettingsSheet s, {
  ValueChanged<String>? onPaperChanged,
  ValueChanged<ThemeMode>? onThemeChanged,
}) => CalendarsPage(settings: s);
Widget _olt(
  SettingsSheet s, {
  ValueChanged<String>? onPaperChanged,
  ValueChanged<ThemeMode>? onThemeChanged,
}) => const OltPage();
Widget _ai(
  SettingsSheet s, {
  ValueChanged<String>? onPaperChanged,
  ValueChanged<ThemeMode>? onThemeChanged,
}) => AiPage(settings: s);
Widget _sync(
  SettingsSheet s, {
  ValueChanged<String>? onPaperChanged,
  ValueChanged<ThemeMode>? onThemeChanged,
}) => SyncStoragePage(settings: s);
Widget _maintenance(
  SettingsSheet s, {
  ValueChanged<String>? onPaperChanged,
  ValueChanged<ThemeMode>? onThemeChanged,
}) => MaintenancePage(settings: s);
Widget _about(
  SettingsSheet s, {
  ValueChanged<String>? onPaperChanged,
  ValueChanged<ThemeMode>? onThemeChanged,
}) => AboutPage(settings: s);
Widget _servers(
  SettingsSheet s, {
  ValueChanged<String>? onPaperChanged,
  ValueChanged<ThemeMode>? onThemeChanged,
}) => aiSectionPage(s, 'Servers', AiSettingsSection.servers);
Widget _audio(
  SettingsSheet s, {
  ValueChanged<String>? onPaperChanged,
  ValueChanged<ThemeMode>? onThemeChanged,
}) => aiSectionPage(s, 'Audio', AiSettingsSection.audio);
Widget _articles(
  SettingsSheet s, {
  ValueChanged<String>? onPaperChanged,
  ValueChanged<ThemeMode>? onThemeChanged,
}) => aiSectionPage(s, 'Articles', AiSettingsSection.articles);
Widget _screenshots(
  SettingsSheet s, {
  ValueChanged<String>? onPaperChanged,
  ValueChanged<ThemeMode>? onThemeChanged,
}) => screenshotsPage(s);
