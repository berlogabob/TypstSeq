import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'enrich.dart';
import 'loan_due.dart';
import 'models.dart';
import 'scanner.dart';
import 'values.dart';

const enrichLoanEntity = 'loan:track';

class EnrichLoanOffer {
  const EnrichLoanOffer({
    required this.line,
    required this.text,
    required this.equipment,
    required this.ledgerSurface,
    this.person,
    this.borrower,
    this.purpose,
    this.topic,
    this.due,
  });

  final int line;
  final String text;
  final String ledgerSurface;
  final List<NoteRef> equipment;
  final NoteRef? person;
  final String? borrower;
  final String? purpose;
  final String? topic;
  final String? due;
}

String _taskText(String line) => line
    .replaceAllMapped(
      RegExp(r'#tylog\.[\w-]+\([^)]*\)(\[([^\]]*)\])?'),
      (m) => m.group(2) ?? '',
    )
    .replaceFirst(RegExp(r'^\s*(?:\\-|-)\s+'), '');

List<EnrichLoanOffer> enrichLoanOffers(
  EnrichMentions mentions,
  String source,
  EnrichMemory memory,
  List<EnrichDecision> decisions, {
  DateTime? noteDate,
}) {
  final lines = source.split('\n');
  final code = enrichCodeLines(source);
  final offers = <EnrichLoanOffer>[];
  for (final hint in mentions.loans) {
    if (hint.line < 1 || hint.line > lines.length || code.contains(hint.line)) {
      continue;
    }
    final line = lines[hint.line - 1];
    if (line.trimLeft().startsWith('#tylog.task(') ||
        memory.isRejected(enrichPlainLine(line), enrichLoanEntity)) {
      continue;
    }
    final equipment = <NoteRef>[];
    NoteRef? person;
    void add(NoteRef note) {
      if (note.kind == 'equipment' && !equipment.any((e) => e.id == note.id)) {
        equipment.add(note);
      } else if (note.kind == 'person') {
        person ??= note;
      }
    }

    for (final match in RegExp(
      r'#tylog\.ref-note\("((?:\\.|[^"\\])*)"\)',
    ).allMatches(line)) {
      final target = match
          .group(1)!
          .replaceAllMapped(RegExp(r'\\(.)'), (m) => m.group(1)!);
      for (final note in memory.entities.values) {
        if (note.id == target ||
            note.title == target ||
            note.aliases.contains(target)) {
          add(note);
        }
      }
    }
    for (final decision in decisions) {
      final target = decision.target;
      if (decision.mention.line == hint.line &&
          (decision.mention.type == 'equipment' ||
              decision.mention.type == 'person') &&
          target != null &&
          // A lone equipment candidate in review is the item the user means:
          // waiting for a tap per item hid the offer until every link was
          // accepted by hand.
          (decision.status == EnrichStatus.linked ||
              (decision.status == EnrichStatus.review &&
                  decision.mention.type == 'equipment' &&
                  decision.candidates.length == 1))) {
        if (target.kind == decision.mention.type) add(target);
      }
    }
    if (equipment.isNotEmpty) {
      offers.add(
        EnrichLoanOffer(
          line: hint.line,
          text: _taskText(line),
          ledgerSurface: enrichPlainLine(line),
          equipment: equipment,
          person: person,
          borrower: hint.borrower,
          purpose: hint.purpose,
          topic: hint.topic,
          due: noteDate == null
              ? null
              : parseLoanDue(enrichPlainLine(line), noteDate),
        ),
      );
    }
  }
  return offers;
}

String loanTaskId(String noteId, EnrichLoanOffer offer) =>
    'loan-${sha256.convert(utf8.encode('$noteId|${offer.equipment.map((e) => e.id).join(',')}|${offer.text}')).toString().substring(0, 8)}';

