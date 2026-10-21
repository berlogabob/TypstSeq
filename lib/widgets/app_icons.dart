import 'package:flutter/material.dart';

/// App-owned icon vocabulary. Actions use outlined glyphs where available;
/// overflow, close and warning follow the design-system decisions.
///
/// Map (meaning -> Material Icons glyph):
/// edit -> edit_outlined
/// settings -> settings_outlined
/// overflow -> more_horiz
/// close -> close
/// warning -> warning_amber_rounded
/// daily -> event_note_outlined
/// today -> today_outlined
/// screenshot -> screenshot_outlined
/// library -> library_books_outlined
/// read -> auto_stories_outlined
/// citation -> menu_book_outlined
/// folder -> folder_outlined
/// folderOpen -> folder_open_outlined
/// folderAdd -> create_new_folder_outlined
/// storageUnavailable -> folder_off_outlined
/// calendarDate -> calendar_month_outlined
/// calendarEvent -> event_outlined
/// calendars -> calendar_view_month_outlined
/// schedule -> schedule_outlined
/// queued -> hourglass_empty
/// agenda -> checklist_outlined
/// link -> link_outlined
/// backlinks -> schema_outlined
/// graph -> account_tree_outlined
/// sync -> sync_outlined
/// syncOk -> cloud_done_outlined
/// syncOff -> cloud_off_outlined
/// syncBusy -> autorenew
/// syncPaused -> sync_problem_outlined
/// syncReady -> cloud_sync_outlined
/// syncManaged -> devices_outlined
/// cloud -> cloud_outlined
///
/// Dates, events and calendar settings are distinct, as are daily notes and
/// editing. Sync states distinguish missing setup, unavailable storage, paused
/// work and system-managed sync. Material widgets keep their built-in icons.
class AppIcons {
  const AppIcons._();

  static const IconData edit = Icons.edit_outlined;
  static const IconData settings = Icons.settings_outlined;
  static const IconData overflow = Icons.more_horiz;
  static const IconData close = Icons.close;
  static const IconData delete = Icons.delete_outline;
  static const IconData expand = Icons.unfold_more;
  static const IconData collapse = Icons.unfold_less;
  static const IconData warning = Icons.warning_amber_rounded;
  static const IconData daily = Icons.event_note_outlined;
  static const IconData today = Icons.today_outlined;
  static const IconData screenshot = Icons.screenshot_outlined;
  static const IconData library = Icons.library_books_outlined;
  static const IconData read = Icons.auto_stories_outlined;
  static const IconData citation = Icons.menu_book_outlined;
  static const IconData folder = Icons.folder_outlined;
  static const IconData folderOpen = Icons.folder_open_outlined;
  static const IconData folderAdd = Icons.create_new_folder_outlined;
  static const IconData storageUnavailable = Icons.folder_off_outlined;
  static const IconData calendarDate = Icons.calendar_month_outlined;
  static const IconData calendarEvent = Icons.event_outlined;
  static const IconData calendars = Icons.calendar_view_month_outlined;
  static const IconData schedule = Icons.schedule_outlined;
  static const IconData queued = Icons.hourglass_empty;
  static const IconData agenda = Icons.checklist_outlined;
  static const IconData link = Icons.link_outlined;
  static const IconData backlinks = Icons.schema_outlined;
  static const IconData graph = Icons.account_tree_outlined;
  static const IconData sync = Icons.sync_outlined;
  static const IconData syncOk = Icons.cloud_done_outlined;
  static const IconData syncOff = Icons.cloud_off_outlined;
  static const IconData syncBusy = Icons.autorenew;
  static const IconData syncPaused = Icons.sync_problem_outlined;
  static const IconData syncReady = Icons.cloud_sync_outlined;
  static const IconData syncManaged = Icons.devices_outlined;
  static const IconData cloud = Icons.cloud_outlined;
}
