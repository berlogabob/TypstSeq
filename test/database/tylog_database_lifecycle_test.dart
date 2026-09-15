import 'dart:async';

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
}
