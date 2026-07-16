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
  } catch (error) {
    debugPrint('Invalid recurrence for task ${task.id}: $error');
    return null;
  }
}

/// Checks each task's non-empty `recurrence` field for a valid RRULE.
///
/// This mirrors the `PkmsProblem` construction pattern used by
/// `validatePkmsStorage` in `tylog_core`, but lives in the app layer: the
/// `rrule` package that can parse/validate recurrence strings is an app
/// dependency only, and `tylog_core` must not gain a new dependency just for
/// this check.
List<PkmsProblem> validateTaskRecurrences(Iterable<TaskRef> tasks) {
  final problems = <PkmsProblem>[];
  for (final task in tasks) {
    final recurrence = task.recurrence;
    if (recurrence == null || recurrence.isEmpty) continue;
    try {
      RecurrenceRule.fromString(recurrence);
    } catch (_) {
      problems.add(
        PkmsProblem(
          code: 'invalid-recurrence',
          severity: PkmsSeverity.warning,
          subject: task.notePath,
          message: 'Task "${task.id}" has an unparseable recurrence rule',
          fix: 'Fix the recurrence field of task "${task.id}" so it is a valid RRULE.',
        ),
      );
    }
  }
  return problems;
}

/// Deterministic 31-bit positive notification id for [id].
///
/// Dart's `String.hashCode` is explicitly *not* guaranteed to be stable
/// across runs/isolates/platforms, so using it for a notification id (which
/// must stay the same across app restarts so reconciling replaces rather
/// than duplicates a pending notification) risks silent collisions and
/// orphaned notifications. FNV-1a is a small, well-known, stable hash.
int stableTaskNotificationId(String id) {
  var hash = 0x811c9dc5;
  for (final unit in id.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash & 0x7fffffff;
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
        id: stableTaskNotificationId(task.id),
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
