import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/models.dart';
import 'package:tylog/widgets/app_icons.dart';
import 'package:tylog/widgets/screenshot_strip.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

NoteRef _shot(String id) => NoteRef(
  id: id,
  path: 'screenshots/2026/10/$id.typ',
  title: 'Shot $id',
  kind: 'screenshot',
  date: '2026-10-21',
  outgoingLinks: const [],
  properties: const {'captured_at': '2026-10-21T09:07:00'},
);

NoteRef _note(
  String id,
  String kind, {
  String? date,
  Map<String, Object?> properties = const {},
}) => NoteRef(
  id: id,
  path: '$kind/$id.typ',
  title: id,
  kind: kind,
  date: date,
  outgoingLinks: const [],
  properties: properties,
);

VaultIndex _index(List<NoteRef> notes) => VaultIndex(
  notesByPath: {for (final n in notes) n.path: n},
  backlinksByTarget: const {},
  tasks: const [],
);

void main() {
  test('incomingOnDay selects new notes for that day', () {
    final screenshot = _shot('shot-aaaaaaaaaaaaaaaa');
    final idea = _note('idea', 'idea', date: '2026-10-21');
    final audio = _note('audio-20261021-153042', 'audio');
    final archived = _note(
      'old-idea',
      'idea',
      date: '2026-10-21',
      properties: const {'attention': 'archived'},
    );
    final other = _note('other', 'idea', date: '2026-10-22');
    expect(
      incomingOnDay(
        _index([idea, audio, archived, other, screenshot]),
        '2026-10-21',
      ),
      [screenshot, audio, idea],
    );
  });

  testWidgets('long press dismiss calls onDecide', (tester) async {
    final note = _shot('shot-aaaaaaaaaaaaaaaa');
    (NoteRef?, String?)? decision;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScreenshotStrip(
            index: _index([note]),
            day: '2026-10-21',
            onOpenPath: (_) {},
            incoming: true,
            onDecide: (n, action) => decision = (n, action),
          ),
        ),
      ),
    );
    await tester.longPress(find.text(note.title));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();
    expect(decision, (note, 'dismissed'));
  });

  testWidgets('external booking renders and tap does not open a vault path', (
    tester,
  ) async {
    var opened = false;
    final booking = NoteRef(
      id: 'olt-activity-4',
      path: 'olt:activities/4',
      title: 'Lab booking',
      kind: 'booking',
      outgoingLinks: const [],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScreenshotStrip(
            index: _index(const []),
            day: '2026-10-21',
            onOpenPath: (_) => opened = true,
            incoming: true,
            external: [booking],
          ),
        ),
      ),
    );
    expect(find.text('Lab booking'), findsOneWidget);
    expect(find.byIcon(Icons.event_available), findsOneWidget);
    await tester.tap(find.text('Lab booking'));
    await tester.pumpAndSettle();
    expect(opened, isFalse);
  });

  testWidgets('an index update keeps thumbnails: no reread, no placeholder', (
    tester,
  ) async {
    final reads = <String, int>{};
    Future<Uint8List?> resolve(String path) async {
      reads[path] = (reads[path] ?? 0) + 1;
      return _png;
    }

    Widget strip(List<NoteRef> notes) => MaterialApp(
      home: Scaffold(
        body: ScreenshotStrip(
          index: _index(notes),
          day: '2026-10-21',
          onOpenPath: (_) {},
          imageResolver: resolve,
        ),
      ),
    );

    final a = _shot('shot-aaaaaaaaaaaaaaaa');
    final b = _shot('shot-bbbbbbbbbbbbbbbb');
    await tester.pumpWidget(strip([a, b]));
    await tester.pumpAndSettle();
    expect(reads.values, everyElement(1));
    expect(find.byIcon(AppIcons.screenshot), findsNothing);

    // A sync/index update publishes a new index with the same screenshots.
    await tester.pumpWidget(strip([a, b]));
    expect(find.byIcon(AppIcons.screenshot), findsNothing);
    await tester.pumpAndSettle();
    expect(reads.values, everyElement(1));

    // A new screenshot loads only its own image.
    final c = _shot('shot-cccccccccccccccc');
    await tester.pumpWidget(strip([a, b, c]));
    await tester.pumpAndSettle();
    expect(reads.length, 3);
    expect(reads.values, everyElement(1));
  });

  test('appendAboveAutoBlock keeps user text out of the entities block', () {
    expect(appendAboveAutoBlock('= Day\n- a\n', '- b'), '= Day\n- a\n- b\n');
    expect(
      appendAboveAutoBlock('- a\n\n// tylog:auto-entities\n#x\n', '- b'),
      '- a\n- b\n\n// tylog:auto-entities\n#x\n',
    );
  });
}
