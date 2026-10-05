import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/app_mobile.dart';
import 'package:tylog/database/tylog_database.dart';

void main() {
  testWidgets('HomeScreen opens once and closes its database on dispose', (
    tester,
  ) async {
    final database = TyLogDatabase(NativeDatabase.memory());
    var opens = 0;
    var closes = 0;
    final closed = Completer<void>();
    final key = GlobalKey();
    Future<TyLogDatabase> opener() async {
      opens++;
      return database;
    }

    Future<void> closer(TyLogDatabase value) async {
      closes++;
      await value.close();
      closed.complete();
    }

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          key: key,
          databaseOpener: opener,
          databaseCloser: closer,
          startup: () async {},
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          key: key,
          databaseOpener: opener,
          databaseCloser: closer,
          startup: () async {},
        ),
      ),
    );
    expect(opens, 1);
    await tester.pumpWidget(const SizedBox());
    await closed.future;
    expect(closes, 1);
  });
  testWidgets('desktop exit awaits database close and closes only once', (
    tester,
  ) async {
    final database = TyLogDatabase(NativeDatabase.memory());
    final allowClose = Completer<void>();
    var closed = false;
    var closes = 0;
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          key: key,
          databaseOpener: () async => database,
          databaseCloser: (value) async {
            closes++;
            await allowClose.future;
            await value.close();
            closed = true;
          },
          startup: () async {},
        ),
      ),
    );
    final observer = key.currentState! as WidgetsBindingObserver;
    var exited = false;
    var closedAtExit = false;
    final exit = observer.didRequestAppExit().then((response) {
      closedAtExit = closed;
      exited = true;
      return response;
    });
    final repeatedExit = observer.didRequestAppExit();
    await tester.pump();
    expect(exited, isFalse);
    allowClose.complete();
    await tester.pump();
    expect(await exit, AppExitResponse.exit);
    expect(closedAtExit, isTrue);
    expect(await repeatedExit, AppExitResponse.exit);
    await tester.pumpWidget(const SizedBox());
    expect(closes, 1);
  });

  testWidgets('desktop exit is bounded when database close hangs', (
    tester,
  ) async {
    final database = TyLogDatabase(NativeDatabase.memory());
    final allowClose = Completer<void>();
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          key: key,
          databaseOpener: () async => database,
          databaseCloser: (value) async {
            await allowClose.future;
            await value.close();
          },
          startup: () async {},
        ),
      ),
    );
    AppExitResponse? response;
    final exit = (key.currentState! as WidgetsBindingObserver)
        .didRequestAppExit()
        .then((value) => response = value);
    await tester.pump();
    expect(response, isNull);
    await tester.pump(const Duration(seconds: 3));
    await exit;
    expect(response, AppExitResponse.exit);
    allowClose.complete();
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
  });
}
