import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/task_scheduler.dart';
import 'package:tylog/vault.dart';
import 'package:tylog/vault_storage.dart';
import 'package:tylog/workspace_controller.dart';
import '../support/temp_dir.dart';

class _PausedStorage extends LocalVaultStorage {
  _PausedStorage(super.root);

  final configuring = Completer<void>();
  final resume = Completer<void>();

  @override
  Future<void> writeText(String path, String text) async {
    if (path == WorkspaceController.calendarsSyncPath) {
      configuring.complete();
      await resume.future;
    }
    await super.writeText(path, text);
  }
}

void main() {
  test(
    'concurrent calendar configuration and refresh preserve both changes',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'tylog_settings_chain_',
      );
      addTearDown(() => deleteTempDir(dir));
      final storage = _PausedStorage(dir);
      final fetched = Completer<void>();
      final controller = WorkspaceController(
        taskScheduler: TaskScheduler(),
        fetchFeed: (_) async {
          fetched.complete();
          return 'BEGIN:VCALENDAR\nEND:VCALENDAR';
        },
      );
      addTearDown(controller.dispose);
      controller.vault = Vault.withStorage(storage);
      await storage.writeText(
        Vault.settingsPath,
        jsonEncode({
          'keep': 'unchanged',
          'calendars': {
            'feeds': [
              {
                'id': 'one',
                'kind': 'ics',
                'url': 'https://example.org/one.ics',
              },
            ],
          },
        }),
      );

      final configure = controller.configureCalendars({'feeds': const []});
      await storage.configuring.future;
      final refresh = controller.refreshCalendarFeeds(force: true);
      await fetched.future;
      await pumpEventQueue();
      storage.resume.complete();
      await Future.wait([configure, refresh]);

      final settings =
          jsonDecode(await storage.readText(Vault.settingsPath)) as Map;
      final calendars = settings['calendars'] as Map;
      expect(settings['keep'], 'unchanged');
      expect(calendars.containsKey('feeds'), isFalse);
      expect(
        (calendars['cache'] as Map)['one'],
        containsPair('body', 'BEGIN:VCALENDAR\nEND:VCALENDAR'),
      );
      final shared =
          jsonDecode(
                await storage.readText(WorkspaceController.calendarsSyncPath),
              )
              as Map;
      expect(shared['feeds'], isEmpty);
    },
  );
}
