import 'dart:async';
import 'package:flutter/material.dart';
import '../constants.dart';
import '../settings_sheet.dart';
import 'scope_note.dart';
import 'settings_page.dart';

class GeneralPage extends StatefulWidget {
  const GeneralPage({
    super.key,
    required this.settings,
    this.onPaperChanged,
    this.onThemeChanged,
  });
  final SettingsSheet settings;
  final ValueChanged<String>? onPaperChanged;
  final ValueChanged<ThemeMode>? onThemeChanged;
  @override
  State<GeneralPage> createState() => _GeneralPageState();
}

class _GeneralPageState extends State<GeneralPage> {
  String? selectedPaper;

  @override
  Widget build(BuildContext context) => SettingsPage(
    title: 'General',
    children: [
      Padding(
        padding: const EdgeInsets.all(kSpace8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.brightness_6_outlined,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: kSpace12),
                const Text('Appearance'),
              ],
            ),
            const ScopeNote('This device'),
            const SizedBox(height: kSpace8),
            Row(
              children: [
                for (final (mode, label) in const [
                  (ThemeMode.system, 'Auto'),
                  (ThemeMode.light, 'Light'),
                  (ThemeMode.dark, 'Dark'),
                ])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: kSpace8),
                      child: ChoiceChip(
                        showCheckmark: false,
                        label: SizedBox(
                          width: double.infinity,
                          child: Text(label, textAlign: TextAlign.center),
                        ),
                        selected: widget.settings.themeMode == mode,
                        onSelected: (_) {
                          widget.settings.onThemeModeChanged(mode);
                          widget.onThemeChanged?.call(mode);
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      ListTile(
        leading: const Icon(Icons.picture_as_pdf_outlined),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [Text('PDF page size'), ScopeNote('This device')],
        ),
        trailing: DropdownButton<String>(
          value: selectedPaper ?? widget.settings.pdfPaper,
          items: const [
            DropdownMenuItem(value: 'a4', child: Text('A4')),
            DropdownMenuItem(value: 'us-letter', child: Text('Letter')),
            DropdownMenuItem(value: 'a5', child: Text('A5')),
            DropdownMenuItem(value: 'us-legal', child: Text('Legal')),
          ],
          onChanged: (paper) {
            if (paper == null) return;
            setState(() => selectedPaper = paper);
            widget.settings.onPdfPaperChanged?.call(paper);
            widget.onPaperChanged?.call(paper);
          },
        ),
      ),
      ListTile(
        leading: const Icon(Icons.notifications_outlined),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [Text('Task reminders'), ScopeNote('This device')],
        ),
        onTap: () => unawaited(widget.settings.onEnableReminders()),
      ),
    ],
  );
}
