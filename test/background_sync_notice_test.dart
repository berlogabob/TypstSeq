import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/vault_storage.dart';
import 'package:tylog/widgets/background_sync_notice.dart';

void main() {
  testWidgets('battery notice follows exemption status and rechecks on resume', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    var ignoring = false;
    var opened = false;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      AndroidTreeVaultStorage.channel,
      (call) async => switch (call.method) {
        'isIgnoringBatteryOptimizations' => ignoring,
        'deviceManufacturer' => 'HUAWEI',
        'openBatterySettings' => opened = true,
        _ => null,
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        AndroidTreeVaultStorage.channel,
        null,
      ),
    );
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: BackgroundSyncNotice())),
    );
    await tester.pumpAndSettle();
    const notice = 'Background sync may stop: allow TyLog to run in background';
    expect(find.text(notice), findsOneWidget);
    expect(
      find.text(
        'Huawei: Settings > Battery > App launch > TyLog > Manage manually, enable all',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Battery settings'));
    await tester.pump();
    expect(opened, isTrue);

    ignoring = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text(notice), findsNothing);
    expect(find.text('Battery settings'), findsNothing);

    ignoring = false;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: BackgroundSyncNotice())),
    );
    await tester.pumpAndSettle();
    expect(find.text(notice), findsNothing);
    // Reset in the body: the binding checks debug vars before tear-downs run.
    debugDefaultTargetPlatformOverride = null;
  });
}
