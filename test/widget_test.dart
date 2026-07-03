import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/main.dart';

void main() {
  testWidgets('TyLog shell renders', (tester) async {
    await tester.pumpWidget(const TyLogApp());
    expect(find.text('TyLog'), findsOneWidget);
    expect(find.text('Save'), findsNothing);
    expect(find.byTooltip('Save'), findsNothing);
    expect(find.byTooltip('Journal'), findsOneWidget);
    expect(find.byTooltip('Source'), findsOneWidget);
    expect(find.byTooltip('Preview'), findsOneWidget);
    expect(find.byTooltip('Graph'), findsOneWidget);
    expect(find.byTooltip('Settings'), findsNothing);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.byTooltip('Quick actions'), findsOneWidget);
  });

  testWidgets('settings menu shows real app data', (tester) async {
    final version = await appVersion();

    await tester.pumpWidget(const TyLogApp());
    await tester.pump();

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsWidgets);
    expect(find.text('Local folder'), findsOneWidget);
    expect(find.text('Nextcloud settings'), findsOneWidget);
    expect(find.text('Sync server status'), findsOneWidget);
    expect(find.text('App version'), findsOneWidget);
    await tester.pump();
    expect(find.text(version), findsOneWidget);
  });

  testWidgets('source preview actions toggle both ways', (tester) async {
    await tester.pumpWidget(const TyLogApp());
    await tester.pump();

    await tester.tap(find.byTooltip('Source'));
    await tester.pump();
    await tester.tap(find.byTooltip('Preview'));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('journal mode hides Typst system prelude', (tester) async {
    await tester.pumpWidget(const TyLogApp());
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, isNot(contains('#import')));
    expect(field.controller?.text, isNot(contains('#note')));
  });

  testWidgets('editor changes are autosaved', (tester) async {
    await tester.pumpWidget(const TyLogApp());
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'autosave text');
    await tester.pump();

    expect(find.text('Autosave pending...'), findsOneWidget);
  });

  testWidgets('TyLog fits a phone-width screen', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const TyLogApp());
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