String trackAsLoan(
  String source,
  EnrichLoanOffer offer,
  String id,
  DateTime now,
) {
  final lines = source.split('\n');
  if (offer.line < 1 ||
      offer.line > lines.length ||
      enrichCodeLines(source).contains(offer.line) ||
      lines[offer.line - 1].contains('#tylog.task(') ||
      _taskText(lines[offer.line - 1]) != offer.text ||
      RegExp(
        r'\bid\s*:\s*' + RegExp.escape(typstString(id)) + r'(?=\s*[,\)])',
      ).hasMatch(source) ||
      locateTypstCalls(
        source,
        names: const {'tylog.task'},
      ).any((call) => taskField(call.source, 'id') == id)) {
    return source;
  }
  final properties = <String>[
    '"loan": true',
    if (offer.purpose != null) '"purpose": ${typstString(offer.purpose!)}',
    '"equipment": (${offer.equipment.map((e) => typstString(e.id)).join(', ')},)',
    if (offer.borrower != null) '"borrower": ${typstString(offer.borrower!)}',
    if (offer.topic != null) '"topic": ${typstString(offer.topic!)}',
  ];
  lines[offer.line - 1] =
      '#tylog.task(\n'
      '  id: ${typstString(id)},\n'
      '  text: ${typstString(_taskText(lines[offer.line - 1]))},\n'
      '${offer.person == null ? '' : '  assignees: (${typstString(offer.person!.id)},),\n'}'
      '${offer.due == null ? '' : '  due: ${typstString(offer.due!)},\n'}'
      '  properties: (${properties.join(', ')}),\n'
      ')';
  final updated = replaceTaskStatus(lines.join('\n'), id, 'doing');
  // UTC with a Z, like every other clock stamp (applyTaskStatus callers pass
  // UTC). Readers parse with DateTime.tryParse, so older loans written with a
  // naive stamp are read as device-local time; new ones are unambiguous.
  return startTaskClock(updated, id, now.toUtc().toIso8601String());
}

/// Moves the line numbers a sidecar holds past [after] by [delta]. A tracked
/// loan turns one line into several, so without this the sidecar's later
/// offers point at the wrong lines (and, with its hash refreshed, are never
/// re-extracted).
Map<String, Object?> shiftEnrichLines(
  Map<String, Object?> json,
  int after,
  int delta,
) {
  if (delta == 0) return json;
  return {
    for (final entry in json.entries)
      entry.key:
          const {'mentions', 'markers', 'loans'}.contains(entry.key) &&
              entry.value is List
          ? [
              for (final item in entry.value as List)
                item is Map &&
                        item['line'] is int &&
                        (item['line'] as int) > after
                    ? {...item, 'line': (item['line'] as int) + delta}
                    : item,
            ]
          : entry.value,
  };
}

/// Consumes the converted line, including any unresolved new-person proposal.
Map<String, Object?> consumeEnrichLine(
  Map<String, Object?> json,
  int line,
  int delta,
) {
  final remaining = {
    for (final entry in json.entries)
      entry.key:
          const {'mentions', 'markers', 'loans'}.contains(entry.key) &&
              entry.value is List
          ? [
              for (final item in entry.value as List)
                if (item is! Map || item['line'] != line) item,
            ]
          : entry.value,
  };
  return shiftEnrichLines(remaining, line, delta);
}

/// Equipment ids of a loan task. The scanner keeps nested property values as
/// their Typst source (`("TL-0003",)`), so read both that and a real list.
List<String> loanEquipmentIds(TaskRef task) {
  final value = task.properties['equipment'];
  if (value is List) return [for (final id in value) '$id'];
  if (value is! String) return const [];
  return [
    for (final m in RegExp(r'"((?:\\.|[^"\\])*)"').allMatches(value)) m[1]!,
  ];
}

/// Whether [task] is a loan written by [trackAsLoan] that is not returned yet.
bool isOpenLoan(TaskRef task) =>
    task.properties['loan'] == true &&
    task.status != 'done' &&
    task.status != 'cancelled';

