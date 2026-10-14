import 'package:flutter/material.dart';
import 'app_icons.dart';

/// The one control set for every background pipeline (audio transcription,
/// screenshot OCR): manual, right after, or on a daily schedule, plus process
/// now. Pipeline-specific options go in [extras].
class ProcessingPolicyEditor extends StatelessWidget {
  const ProcessingPolicyEditor({
    super.key,
    required this.icon,
    required this.title,
    required this.onTheFly,
    required this.scheduled,
    required this.time,
    required this.onChanged,
    required this.onProcessNow,
    this.extras = const [],
    this.status,
    this.enabled = true,
    this.busy = false,
  });

  final IconData icon;
  final String title;
  final bool onTheFly;
  final bool scheduled;
  final String time;
  final void Function(bool onTheFly, bool scheduled, String time) onChanged;
  final VoidCallback onProcessNow;
  final List<Widget> extras;
  final String? status;
  final bool enabled;
  final bool busy;

  Future<void> _pickTime(BuildContext context) async {
    final parts = time.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.tryParse(parts.first) ?? 3,
        minute: int.tryParse(parts.last) ?? 0,
      ),
    );
    if (picked == null) return;
    onChanged(
      onTheFly && !scheduled,
      scheduled,
      '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(leading: Icon(icon), title: Text(title)),
        ...extras,
        RadioGroup<String>(
          groupValue: scheduled
              ? 'schedule'
              : onTheFly
              ? 'watch'
              : 'off',
          onChanged: (value) {
            if (enabled && !busy && value != null) {
              onChanged(value == 'watch', value == 'schedule', time);
            }
          },
          child: Column(
            children: [
              RadioListTile<String>(
                value: 'off',
                title: const Text('Only when I ask'),
                enabled: enabled && !busy,
              ),
              RadioListTile<String>(
                value: 'watch',
                title: const Text('Right after it is added'),
                enabled: enabled && !busy,
              ),
              RadioListTile<String>(
                value: 'schedule',
                title: const Text('On schedule'),
                enabled: enabled && !busy,
              ),
            ],
          ),
        ),
        if (scheduled)
          ListTile(
            contentPadding: const EdgeInsets.only(left: 32, right: 16),
            leading: const Icon(AppIcons.schedule),
            title: Text('Every day at $time'),
            trailing: const Icon(AppIcons.edit, size: 20),
            enabled: enabled && !busy,
            onTap: () => _pickTime(context),
          ),
        if (status != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(status!, style: Theme.of(context).textTheme.bodySmall),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: busy ? null : onProcessNow,
            child: const Text('Process now'),
          ),
        ),
      ],
    );
  }
}
