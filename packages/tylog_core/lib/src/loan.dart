import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'enrich.dart';
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
  });

  final int line;
  final String text;
  final String ledgerSurface;
  final List<NoteRef> equipment;
  final NoteRef? person;
  final String? borrower;
  final String? purpose;
  final String? topic;
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
  List<EnrichDecision> decisions,
) {
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
          decision.status == EnrichStatus.linked &&
          target != null) {
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
      '  properties: (${properties.join(', ')}),\n'
      ')';
  final updated = replaceTaskStatus(lines.join('\n'), id, 'doing');
  return startTaskClock(updated, id, now.toIso8601String());
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

List<TaskRef> loanHistoryFor(VaultIndex index, String equipmentId) =>
    index.tasks
        .where(
          (task) =>
              task.properties['loan'] == true &&
              loanEquipmentIds(task).contains(equipmentId),
        )
        .toList()
      ..sort(_loanOrder);

Duration? loanOutFor(TaskRef task, DateTime now) {
  if (task.clocked.isEmpty) return null;
  final start = DateTime.tryParse(task.clocked.first.start);
  final endStamp = task.clocked.last.end;
  final end = endStamp == null ? now : DateTime.tryParse(endStamp);
  if (start == null || end == null) return null;
  return end.difference(start);
}
