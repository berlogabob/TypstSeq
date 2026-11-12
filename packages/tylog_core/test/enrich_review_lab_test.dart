import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tylog_core/tylog_core.dart';

// Fixture from the P30 report of 2026-11-12: three lab lines, two loan hints.
void main() {
  final dir = Directory('test/fixtures/lab_review');
  final files = {
    for (final f in dir.listSync().whereType<File>())
      if (f.path.endsWith('.typ') && !f.path.endsWith('day.typ'))
        'notes/${f.uri.pathSegments.last}': f.readAsStringSync(),
  };
  final daySource = File('${dir.path}/day.typ').readAsStringSync();
  const dayPath = 'daily/2026/11/2026-11-12.typ';
  final mentions = EnrichMentions.tryParse(
    jsonDecode(File('${dir.path}/mentions.json').readAsStringSync()),
  )!;

  EnrichDayResolution resolve(
    String source, [
    List<EnrichFeedback> fb = const [],
  ]) {
    final notes = {
      for (final e in files.entries) e.key: scanNote(e.key, e.value),
      dayPath: scanNote(dayPath, source),
    };
    final index = VaultIndex(notesByPath: notes, backlinksByTarget: const {});
    final memory = EnrichMemory.build(index, fb);
    return resolveEnrichDay(mentions, notes[dayPath]!, memory, index, source);
  }

  String show(EnrichDayResolution r) => [
    for (final d in r.decisions)
      '${d.mention.line} ${d.mention.surface} ${d.status.name} ${d.target?.id}',
    for (final l in r.loans) 'loan ${l.line} ${l.equipment.map((e) => e.id)}',
  ].join('\n');

  test('every line of the day yields chips and loans', () {
    final r = resolve(daySource);
    printOnError(r);
    final lines = r.decisions.map((d) => d.mention.line).toSet();
    expect(lines, containsAll([13, 14, 15]), reason: show(r));
    expect(r.loans.map((l) => l.line), containsAll([13, 15]), reason: show(r));
  });

  test('accepting the ESP32 link keeps lines 14 and 15 visible', () {
    final esp = scanNote('notes/TL-0102.typ', files['notes/TL-0102.typ']!);
    final linked = linkMentionInline(daySource, mentions.mentions[2], esp);
    expect(linked, isNot(daySource));
    final r = resolve(linked);
    final lines = r.decisions.map((d) => d.mention.line).toSet();
    expect(lines, containsAll([14, 15]), reason: show(r));
    expect(r.loans.map((l) => l.line), containsAll([13, 15]), reason: show(r));
  });
}

void printOnError(EnrichDayResolution r) {}