int _loanOrder(TaskRef a, TaskRef b) {
  final aStart = a.clocked.isEmpty
      ? null
      : DateTime.tryParse(a.clocked.first.start);
  final bStart = b.clocked.isEmpty
      ? null
      : DateTime.tryParse(b.clocked.first.start);
  final byStart = aStart == null
      ? (bStart == null ? 0 : 1)
      : (bStart == null ? -1 : bStart.compareTo(aStart));
  if (byStart != 0) return byStart;
  final byPath = b.notePath.compareTo(a.notePath);
  return byPath != 0 ? byPath : b.id.compareTo(a.id);
}

List<TaskRef> openLoanTasks(VaultIndex index) =>
    index.tasks.where(isOpenLoan).toList()..sort(_loanOrder);

Map<String, List<TaskRef>> openLoansByEquipment(VaultIndex index) {
  final grouped = <String, List<TaskRef>>{};
  for (final task in openLoanTasks(index)) {
    for (final id in loanEquipmentIds(task).toSet()) {
      (grouped[id] ??= []).add(task);
    }
  }
  return grouped;
}

TaskRef? openLoanFor(
  EnrichLoanOffer offer,
  Map<String, List<TaskRef>> byEquipment,
) {
  TaskRef? oldest;
  DateTime? oldestStart;
  for (final equipment in offer.equipment) {
    for (final task in byEquipment[equipment.id] ?? const <TaskRef>[]) {
      final start = task.clocked.isEmpty
          ? null
          : DateTime.tryParse(task.clocked.first.start);
      if (oldest == null ||
          (start != null &&
              (oldestStart == null || start.isBefore(oldestStart)))) {
        oldest = task;
        oldestStart = start;
      }
    }
  }
  return oldest;
}

String loanOutSinceText(TaskRef task) {
  final date = task.clocked.isEmpty
      ? 'unknown'
      : task.clocked.first.start.split('T').first;
  final borrower = task.properties['borrower'];
  final name = borrower is String && borrower.trim().isNotEmpty
      ? borrower
      : (task.assignees.isEmpty ? null : task.assignees.first);
  return 'Already out since $date${name == null || name.isEmpty ? '' : ' ($name)'}';
}

List<TaskRef> loanHistoryFor(VaultIndex index, String equipmentId) =>
    index.tasks
        .where(
          (task) =>
              task.properties['loan'] == true &&
              loanEquipmentIds(task).contains(equipmentId),
        )
        .toList()
      ..sort(_loanOrder);

class EquipmentUsage {
  const EquipmentUsage({
    required this.loans,
    required this.hoursOut,
    required this.hoursByPurpose,
    required this.borrowers,
    required this.lastReturned,
  });

  final int loans;
  final double hoursOut;
  final Map<String, double> hoursByPurpose;
  final Set<String> borrowers;
  final DateTime? lastReturned;
}

