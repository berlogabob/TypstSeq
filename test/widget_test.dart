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
    expect(find.byTooltip('Settings'), findsOneWidget);
  });

  testWidgets('settings menu shows real app data', (tester) async {
    await tester.pumpWidget(const TyLogApp());
    await tester.pump();

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Local folder'), findsOneWidget);
    expect(find.text('Nextcloud settings'), findsOneWidget);
    expect(find.text('Sync server status'), findsOneWidget);
    expect(find.text('App version'), findsOneWidget);
    expect(find.text('1.0.0+6'), findsOneWidget);
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
