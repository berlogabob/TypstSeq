import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/widgets/agenda_timeline.dart';

DateTime _at(int h, [int m = 0]) => DateTime(2026, 10, 21, h, m);

void main() {
  var tapped = '';
  List<AgendaEntry> entries() => [
    AgendaEntry(
      start: _at(14),
      end: _at(15),
      title: 'Gamma',
      onTap: () => tapped = 'Gamma',
    ),
    AgendaEntry(start: _at(9), end: _at(10), title: 'Alpha', detail: 'Room 1'),
    AgendaEntry(start: _at(11), end: _at(12, 30), title: 'Beta'),
  ];

  Future<void> pump(WidgetTester tester, DateTime now, {bool show = true}) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AgendaTimeline(
                entries: entries(),
                now: () => now,
                showNow: show,
              ),
            ),
          ),
        ),
      );

  double dotY(WidgetTester tester) =>
      tester.getCenter(find.byKey(const ValueKey('agenda-now-dot'))).dy -
      tester.getTopLeft(find.byType(AgendaTimeline)).dy;

  const h = kAgendaRowHeight;

  testWidgets('sorted rows with times and room; the running event is tinted', (
    tester,
  ) async {
    await pump(tester, _at(11, 30));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('agenda-current')),
        matching: find.text('Beta'),
      ),
      findsOneWidget,
    );
    expect(find.text('09:00'), findsOneWidget);
    expect(find.text('10:00'), findsOneWidget);
    expect(find.text('Room 1'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Alpha')).dy,
      lessThan(tester.getTopLeft(find.text('Gamma')).dy),
    );
    expect(dotY(tester), inExclusiveRange(h + h / 2, 2 * h + h / 2));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('before the first event the dot sits at the top', (
    tester,
  ) async {
    await pump(tester, _at(8));
    expect(find.byKey(const ValueKey('agenda-current')), findsNothing);
    expect(dotY(tester), lessThan(h / 2));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('after the last event the dot sits at the bottom', (
    tester,
  ) async {
    await pump(tester, _at(16));
    expect(dotY(tester), greaterThan(2 * h + h / 2));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('other days show no now dot; rows open their event', (
    tester,
  ) async {
    await pump(tester, _at(11, 30), show: false);
    expect(find.byKey(const ValueKey('agenda-now-dot')), findsNothing);
    await tester.tap(find.text('Gamma'));
    expect(tapped, 'Gamma');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a long title ellipsizes instead of shrinking', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    const long = 'Estratégias Comerciais e Gestão de Vendas e mais palavras';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgendaTimeline(
            entries: [AgendaEntry(start: _at(9), end: _at(10), title: long)],
            now: () => _at(8),
          ),
        ),
      ),
    );
    final scale =
        tester.getRect(find.text(long)).height /
        tester.getSize(find.text(long)).height;
    expect(scale, greaterThan(0.9));
    await tester.pumpWidget(const SizedBox());
  });
}