/// Summarizes recorded equipment loans, merging concurrent intervals per item.
Map<String, EquipmentUsage> equipmentUsage(
  VaultIndex index, {
  DateTime? from,
  DateTime? to,
}) {
  final endLimit = to ?? DateTime.now();
  final startLimit = from ?? DateTime.fromMillisecondsSinceEpoch(0);
  final intervals = <String, List<(DateTime, DateTime)>>{};
  final loanCounts = <String, int>{};
  final purposes = <String, Map<String, double>>{};
  final borrowers = <String, Set<String>>{};
  final returned = <String, DateTime>{};
  for (final task in index.tasks.where(
    (task) => task.properties['loan'] == true,
  )) {
    final ids = loanEquipmentIds(task).toSet();
    if (ids.isEmpty) continue;
    final taskIntervals = <(DateTime, DateTime)>[];
    DateTime? taskReturned;
    for (final clock in task.clocked) {
      final start = DateTime.tryParse(clock.start);
      final end = clock.end == null ? endLimit : DateTime.tryParse(clock.end!);
      if (start == null || end == null) continue;
      final clippedStart = start.isBefore(startLimit) ? startLimit : start;
      final clippedEnd = end.isAfter(endLimit) ? endLimit : end;
      if (clippedEnd.isAfter(clippedStart)) {
        taskIntervals.add((clippedStart, clippedEnd));
      }
      if (clock.end != null && !isOpenLoan(task)) {
        final actualEnd = DateTime.tryParse(clock.end!);
        if (actualEnd != null &&
            (taskReturned == null || actualEnd.isAfter(taskReturned))) {
          taskReturned = actualEnd;
        }
      }
    }
    if ((from != null || to != null) && taskIntervals.isEmpty) {
      continue;
    }
    for (final id in ids) {
      loanCounts.update(id, (count) => count + 1, ifAbsent: () => 1);
      final purpose = task.properties['purpose'];
      final key = purpose == null || '$purpose'.trim().isEmpty
          ? 'unspecified'
          : '$purpose';
      final hours = taskIntervals.fold<double>(
        0,
        (sum, interval) =>
            sum + interval.$2.difference(interval.$1).inSeconds / 3600,
      );
      purposes
          .putIfAbsent(id, () => {})
          .update(key, (value) => value + hours, ifAbsent: () => hours);
      intervals.putIfAbsent(id, () => []).addAll(taskIntervals);
      final names = borrowers.putIfAbsent(id, () => {});
      final borrower = task.properties['borrower'];
      if (borrower is String && borrower.trim().isNotEmpty) {
        names.add(borrower.trim());
      }
      names.addAll(task.assignees.where((name) => name.trim().isNotEmpty));
      if (taskReturned != null &&
          (returned[id] == null || taskReturned.isAfter(returned[id]!))) {
        returned[id] = taskReturned;
      }
    }
  }
  return {
    for (final id in loanCounts.keys)
      id: EquipmentUsage(
        loans: loanCounts[id]!,
        hoursOut: _mergedLoanHours(intervals[id]!),
        hoursByPurpose: Map.unmodifiable(purposes[id]!),
        borrowers: Set.unmodifiable(borrowers[id]!),
        lastReturned: returned[id],
      ),
  };
}

double _mergedLoanHours(List<(DateTime, DateTime)> intervals) {
  intervals.sort((a, b) => a.$1.compareTo(b.$1));
  if (intervals.isEmpty) return 0;
  var start = intervals.first.$1;
  var end = intervals.first.$2;
  var seconds = 0;
  for (final interval in intervals.skip(1)) {
    if (!interval.$1.isAfter(end)) {
      if (interval.$2.isAfter(end)) end = interval.$2;
    } else {
      seconds += end.difference(start).inSeconds;
      start = interval.$1;
      end = interval.$2;
    }
  }
  seconds += end.difference(start).inSeconds;
  return seconds / 3600;
}

Duration? loanOutFor(TaskRef task, DateTime now) {
  if (task.clocked.isEmpty) return null;
  final start = DateTime.tryParse(task.clocked.first.start);
  final endStamp = task.clocked.last.end;
  final end = endStamp == null ? now : DateTime.tryParse(endStamp);
  if (start == null || end == null) return null;
  return end.difference(start);
}

/// The most recently started work timer; loan intervals run independently.
TaskRef? runningWorkTask(Iterable<TaskRef> tasks) {
  TaskRef? latest;
  for (final task in tasks) {
    if (task.properties['loan'] == true || task.runningClock == null) continue;
    final start = DateTime.tryParse(task.runningClock!.start) ?? DateTime(0);
    final previous =
        DateTime.tryParse(latest?.runningClock?.start ?? '') ?? DateTime(0);
    if (latest == null || !start.isBefore(previous)) latest = task;
  }
  return latest;
}
