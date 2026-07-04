import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:rrule/rrule.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'models.dart';

DateTime? nextTaskReminder(TaskRef task, DateTime now) {
  final initial = DateTime.tryParse(task.remind ?? task.due ?? '');
  if (initial == null || task.status == 'done' || task.status == 'cancelled') {
    return null;
  }
  if (task.recurrence == null || task.recurrence!.isEmpty) {
    return initial.isAfter(now) ? initial : null;
  }
  try {
    final rule = RecurrenceRule.fromString(task.recurrence!);
    return rule
        .getInstances(
          start: initial.toUtc().copyWith(isUtc: true),
          after: now.toUtc().copyWith(isUtc: true),
        )
        .firstOrNull;
  } catch (_) {
    return null;
  }
}

class TaskScheduler {
  final plugin = FlutterLocalNotificationsPlugin();

  Future<void> initialize(void Function(String path) onOpen) async {
    tz_data.initializeTimeZones();
    try {
      final local = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(local.identifier));
    } catch (_) {
      // UTC remains a safe fallback when the OS timezone is unavailable.
    }
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        macOS: DarwinInitializationSettings(),
        linux: LinuxInitializationSettings(defaultActionName: 'Open'),
      ),
      onDidReceiveNotificationResponse: (response) {
        final path = response.payload;
        if (path != null && path.isNotEmpty) onOpen(path);
      },
    );
  }

  Future<void> requestPermission() async {
    if (Platform.isAndroid) {
      await plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    } else if (Platform.isMacOS) {
      await plugin
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: false, sound: true);
    }
  }

  Future<void> reconcile(Iterable<TaskRef> tasks) async {
    if (kIsWeb) return;
    await plugin.cancelAll();
    final now = DateTime.now();
    for (final task in tasks) {
      final next = nextTaskReminder(task, now);
      if (next == null) continue;
      await plugin.zonedSchedule(
        id: task.id.hashCode & 0x7fffffff,
        title: task.project ?? 'TyLog task',
        body: task.text,
        payload: task.notePath,
        scheduledDate: tz.TZDateTime.from(next, tz.local),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'tylog_tasks',
            'Task reminders',
            channelDescription: 'Due and recurring TyLog tasks',
          ),
          macOS: DarwinNotificationDetails(),
          linux: LinuxNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }
}
