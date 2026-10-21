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

VaultIndex _index(List<NoteRef> notes) => VaultIndex(
  notesByPath: {for (final n in notes) n.path: n},
  backlinksByTarget: const {},
  tasks: const [],
);

void main() {
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
}
